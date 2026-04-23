//
//  AccessibilityRow.swift
//  ClaudeIsland
//
//  Opt-in Accessibility setting. The app itself doesn't need AX to run —
//  this row exists so users who want the "one-click dismiss that also
//  reaches the app behind" enhancement can flip it on explicitly, rather
//  than getting a surprise macOS prompt on first launch.
//
//  Clicking "Enable" calls AXIsProcessTrustedWithOptions with the prompt
//  flag, which either triggers the macOS dialog (first time) or opens
//  System Settings implicitly (if already denied). After the user grants
//  access the app needs to be restarted for the new NotchPanel.sendEvent
//  path to take effect — we note that inline.
//

import AppKit
import SwiftUI

struct AccessibilityRow: View {
    @State private var isEnabled: Bool = AccessibilityHelper.isTrusted
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("Accessibility")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEnabled {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("On")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Button {
                    AccessibilityHelper.requestAccess()
                    // Also open Settings so users who have previously denied
                    // (prompt won't fire again) have a clear next action.
                    AccessibilityHelper.openSettings()
                } label: {
                    Text("Enable")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check whenever the user returns to the app — likely from
            // System Settings — so the row updates without needing a relaunch
            // to reflect a fresh grant.
            isEnabled = AccessibilityHelper.isTrusted
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}
