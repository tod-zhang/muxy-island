//
//  AccessibilityHelper.swift
//  ClaudeIsland
//
//  Wrapper around macOS Accessibility (AX) trust state. The app works
//  fine without AX — hover detection uses NSEvent.mouseLocation polling
//  and out-of-panel clicks fall back to NSWorkspace activation
//  notifications. AX is purely an opt-in enhancement that lets us
//  forward a single click to dismiss-the-panel + activate-the-target.
//

import ApplicationServices
import AppKit
import Foundation

enum AccessibilityHelper {
    /// Whether the user has granted AX permission to this app right now.
    /// Cheap to call repeatedly — under the hood it just queries the
    /// trust database; no UI side effect.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the macOS "want to control your computer" prompt. Safe to
    /// call any number of times: if already trusted it's a no-op; if the
    /// user has denied before, the system will silently keep returning
    /// false and the user has to flip the toggle in System Settings
    /// manually (which is why we also offer `openSettings()` as a
    /// fallback in the same row).
    @discardableResult
    static func requestAccess() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy & Security → Accessibility so the
    /// user can flip the toggle for Vibe Notch directly.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
