//
//  ProjectTag.swift
//  ClaudeIsland
//
//  Small color-coded pill shown on the right of each session row. Groups
//  sessions of the same project visually without needing a hierarchical
//  folder UI. The color is derived from the project key (muxyProjectId
//  or cwd) via a stable hash into an 8-color palette, so reopenings of
//  the same project always land on the same tint.
//

import Foundation
import SwiftUI

struct ProjectTag: View {
    let session: SessionState

    var body: some View {
        let key = Self.projectKey(for: session)
        let color = Self.color(forKey: key)
        let label = Self.displayName(for: session)

        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.18))
            )
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// Key used for grouping. Muxy sessions share the same projectId
    /// across worktrees, so those cluster together automatically. Non-
    /// Muxy sessions fall back to cwd — two sessions in the same folder
    /// group, two in sibling folders don't (acceptable simplification).
    static func projectKey(for session: SessionState) -> String {
        session.muxyProjectId ?? session.cwd
    }

    /// Last path component of cwd is usually the "project name" the user
    /// thinks in — e.g. "muxy island" for /Users/todd/Desktop/muxy island.
    static func displayName(for session: SessionState) -> String {
        let name = URL(fileURLWithPath: session.cwd).lastPathComponent
        return name.isEmpty ? "~" : name
    }

    /// Stable color derived by summing the key's unicode scalars modulo
    /// the palette size. Swift's default String.hashValue is randomized
    /// per process launch, so we roll our own deterministic one.
    static func color(forKey key: String) -> Color {
        let idx = key.unicodeScalars.reduce(0) { acc, scalar in
            (acc &+ Int(scalar.value)) % Self.palette.count
        }
        return Self.palette[idx]
    }

    /// 7 visually distinct hues that read clearly on the dark notch
    /// background. Kept muted so the tags don't overpower the session
    /// title or state indicator.
    static let palette: [Color] = [
        Color(red: 0.42, green: 0.66, blue: 0.96),  // blue
        Color(red: 0.98, green: 0.62, blue: 0.34),  // orange
        Color(red: 0.56, green: 0.80, blue: 0.48),  // green
        Color(red: 0.82, green: 0.54, blue: 0.96),  // purple
        Color(red: 0.96, green: 0.52, blue: 0.68),  // pink
        Color(red: 0.33, green: 0.73, blue: 0.92),  // teal (shifted toward cyan-blue to separate from green)
        Color(red: 0.98, green: 0.82, blue: 0.34),  // yellow
    ]
}
