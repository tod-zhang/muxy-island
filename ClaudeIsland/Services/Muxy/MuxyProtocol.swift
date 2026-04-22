//
//  MuxyProtocol.swift
//  ClaudeIsland
//
//  Minimal subset of Muxy's remote WebSocket protocol (docs/remote-server.md
//  in muxy-app/muxy). We only model the messages Vibe Notch actually sends
//  or needs to decode — if Muxy adds fields, unknown keys are silently
//  ignored by JSONDecoder, so this stays forward-compatible as long as the
//  fields we rely on don't change shape.
//

import Foundation

// MARK: - Envelope

nonisolated enum MuxyWireType: String, Codable, Sendable {
    case request
    case response
    case event
}

/// Outbound request envelope: `{ "type": "request", "payload": { ... } }`
nonisolated struct MuxyRequestEnvelope: Encodable, Sendable {
    let type = MuxyWireType.request
    let payload: MuxyRequest

    enum CodingKeys: String, CodingKey {
        case type, payload
    }
}

nonisolated struct MuxyRequest: Encodable, Sendable {
    let id: String
    let method: String
    let params: MuxyParams?
}

/// Polymorphic params: encoded as `{ "type": "<method>", "value": <payload> }`
/// matching Muxy's server-side MuxyParams enum.
nonisolated enum MuxyParams: Encodable, Sendable {
    case authenticateDevice(deviceID: String, deviceName: String, token: String)
    case pairDevice(deviceID: String, deviceName: String, token: String)
    case getWorkspace(projectID: String)
    case selectProject(projectID: String)
    case selectWorktree(projectID: String, worktreeID: String)
    case focusArea(projectID: String, areaID: String)
    case selectTab(projectID: String, areaID: String, tabID: String)
    case getTerminalContent(paneID: String)
    case takeOverPane(paneID: String, cols: UInt32, rows: UInt32)
    case releasePane(paneID: String)
    case terminalInput(paneID: String, text: String)

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .authenticateDevice(deviceID, deviceName, token):
            try container.encode("authenticateDevice", forKey: .type)
            try container.encode(DevicePayload(deviceID: deviceID, deviceName: deviceName, token: token), forKey: .value)
        case let .pairDevice(deviceID, deviceName, token):
            try container.encode("pairDevice", forKey: .type)
            try container.encode(DevicePayload(deviceID: deviceID, deviceName: deviceName, token: token), forKey: .value)
        case let .getWorkspace(projectID):
            try container.encode("getWorkspace", forKey: .type)
            try container.encode(["projectID": projectID], forKey: .value)
        case let .selectProject(projectID):
            try container.encode("selectProject", forKey: .type)
            try container.encode(["projectID": projectID], forKey: .value)
        case let .selectWorktree(projectID, worktreeID):
            try container.encode("selectWorktree", forKey: .type)
            try container.encode(["projectID": projectID, "worktreeID": worktreeID], forKey: .value)
        case let .focusArea(projectID, areaID):
            try container.encode("focusArea", forKey: .type)
            try container.encode(["projectID": projectID, "areaID": areaID], forKey: .value)
        case let .selectTab(projectID, areaID, tabID):
            try container.encode("selectTab", forKey: .type)
            try container.encode(["projectID": projectID, "areaID": areaID, "tabID": tabID], forKey: .value)
        case let .getTerminalContent(paneID):
            try container.encode("getTerminalContent", forKey: .type)
            try container.encode(["paneID": paneID], forKey: .value)
        case let .takeOverPane(paneID, cols, rows):
            try container.encode("takeOverPane", forKey: .type)
            try container.encode(TakeOverPayload(paneID: paneID, cols: cols, rows: rows), forKey: .value)
        case let .releasePane(paneID):
            try container.encode("releasePane", forKey: .type)
            try container.encode(["paneID": paneID], forKey: .value)
        case let .terminalInput(paneID, text):
            try container.encode("terminalInput", forKey: .type)
            try container.encode(TerminalInputPayload(paneID: paneID, text: text), forKey: .value)
        }
    }

    private struct DevicePayload: Encodable, Sendable {
        let deviceID: String
        let deviceName: String
        let token: String
    }

    private struct TakeOverPayload: Encodable, Sendable {
        let paneID: String
        let cols: UInt32
        let rows: UInt32
    }

    private struct TerminalInputPayload: Encodable, Sendable {
        let paneID: String
        let text: String
    }
}

