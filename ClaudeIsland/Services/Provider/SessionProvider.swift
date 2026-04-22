//
//  SessionProvider.swift
//  ClaudeIsland
//
//  Abstracts a source of Claude-like coding sessions (Claude Code, OpenCode,
//  Codex, ...). Each provider installs its own hook/plugin that emits events
//  to our shared Unix socket, tagged with its `id`. UI components query a
//  provider's `capabilities` to decide whether features like tool approval
//  or chat-send are available for a given session.
//

import Foundation

/// Per-provider feature flags. The Muxy fork currently only implements Claude
/// Code; values here describe what OpenCode / Codex *would* support once
/// their providers are added.
struct ProviderCapabilities: Sendable {
    /// Can the user type a prompt in the chat pane and send it to this
    /// session? Requires tmux paste or Muxy's remote terminalInput API.
    let canSendMessages: Bool
    /// Does the provider raise per-tool approval requests that the user can
    /// allow/deny from the notch? Only Claude Code has this today.
    let canApproveTools: Bool
    /// Do we get a JSONL conversation log we can replay as chat history?
    let hasChatHistory: Bool

    static let claudeCode = ProviderCapabilities(
        canSendMessages: true,
        canApproveTools: true,
        hasChatHistory: true
    )

    /// Reasonable fallback for unknown/unregistered providers coming off the
    /// socket — treat them as notification-only (no interactive features)
    /// until we learn otherwise.
    static let notificationOnly = ProviderCapabilities(
        canSendMessages: false,
        canApproveTools: false,
        hasChatHistory: false
    )
}

/// Anything that can surface coding sessions into the notch.
protocol SessionProvider: Sendable {
    /// Stable identifier — stored in `SessionState.providerId` and sent on
    /// every hook payload so the app can route events back to the provider.
    var id: String { get }
    var displayName: String { get }

    /// CLI executable name(s) we probe to decide whether to install hooks.
    var executableNames: [String] { get }

    var capabilities: ProviderCapabilities { get }

    /// Is the underlying tool installed on this machine?
    func isToolInstalled() -> Bool

    /// Install the provider's hook/plugin so it emits events to our socket.
    func install() throws

    /// Remove hooks/plugins we installed.
    func uninstall() throws

    /// Whether our hook/plugin is currently installed.
    func isHookInstalled() -> Bool
}

extension SessionProvider {
    /// Default probe: look in the usual places for the named executables.
    func isToolInstalled() -> Bool {
        let home = NSHomeDirectory()
        let searchPaths = executableNames.flatMap { name in
            [
                "\(home)/.local/bin/\(name)",
                "/usr/local/bin/\(name)",
                "/opt/homebrew/bin/\(name)",
                "\(home)/.claude/local/\(name)",
            ]
        }
        return searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// ID constants to avoid stringly-typed bugs at call sites.
enum ProviderID {
    static let claudeCode = "claude_code"
    static let openCode = "opencode"
    static let codex = "codex"
}
