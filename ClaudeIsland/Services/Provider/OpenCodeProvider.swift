//
//  OpenCodeProvider.swift
//  ClaudeIsland
//
//  Installs a JS plugin into ~/.opencode/plugins/ that posts session.idle
//  events to Muxy Island's Unix socket. OpenCode's plugin API only exposes
//  coarse session-level events (no tool approval, no pre/post-tool) so the
//  provider is flagged `notificationOnly` — sessions appear in the notch
//  list after each completion but don't get approval buttons or chat input.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "OpenCodeProvider")

struct OpenCodeProvider: SessionProvider {
    let id = ProviderID.openCode
    let displayName = "OpenCode"
    let iconName = "chevron.left.forwardslash.chevron.right"
    let executableNames = ["opencode"]
    /// Plugin API exposes session.idle only — nothing to approve, no way to
    /// inject user input back, no JSONL log to replay. Pure "done" notifier.
    let capabilities = ProviderCapabilities.notificationOnly

    private static let pluginsDir = NSHomeDirectory() + "/.opencode/plugins"
    private static let pluginFileName = "muxy-island-notify.js"
    private static var installedPluginPath: String {
        pluginsDir + "/" + pluginFileName
    }
    /// Resource name (without extension) as bundled in the app.
    private static let bundledResourceName = "opencode-muxy-island-plugin"

    func install() throws {
        guard let bundledURL = Bundle.main.url(
            forResource: Self.bundledResourceName,
            withExtension: "js"
        ) else {
            logger.error("OpenCode plugin resource missing from app bundle")
            return
        }

        let sourceData = try Data(contentsOf: bundledURL)

        // Skip the write if the on-disk plugin already matches — avoids
        // churning the file on every launch and tripping OpenCode's file
        // watcher unnecessarily.
        if FileManager.default.fileExists(atPath: Self.installedPluginPath),
           let existing = try? Data(contentsOf: URL(fileURLWithPath: Self.installedPluginPath)),
           existing == sourceData {
            return
        }

        try FileManager.default.createDirectory(
            atPath: Self.pluginsDir,
            withIntermediateDirectories: true
        )

        let dest = URL(fileURLWithPath: Self.installedPluginPath)
        if FileManager.default.fileExists(atPath: Self.installedPluginPath) {
            try FileManager.default.removeItem(at: dest)
        }
        try sourceData.write(to: dest)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: Self.installedPluginPath) else { return }
        try FileManager.default.removeItem(atPath: Self.installedPluginPath)
    }

    func isHookInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.installedPluginPath)
    }
}
