//
//  Settings.swift
//  DeliciousIsland
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
        static let alwaysExpandForApprovals = "alwaysExpandForApprovals"
        static let playSoundForApprovals = "playSoundForApprovals"
        static let focusBehavior = "focusBehavior"
    }

    // MARK: - Focus Behavior

    /// Controls when Delicious Island takes keyboard focus
    enum FocusBehavior: String, CaseIterable {
        case never = "Never"
        case approvalsOnly = "Approvals Only"
        case always = "Always"

        var description: String {
            switch self {
            case .never: return "Never steal focus from other apps"
            case .approvalsOnly: return "Only for permission prompts"
            case .always: return "Whenever showing content"
            }
        }
    }

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

    // MARK: - Approval Notifications

    /// Whether to always expand the notch for pending approvals (regardless of terminal visibility)
    static var alwaysExpandForApprovals: Bool {
        get {
            // Default to true for better notification visibility
            if defaults.object(forKey: Keys.alwaysExpandForApprovals) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.alwaysExpandForApprovals)
        }
        set {
            defaults.set(newValue, forKey: Keys.alwaysExpandForApprovals)
        }
    }

    /// Whether to play notification sound for pending approvals
    static var playSoundForApprovals: Bool {
        get {
            // Default to true
            if defaults.object(forKey: Keys.playSoundForApprovals) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.playSoundForApprovals)
        }
        set {
            defaults.set(newValue, forKey: Keys.playSoundForApprovals)
        }
    }

    // MARK: - Focus Behavior

    /// When Delicious Island should take keyboard focus
    static var focusBehavior: FocusBehavior {
        get {
            guard let rawValue = defaults.string(forKey: Keys.focusBehavior),
                  let behavior = FocusBehavior(rawValue: rawValue) else {
                return .never // Default to never stealing focus
            }
            return behavior
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.focusBehavior)
        }
    }

    /// Check if focus should be taken for the current context
    static func shouldTakeFocus(forApproval: Bool) -> Bool {
        switch focusBehavior {
        case .never:
            return false
        case .approvalsOnly:
            return forApproval
        case .always:
            return true
        }
    }
}