// MARK: - Inbound decoding

/// We only decode response envelopes. Events are received but ignored.
nonisolated struct MuxyInboundEnvelope: Decodable, Sendable {
    let type: MuxyWireType
    let payload: MuxyInboundPayload
}

nonisolated enum MuxyInboundPayload: Decodable, Sendable {
    case response(MuxyResponse)
    case event  // decoded shape intentionally discarded
    case unknown

    init(from decoder: Decoder) throws {
        // Try response first — has `id` + `result`/`error`
        if let response = try? MuxyResponse(from: decoder) {
            self = .response(response)
            return
        }
        self = .unknown
    }
}

nonisolated struct MuxyResponse: Decodable, Sendable {
    let id: String
    let result: MuxyResult?
    let error: MuxyErrorDTO?
}

nonisolated struct MuxyErrorDTO: Decodable, Error, CustomStringConvertible, Sendable {
    let code: Int
    let message: String

    var description: String { "MuxyError(code: \(code), message: \(message))" }
}

/// Tagged-union result. We only care about `workspace`, `pairing`, `terminalCells`, and `ok`.
nonisolated enum MuxyResult: Decodable, Sendable {
    case ok
    case pairing(PairingResult)
    case workspace(Workspace)
    case terminalCells(TerminalCells)
    case other  // any other result type we don't need

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ok":
            self = .ok
        case "pairing":
            self = .pairing(try container.decode(PairingResult.self, forKey: .value))
        case "workspace":
            self = .workspace(try container.decode(Workspace.self, forKey: .value))
        case "terminalCells":
            self = .terminalCells(try container.decode(TerminalCells.self, forKey: .value))
        default:
            self = .other
        }
    }
}

/// Response from `getTerminalContent`. We only need cols/rows to preserve
/// the PTY size during a takeOverPane; the full cells array is discarded
/// via CodingKeys (we never decode it).
nonisolated struct TerminalCells: Decodable, Sendable {
    let cols: UInt32
    let rows: UInt32

    private enum CodingKeys: String, CodingKey {
        case cols, rows
    }
}

nonisolated struct PairingResult: Decodable, Sendable {
    let clientID: String
    let deviceName: String
}

// MARK: - Workspace tree (pruned to what NavigationResolver needs)

nonisolated struct Workspace: Decodable, Sendable {
    let projectID: String
    let worktreeID: String
    let focusedAreaID: String?
    let root: SplitNode
}

nonisolated indirect enum SplitNode: Decodable, Sendable {
    case tabArea(TabArea)
    case split(SplitBranch)

    private enum CodingKeys: String, CodingKey {
        case type, tabArea, split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "tabArea":
            self = .tabArea(try container.decode(TabArea.self, forKey: .tabArea))
        case "split":
            self = .split(try container.decode(SplitBranch.self, forKey: .split))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown split node type: \(type)")
        }
    }
}

nonisolated struct SplitBranch: Decodable, Sendable {
    let id: String
    let first: SplitNode
    let second: SplitNode
}

nonisolated struct TabArea: Decodable, Sendable {
    let id: String
    let tabs: [Tab]
}

nonisolated struct Tab: Decodable, Sendable {
    let id: String
    let paneID: String?
}

// MARK: - Tree walking

extension Workspace {
    /// Walk the tree until we find a tab whose paneID matches. Returns the
    /// containing areaID + that tabID.
    nonisolated func resolve(paneID: String) -> (areaID: String, tabID: String)? {
        resolve(paneID: paneID, in: root)
    }

    private nonisolated func resolve(paneID: String, in node: SplitNode) -> (areaID: String, tabID: String)? {
        switch node {
        case .tabArea(let area):
            if let tab = area.tabs.first(where: { $0.paneID == paneID }) {
                return (area.id, tab.id)
            }
            return nil
        case .split(let branch):
            return resolve(paneID: paneID, in: branch.first)
                ?? resolve(paneID: paneID, in: branch.second)
        }
    }
}
