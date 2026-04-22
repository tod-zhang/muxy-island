//
//  MuxyClient.swift
//  ClaudeIsland
//
//  WebSocket client for Muxy's remote API (docs/remote-server.md).
//  Handles pairing, authentication, and request/response correlation.
//
//  Endpoint is ws://127.0.0.1:4865 and must be enabled in Muxy's
//  Settings → Mobile → "Allow mobile device connection". First-time use
//  requires the user to approve a pairing request that Muxy prompts for
//  on the Mac; we persist the deviceID + token so later runs skip that.
//

import Foundation
import os.log

nonisolated let muxyClientLogger = Logger(subsystem: "com.claudeisland", category: "MuxyClient")

/// Errors raised by MuxyClient
nonisolated enum MuxyClientError: Error, CustomStringConvertible, Sendable {
    case connectFailed(underlying: Error?)
    case decodeFailed
    case serverError(code: Int, message: String)
    case timedOut
    case disconnected

    var description: String {
        switch self {
        case let .connectFailed(err): return "Connect failed: \(err?.localizedDescription ?? "unknown")"
        case .decodeFailed: return "Decode failed"
        case let .serverError(code, message): return "Server error \(code): \(message)"
        case .timedOut: return "Timed out"
        case .disconnected: return "Disconnected"
        }
    }
}

/// Persistent credentials for a paired device.
nonisolated private struct MuxyCredentials: Sendable {
    let deviceID: String
    let token: String

    static let deviceIDKey = "muxy.integration.deviceID"
    static let tokenKey = "muxy.integration.token"

    /// Load from UserDefaults. The token is local-network-only and low-value
    /// (grants access to a local Muxy instance), so UserDefaults is fine —
    /// Keychain would be more proper but adds complexity with no real gain.
    static func loadOrCreate() -> MuxyCredentials {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: deviceIDKey) ?? {
            let id = UUID().uuidString
            defaults.set(id, forKey: deviceIDKey)
            return id
        }()
        let token = defaults.string(forKey: tokenKey) ?? {
            let t = Self.randomToken()
            defaults.set(t, forKey: tokenKey)
            return t
        }()
        return MuxyCredentials(deviceID: deviceID, token: token)
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Single shared WebSocket connection. Reconnects lazily on demand.
actor MuxyClient {
    static let shared = MuxyClient()

    private let endpoint = URL(string: "ws://127.0.0.1:4865")!
    private let deviceName = "Vibe Notch"
    private let creds: MuxyCredentials

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<MuxyResponse, Never>] = [:]
    private var isAuthenticated = false

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private let decoder = JSONDecoder()

    private init() {
        self.creds = MuxyCredentials.loadOrCreate()
    }

    // MARK: - Public API

    /// Send a request and await the response. Ensures the socket is connected
    /// and authenticated first (pairing automatically if necessary).
    func request(_ params: MuxyParams) async throws -> MuxyResult {
        try await ensureAuthenticated()
        return try await send(params)
    }

    /// Check whether Muxy's remote server is reachable at all. Used by the UI
    /// to decide whether to show the focus button.
    func isReachable() async -> Bool {
        if socket != nil { return true }
        do {
            try await connect()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Connection lifecycle

    private func connect() async throws {
        guard socket == nil else { return }

        let task = URLSession.shared.webSocketTask(with: endpoint)
        socket = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isAuthenticated = false

        // Fail any in-flight requests
        for (_, cont) in pending {
            cont.resume(returning: MuxyResponse(
                id: "",
                result: nil,
                error: MuxyErrorDTO(code: -1, message: "Disconnected")
            ))
        }
        pending.removeAll()
    }

    private func receiveLoop() async {
        guard let socket else { return }
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                handle(message)
            } catch {
                muxyClientLogger.debug("WebSocket receive ended: \(error.localizedDescription, privacy: .public)")
                handleDisconnect()
                return
            }
        }
    }

    private func handleDisconnect() {
        disconnect()
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        guard let envelope = try? decoder.decode(MuxyInboundEnvelope.self, from: data) else {
            muxyClientLogger.debug("Dropping unparseable Muxy frame")
            return
        }

        switch envelope.payload {
        case .response(let response):
            if let cont = pending.removeValue(forKey: response.id) {
                cont.resume(returning: response)
            } else {
                muxyClientLogger.debug("Response for unknown id \(response.id, privacy: .public)")
            }
        case .event, .unknown:
            // Events are ignored — we don't subscribe and the protocol sends
            // all broadcast events regardless. Nothing to do.
            break
        }
    }

    // MARK: - Auth

    private func ensureAuthenticated() async throws {
        if isAuthenticated { return }
        try await connect()

        // First attempt: silent re-auth with stored creds. If Muxy has
        // forgotten the device (fresh install, settings wiped) this returns
        // 401 and we fall through to pairDevice.
        do {
            _ = try await sendExpectingAuth(.authenticateDevice(
                deviceID: creds.deviceID,
                deviceName: deviceName,
                token: creds.token
            ))
            isAuthenticated = true
            return
        } catch MuxyClientError.serverError(code: 401, _) {
            // fall through to pairing
        }

        // Pairing — blocks until the user approves the prompt Muxy displays
        // on the Mac. May take minutes; no timeout on our side.
        _ = try await sendExpectingAuth(.pairDevice(
            deviceID: creds.deviceID,
            deviceName: deviceName,
            token: creds.token
        ))
        isAuthenticated = true
    }

    /// Variant of send() that doesn't require prior authentication — used for
    /// the auth/pair calls themselves.
    @discardableResult
    private func sendExpectingAuth(_ params: MuxyParams) async throws -> MuxyResult {
        try await send(params)
    }

    // MARK: - Send

    private func send(_ params: MuxyParams) async throws -> MuxyResult {
        guard let socket else { throw MuxyClientError.disconnected }

        let id = UUID().uuidString
        let envelope = MuxyRequestEnvelope(payload: MuxyRequest(
            id: id,
            method: methodName(params),
            params: params
        ))

        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw MuxyClientError.decodeFailed
        }

        let response: MuxyResponse = await withCheckedContinuation { cont in
            pending[id] = cont
            let task = Task {
                do {
                    try await socket.send(.data(data))
                } catch {
                    if let cont = pending.removeValue(forKey: id) {
                        cont.resume(returning: MuxyResponse(
                            id: id,
                            result: nil,
                            error: MuxyErrorDTO(code: -1, message: "Send failed: \(error.localizedDescription)")
                        ))
                    }
                }
            }
            _ = task
        }

        if let err = response.error {
            throw MuxyClientError.serverError(code: err.code, message: err.message)
        }
        guard let result = response.result else {
            throw MuxyClientError.decodeFailed
        }
        return result
    }

    private nonisolated func methodName(_ params: MuxyParams) -> String {
        switch params {
        case .authenticateDevice: return "authenticateDevice"
        case .pairDevice: return "pairDevice"
        case .getWorkspace: return "getWorkspace"
        case .selectProject: return "selectProject"
        case .selectWorktree: return "selectWorktree"
        case .focusArea: return "focusArea"
        case .selectTab: return "selectTab"
        case .getTerminalContent: return "getTerminalContent"
        case .takeOverPane: return "takeOverPane"
        case .releasePane: return "releasePane"
        case .terminalInput: return "terminalInput"
        }
    }
}
