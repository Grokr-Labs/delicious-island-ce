//
//  TmuxStubs.swift
//  DeliciousIsland CE
//
//  Stub implementations for tmux integration (CE does not include this feature)
//

import Foundation
import Combine

/// Stub for TmuxTarget (premium feature)
struct TmuxTarget: Equatable, Sendable, Identifiable, Hashable {
    var id: String { session }
    let session: String
    let window: Int
    let pane: Int

    init(session: String = "", window: Int = 0, pane: Int = 0) {
        self.session = session
        self.window = window
        self.pane = pane
    }

    /// Initialize from a target string like "session:window.pane"
    init?(from targetString: String) {
        // Stub always returns nil via failable init
        return nil
    }
}

/// Stub for TmuxIntegrationManager (premium feature)
@MainActor
class TmuxIntegrationManager: ObservableObject {
    static let shared = TmuxIntegrationManager()
    
    enum TerminalApp: String, CaseIterable, Identifiable {
        case systemDefault = "Default Terminal"
        case terminal = "Terminal"
        case iterm = "iTerm2"
        case warp = "Warp"
        case alacritty = "Alacritty"
        case kitty = "Kitty"
        case ghostty = "Ghostty"
        
        var id: String { rawValue }
        var isInstalled: Bool { false }
    }
    
    enum LaunchStatus: Equatable {
        case idle
        case launching
        case success
        case failed(String)
    }
    
    @Published var isTmuxInstalled: Bool = false
    @Published var preferredTerminal: TerminalApp = .systemDefault
    @Published var launchStatus: LaunchStatus = .idle
    
    func launchClaudeInTmux() async {
        // Premium feature - not available in CE
    }
}

/// Stub for ToolApprovalHandler (premium feature)
@MainActor
class ToolApprovalHandler {
    static let shared = ToolApprovalHandler()

    func cancelAnyPendingApproval() {}
    func approveAlways(target: TmuxTarget) async -> Bool { false }
    func selectOption(target: TmuxTarget, key: String) async -> Bool { false }
    func sendMessage(_ text: String, to target: TmuxTarget) async -> Bool { false }
}

/// Stub for TmuxPathFinder (premium feature)
actor TmuxPathFinder {
    static let shared = TmuxPathFinder()

    func findTmux() -> String? { nil }
    func getTmuxPath() async -> String? { nil }
}

/// Stub for captured menu data (premium feature)
struct CapturedMenu {
    let prompt: String
    let rawContent: String

    func toMenuOptions() -> [MenuOption] { [] }
}

/// Stub for TmuxMenuCapture (premium feature)
@MainActor
class TmuxMenuCapture {
    static let shared = TmuxMenuCapture()

    func captureActiveMenu(for target: TmuxTarget) async -> String? { nil }
    func captureMenu(from target: TmuxTarget) async -> CapturedMenu? { nil }
}

/// Stub for TmuxTargetFinder (premium feature)
@MainActor
class TmuxTargetFinder {
    static let shared = TmuxTargetFinder()

    func findTarget(for session: SessionState) -> TmuxTarget? { nil }
    func isSessionPaneActive(claudePid: Int) async -> Bool { false }
}

/// Stub for TmuxController (premium feature)
actor TmuxController {
    static let shared = TmuxController()

    var isAvailable: Bool { false }

    func findTmuxTarget(forClaudePid claudePid: Int) async -> TmuxTarget? { nil }
    func switchToPane(target: TmuxTarget) async -> Bool { false }
    func sendKeys(_ keys: [String], target: TmuxTarget) {}
    func parseTarget(from: String) -> TmuxTarget? { nil }
}

/// Stub for TmuxSessionTracker (premium feature)
@MainActor
class TmuxSessionTracker {
    static let shared = TmuxSessionTracker()

    func attachToSession(_ sessionName: String, terminal: TmuxIntegrationManager.TerminalApp? = nil) async {}
    func detachOthers(_ sessionName: String) async -> Bool { false }
    func renameSession(_ oldName: String, to newName: String) async -> Bool { false }
    func killSession(_ sessionName: String) async -> Bool { false }
}

/// Stub extension to add tmux properties to SessionState (premium feature)
extension SessionState {
    /// Always nil in CE - tmux integration is a premium feature
    var tmuxSessionName: String? { nil }
}
