//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let approvalSound = "approvalSound"
        static let claudeDirectoryName = "claudeDirectoryName"
        static let notificationAutoCloseSeconds = "notificationAutoCloseSeconds"
    }

    // MARK: - Auto-close

    /// Seconds before a notification-opened panel auto-collapses. 0 = never
    /// auto-close (panel sticks until the user dismisses). Default 5.
    static var notificationAutoCloseSeconds: Int {
        get {
            let value = defaults.object(forKey: Keys.notificationAutoCloseSeconds) as? Int
            return value ?? 5
        }
        set {
            defaults.set(newValue, forKey: Keys.notificationAutoCloseSeconds)
        }
    }

    /// Allowed values for the auto-close picker in settings. 0 means Off.
    static let notificationAutoCloseOptions: [Int] = [0, 3, 5, 10, 30]

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    /// The sound to play when Claude requests tool approval. Defaults to
    /// something more attention-grabbing than the ready sound since approval
    /// blocks Claude until the user responds.
    static var approvalSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.approvalSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .glass
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.approvalSound)
        }
    }

    // MARK: - Claude Directory

    /// The name of the Claude config directory under the user's home folder.
    /// Defaults to ".claude" (standard Claude Code installation).
    /// Change to ".claude-internal" (or similar) for enterprise/custom distributions.
    static var claudeDirectoryName: String {
        get {
            let value = defaults.string(forKey: Keys.claudeDirectoryName) ?? ""
            return value.isEmpty ? ".claude" : value
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Keys.claudeDirectoryName)
        }
    }
}
