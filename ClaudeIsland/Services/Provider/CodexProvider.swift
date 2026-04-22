//
//  CodexProvider.swift
//  ClaudeIsland
//
//  Codex CLI (openai/codex) ships with a Claude-Code-compatible hook engine
//  — event names, config shape, and stdin JSON all match. So we reuse the
//  same Python hook script the Claude Code provider installs; the only
//  difference is the registration file (`~/.codex/hooks.json` vs Claude's
//  `~/.claude/settings.json`) and the `--provider codex` argv flag so the
//  script tags outgoing events with the right provider id.
//
//  Codex doesn't expose a JSONL conversation log the same way Claude Code
//  does (it uses SQLite). We therefore advertise `hasChatHistory = false`
//  for now — sessions appear in the notch and can be jumped-to, but
//  opening their chat view would show nothing useful.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "CodexProvider")

struct CodexProvider: SessionProvider {
    let id = ProviderID.codex
    let displayName = "Codex"
    let executableNames = ["codex"]
    /// Approval is supported because Codex implements PermissionRequest with
    /// Claude Code semantics. Message-send works via the same tmux/Muxy
    /// terminalInput path Claude Code uses. Chat history stays off until we
    /// add a SQLite reader for Codex's state.db.
    let capabilities = ProviderCapabilities(
        canSendMessages: true,
        canApproveTools: true,
        hasChatHistory: false
    )

    // MARK: - Paths

    private static let codexHome: String = {
        if let override = Foundation.ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.codex"
    }()

    private static var hooksFile: URL {
        URL(fileURLWithPath: codexHome).appendingPathComponent("hooks.json")
    }

    /// Marker used to recognize hook entries we wrote, so we can clean them
    /// up on uninstall without clobbering hooks the user may have added by
    /// hand.
    private static let marker = "claude-island-state.py"

    // MARK: - SessionProvider

    func isToolInstalled() -> Bool {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(home)/.codex/bin/codex",
        ]
        if paths.contains(where: { fm.isExecutableFile(atPath: $0) }) {
            return true
        }
        // Fallback — Codex CLI can live in nonstandard npm / nvm prefixes
        // we can't reliably enumerate. The presence of `~/.codex/config.toml`
        // (or hooks.json) is a strong signal the user has used Codex locally,
        // so we treat that as install-present too.
        let configSignals = [
            "\(home)/.codex/config.toml",
            "\(home)/.codex/hooks.json",
        ]
        return configSignals.contains { fm.fileExists(atPath: $0) }
    }

    func install() throws {
        // The Python hook is shared across providers and lives in
        // ~/.claude/hooks/. Ensure it's present even when only Codex is
        // installed (no Claude Code on this machine).
        HookInstaller.ensureScriptInstalled()
        let scriptPath = ClaudePaths.hooksDir
            .appendingPathComponent("claude-island-state.py")
            .path

        try FileManager.default.createDirectory(
            atPath: Self.codexHome,
            withIntermediateDirectories: true
        )

        let python = Self.detectPython()
        let command = "\(python) \(scriptPath) --provider codex"

        // Build the hooks.json payload. Event names mirror Claude Code's
        // wire format, which Codex's ClaudeHooksEngine speaks natively.
        let hookEntry: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": 86400,
        ]
        let matcherGroup: [String: Any] = [
            "matcher": "*",
            "hooks": [hookEntry],
        ]
        let matcherGroupNoMatcher: [String: Any] = [
            "hooks": [hookEntry],
        ]

        let events: [(String, [[String: Any]])] = [
            ("PreToolUse", [matcherGroup]),
            ("PostToolUse", [matcherGroup]),
            ("PermissionRequest", [matcherGroup]),
            ("SessionStart", [matcherGroupNoMatcher]),
            ("UserPromptSubmit", [matcherGroupNoMatcher]),
            ("Stop", [matcherGroupNoMatcher]),
        ]

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.hooksFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Strip any previously-installed Muxy Island entries so we don't
        // duplicate if the user runs install twice.
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries = entries.compactMap { Self.removingOurHooks(from: $0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        for (event, config) in events {
            let existing = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = existing + config
        }

        json["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: Self.hooksFile)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: Self.hooksFile.path) else { return }
        guard let data = try? Data(contentsOf: Self.hooksFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries = entries.compactMap { Self.removingOurHooks(from: $0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        let newData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try newData.write(to: Self.hooksFile)
    }

    func isHookInstalled() -> Bool {
        guard let data = try? Data(contentsOf: Self.hooksFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { continue }
                for hook in entryHooks {
                    if let cmd = hook["command"] as? String, cmd.contains(Self.marker) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Helpers

    private static func removingOurHooks(from entry: [String: Any]) -> [String: Any]? {
        guard var entryHooks = entry["hooks"] as? [[String: Any]] else { return entry }
        entryHooks.removeAll { hook in
            (hook["command"] as? String)?.contains(marker) == true
        }
        guard !entryHooks.isEmpty else { return nil }
        var updated = entry
        updated["hooks"] = entryHooks
        return updated
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return "python3" }
        } catch {}
        return "python"
    }
}
