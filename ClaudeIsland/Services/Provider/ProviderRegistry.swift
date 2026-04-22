//
//  ProviderRegistry.swift
//  ClaudeIsland
//
//  Single source of truth for which SessionProviders exist. Anywhere in the
//  app that used to call HookInstaller directly now goes through here, so
//  adding OpenCode / Codex is just appending to `all`.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "ProviderRegistry")

@MainActor
final class ProviderRegistry {
    static let shared = ProviderRegistry()

    /// Ordered by priority — earlier entries show up first in UI listings
    /// where grouping matters. Claude Code leads because it's the only
    /// provider with a full-fidelity integration today.
    let all: [SessionProvider] = [
        ClaudeCodeProvider(),
        OpenCodeProvider(),
        CodexProvider(),
    ]

    private init() {}

    /// Install hooks for every provider whose underlying CLI is present on
    /// this machine. Safe to call on every launch; individual provider
    /// install() methods are idempotent.
    func installAllDetected() {
        for provider in all {
            guard provider.isToolInstalled() else { continue }
            do {
                try provider.install()
            } catch {
                logger.error("Failed to install \(provider.displayName, privacy: .public) hooks: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Remove hooks for every provider we know about. Used by the Hooks
    /// toggle in settings.
    func uninstallAll() {
        for provider in all {
            try? provider.uninstall()
        }
    }

    /// Whether any provider reports its hooks are installed. The settings
    /// toggle uses this as an approximate "any hooks active" indicator.
    func anyHookInstalled() -> Bool {
        all.contains { $0.isHookInstalled() }
    }

    func provider(id: String) -> SessionProvider? {
        all.first { $0.id == id }
    }

    /// Capabilities for a provider id. Unknown providers default to
    /// `notificationOnly` so the UI hides features they can't support
    /// rather than crashing or showing broken buttons.
    func capabilities(forProviderId id: String) -> ProviderCapabilities {
        provider(id: id)?.capabilities ?? .notificationOnly
    }
}
