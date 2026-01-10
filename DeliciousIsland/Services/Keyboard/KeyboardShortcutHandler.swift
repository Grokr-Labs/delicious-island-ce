//
//  KeyboardShortcutHandler.swift
//  DeliciousIsland
//
//  Handles keyboard shortcuts for approval actions when notch is open
//

import AppKit
import Combine
import os.log

/// Handles keyboard shortcuts for Delicious Island approval actions
@MainActor
class KeyboardShortcutHandler: ObservableObject {
    static let shared = KeyboardShortcutHandler()

    /// Logger for keyboard events
    private let logger = Logger(subsystem: "com.deliciousisland", category: "Keyboard")

    /// Currently selected session index for multi-session navigation
    @Published private(set) var selectedSessionIndex: Int = 0

    /// Whether keyboard shortcuts are enabled
    @Published var isEnabled: Bool = true

    /// Local event monitor for keyboard events
    private var eventMonitor: Any?

    private init() {}

    // MARK: - Public API

    /// Start monitoring keyboard events
    func startMonitoring(sessionMonitor: ClaudeSessionMonitor) {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak sessionMonitor] event in
            guard let self = self,
                  let sessionMonitor = sessionMonitor,
                  self.isEnabled else {
                return event
            }

            if self.handleKeyEvent(event, sessionMonitor: sessionMonitor) {
                return nil // Consume the event
            }
            return event // Pass through unhandled events
        }

        logger.info("Keyboard shortcuts enabled")
    }

    /// Stop monitoring keyboard events
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            logger.info("Keyboard shortcuts disabled")
        }
    }

    /// Reset selection to first session
    func resetSelection() {
        selectedSessionIndex = 0
    }

    // MARK: - Event Handling

    /// Handle a keyboard event, return true if consumed
    private func handleKeyEvent(_ event: NSEvent, sessionMonitor: ClaudeSessionMonitor) -> Bool {
        // Use all instances for navigation, but only handle approval actions for pending ones
        let allSessions = sessionMonitor.instances
        let pendingSessions = sessionMonitor.pendingInstances

        // No sessions at all, don't consume events
        guard !allSessions.isEmpty else {
            return false
        }

        // Ensure valid selection based on all sessions for navigation
        if selectedSessionIndex >= allSessions.count {
            selectedSessionIndex = 0
        }

        let keyCode = event.keyCode
        let characters = event.charactersIgnoringModifiers ?? ""

        // Handle session navigation (arrow keys) - works on all sessions
        if keyCode == 126 { // Up arrow
            navigateUp(sessionCount: allSessions.count)
            return true
        } else if keyCode == 125 { // Down arrow
            navigateDown(sessionCount: allSessions.count)
            return true
        }

        // For approval actions, we need a session with pending approval
        guard !pendingSessions.isEmpty else {
            return false
        }

        // Adjust selection index to pending sessions for approval actions
        let pendingIndex = min(selectedSessionIndex, pendingSessions.count - 1)
        let selectedSession = pendingSessions[pendingIndex]

        // Only process approval keys if the selected session is waiting for approval
        guard selectedSession.phase.isWaitingForApproval,
              let permission = selectedSession.activePermission else {
            return false
        }

        let menuOptions = permission.menuOptions

        // Handle number keys 1-9 for dynamic menu options
        if let keyNumber = Int(characters), keyNumber >= 1 && keyNumber <= 9 {
            if let option = menuOptions.first(where: { $0.id == keyNumber }) {
                // Check if option requires native menu and we're not in tmux
                if option.requiresNativeMenu && !selectedSession.isInTmux {
                    logger.info("Keyboard[\(keyNumber)]: Option requires tmux, falling back to hook response")
                    // For non-tmux, can only use hookDecision options
                    if let hookDecision = option.hookDecision {
                        if hookDecision == "allow" {
                            sessionMonitor.approvePermission(sessionId: selectedSession.sessionId)
                        } else if hookDecision == "deny" {
                            sessionMonitor.denyPermission(sessionId: selectedSession.sessionId, reason: nil)
                        }
                        return true
                    }
                    // Can't handle this option without tmux
                    return false
                }

                // Use dynamic menu option selection
                sessionMonitor.selectMenuOption(sessionId: selectedSession.sessionId, option: option)
                logger.info("Keyboard[\(keyNumber)]: Selected '\(option.shortLabel)' for session \(selectedSession.sessionId)")
                return true
            }
        }

        // Handle Escape key for deny
        if keyCode == 53 { // Escape
            sessionMonitor.denyPermission(sessionId: selectedSession.sessionId, reason: nil)
            logger.info("Keyboard: Denied session \(selectedSession.sessionId)")
            return true
        }

        return false
    }

    // MARK: - Navigation

    private func navigateUp(sessionCount: Int) {
        if selectedSessionIndex > 0 {
            selectedSessionIndex -= 1
        } else {
            selectedSessionIndex = sessionCount - 1 // Wrap to bottom
        }
        logger.debug("Keyboard: Selected session \(self.selectedSessionIndex + 1)")
    }

    private func navigateDown(sessionCount: Int) {
        if selectedSessionIndex < sessionCount - 1 {
            selectedSessionIndex += 1
        } else {
            selectedSessionIndex = 0 // Wrap to top
        }
        logger.debug("Keyboard: Selected session \(self.selectedSessionIndex + 1)")
    }

}
