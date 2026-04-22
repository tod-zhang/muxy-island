//
//  MuxyController.swift
//  ClaudeIsland
//
//  High-level "jump to Muxy session" API. Mirrors what Muxy's own
//  NotificationNavigator does internally: select the project+worktree,
//  find the tab that owns the given paneID, then focus its area and tab.
//

import AppKit
import Foundation
import os.log

nonisolated let muxyControllerLogger = Logger(subsystem: "com.claudeisland", category: "MuxyController")

/// macOS bundle identifier for the Muxy terminal app.
private let muxyBundleID = "com.muxy.app"

actor MuxyController {
    static let shared = MuxyController()

    private init() {}

    /// Navigate Muxy to the pane that owns the given Claude session. Brings
    /// Muxy to the front on success. Returns false on any failure (server
    /// unreachable, pairing denied, pane no longer exists, etc.).
    @discardableResult
    func focus(paneID: String, projectID: String, worktreeID: String?) async -> Bool {
        do {
            // Select the project first — idempotent on the server side.
            _ = try await MuxyClient.shared.request(.selectProject(projectID: projectID))

            if let worktreeID {
                _ = try await MuxyClient.shared.request(.selectWorktree(
                    projectID: projectID,
                    worktreeID: worktreeID
                ))
            }

            let workspace = try await getWorkspace(projectID: projectID)
            guard let location = workspace.resolve(paneID: paneID) else {
                muxyControllerLogger.warning("Muxy pane \(paneID, privacy: .public) not found in workspace — tab was likely closed")
                await activateMuxyApp()
                return false
            }

            _ = try await MuxyClient.shared.request(.focusArea(
                projectID: projectID,
                areaID: location.areaID
            ))
            _ = try await MuxyClient.shared.request(.selectTab(
                projectID: projectID,
                areaID: location.areaID,
                tabID: location.tabID
            ))

            await activateMuxyApp()
            return true
        } catch {
            muxyControllerLogger.error("Muxy focus failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func getWorkspace(projectID: String) async throws -> Workspace {
        let result = try await MuxyClient.shared.request(.getWorkspace(projectID: projectID))
        guard case let .workspace(ws) = result else {
            throw MuxyClientError.decodeFailed
        }
        return ws
    }

    /// Type text into a Muxy pane as if the user typed it. `\n` is appended
    /// so Claude Code treats the message as a submitted prompt.
    ///
    /// Muxy requires pane ownership before accepting input, so we briefly
    /// take ownership (preserving the current PTY size so nothing resizes
    /// visibly) and release immediately after. The ownership change is not
    /// displayed to the user — it only affects who can drive terminalInput.
    @discardableResult
    func sendInput(paneID: String, text: String) async -> Bool {
        // Phase 1: acquire ownership with current PTY size so the pane
        // doesn't visibly resize during the handover.
        do {
            let cells = try await getTerminalSize(paneID: paneID)
            _ = try await MuxyClient.shared.request(.takeOverPane(
                paneID: paneID,
                cols: cells.cols,
                rows: cells.rows
            ))
        } catch {
            muxyControllerLogger.error("Muxy takeOverPane failed: \(String(describing: error), privacy: .public)")
            return false
        }

        // Phase 2: send the text. Always release afterwards regardless of
        // whether the send succeeded — leaving ownership stuck on Vibe Notch
        // would lock the user out of their own pane.
        var sent = false
        do {
            _ = try await MuxyClient.shared.request(.terminalInput(
                paneID: paneID,
                text: text + "\n"
            ))
            sent = true
        } catch {
            muxyControllerLogger.error("Muxy terminalInput failed: \(String(describing: error), privacy: .public)")
        }

        _ = try? await MuxyClient.shared.request(.releasePane(paneID: paneID))
        return sent
    }

    private func getTerminalSize(paneID: String) async throws -> TerminalCells {
        let result = try await MuxyClient.shared.request(.getTerminalContent(paneID: paneID))
        guard case let .terminalCells(cells) = result else {
            throw MuxyClientError.decodeFailed
        }
        return cells
    }

    /// Bring Muxy.app to the foreground. The WebSocket focuses panes within
    /// Muxy but does nothing about its window ordering — that's our job.
    @MainActor
    private func activateMuxyApp() {
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == muxyBundleID
        }
        running?.activate()
    }
}
