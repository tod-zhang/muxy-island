//
//  ClaudeCodeProvider.swift
//  ClaudeIsland
//
//  Wraps the existing HookInstaller so Claude Code slots into the generic
//  SessionProvider machinery. All the heavy lifting (detecting the installed
//  Claude Code version, deciding which hook events to register, merging with
//  the user's existing settings.json) still lives in HookInstaller — this
//  file is just the adapter.
//

import Foundation

struct ClaudeCodeProvider: SessionProvider {
    let id = ProviderID.claudeCode
    let displayName = "Claude Code"
    let executableNames = ["claude"]
    let capabilities = ProviderCapabilities.claudeCode

    func install() throws {
        HookInstaller.installIfNeeded()
    }

    func uninstall() throws {
        HookInstaller.uninstall()
    }

    func isHookInstalled() -> Bool {
        HookInstaller.isInstalled()
    }
}
