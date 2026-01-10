//
//  ClaudeSessionMonitor.swift
//  DeliciousIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { [weak self] event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                // Trigger async menu capture for permission requests in tmux sessions
                if event.expectsResponse, let toolUseId = event.toolUseId {
                    Task { @MainActor [weak self] in
                        self?.triggerMenuCapture(sessionId: event.sessionId, toolUseId: toolUseId)
                    }
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Approve permission for session using tmux-based approach.
    /// This closes the hook socket (letting Claude show its native menu) and sends "2" via tmux.
    func approvePermissionForSession(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Check if session is in tmux (required for this approach)
            guard session.isInTmux, let tty = session.tty else {
                // Fall back to hook-based approval (will just do "allow" since Claude doesn't support "allow_for_session")
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission.toolUseId,
                    decision: "allow"
                )
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
                )
                return
            }

            // Step 1: Close the hook socket without responding
            // This causes the Python hook to exit without output, letting Claude show its native menu
            HookSocketServer.shared.closeWithoutResponse(toolUseId: permission.toolUseId)

            // Step 2: Wait for Claude to display its native menu
            try? await Task.sleep(for: .milliseconds(200))

            // Step 3: Find the tmux target for this session
            guard let target = await findTmuxTarget(tty: tty) else {
                return
            }

            // Step 4: Send "2" to select "Yes, and don't ask again"
            _ = await ToolApprovalHandler.shared.approveAlways(target: target)

            // Update session state
            await SessionStore.shared.process(
                .permissionApprovedForSession(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Find the tmux target (pane) for a given tty
    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let target = parts[0]
                let paneTty = parts[1].replacingOccurrences(of: "/dev/", with: "")

                if paneTty == tty {
                    return TmuxTarget(from: target)
                }
            }
        } catch {
            // Silently fail - tmux might not be available
        }

        return nil
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    // MARK: - Plan Mode Methods

    /// Enter plan mode - approves the EnterPlanMode tool
    /// For plan mode, we just need to approve the tool - Claude handles the rest
    func enterPlanMode(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Use hook socket to approve (same as approvePermission)
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Skip plan mode - denies the EnterPlanMode tool, causing Claude to start implementing
    func skipPlanMode(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Deny the plan mode tool - this tells Claude to skip planning
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: "User chose to skip planning and start implementing"
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: "Skip planning")
            )
        }
    }

    /// Approve plan with auto-accept edits - approves the ExitPlanMode tool
    func approvePlanAutoAccept(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Approve the plan execution
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Approve plan with manual edit approval - approves the ExitPlanMode tool
    /// Note: The distinction between auto/manual is handled by Claude Code's native UI
    /// when using tmux. Via hooks, we can only approve or deny.
    func approvePlanManual(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Approve the plan execution
            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - Folder/Command Access Methods

    /// Approve with folder/command access using tmux-based approach.
    /// This closes the hook socket (letting Claude show its native menu) and sends "2" via tmux
    /// to select the "allow access to folder and commands" option.
    func approveWithFolderAccess(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Check if session is in tmux (required for this approach)
            guard session.isInTmux, let tty = session.tty else {
                // Fall back to hook-based approval (will just do "allow" once)
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission.toolUseId,
                    decision: "allow"
                )
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
                )
                return
            }

            // Step 1: Close the hook socket without responding
            HookSocketServer.shared.closeWithoutResponse(toolUseId: permission.toolUseId)

            // Step 2: Wait for Claude to display its native menu
            try? await Task.sleep(for: .milliseconds(200))

            // Step 3: Find the tmux target for this session
            guard let target = await findTmuxTarget(tty: tty) else {
                return
            }

            // Step 4: Send "2" to select "Yes, and allow access to..."
            _ = await ToolApprovalHandler.shared.approveAlways(target: target)

            // Update session state
            await SessionStore.shared.process(
                .permissionApprovedForSession(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    /// Approve MCP permission and remember using tmux-based approach.
    /// This closes the hook socket (letting Claude show its native menu) and sends "2" via tmux
    /// to select the "don't ask again for this MCP command" option.
    func approveAndRememberMCP(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // Check if session is in tmux (required for this approach)
            guard session.isInTmux, let tty = session.tty else {
                // Fall back to hook-based approval (will just do "allow" once)
                HookSocketServer.shared.respondToPermission(
                    toolUseId: permission.toolUseId,
                    decision: "allow"
                )
                await SessionStore.shared.process(
                    .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
                )
                return
            }

            // Step 1: Close the hook socket without responding
            HookSocketServer.shared.closeWithoutResponse(toolUseId: permission.toolUseId)

            // Step 2: Wait for Claude to display its native menu
            try? await Task.sleep(for: .milliseconds(200))

            // Step 3: Find the tmux target for this session
            guard let target = await findTmuxTarget(tty: tty) else {
                return
            }

            // Step 4: Send "2" to select "Yes, and don't ask again for..."
            _ = await ToolApprovalHandler.shared.approveAlways(target: target)

            // Update session state
            await SessionStore.shared.process(
                .permissionApprovedForSession(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    // MARK: - Tmux Menu Capture

    /// Trigger async menu capture from tmux terminal
    /// This runs after a permission request to get the actual menu Claude is displaying
    private func triggerMenuCapture(sessionId: String, toolUseId: String) {
        Task {
            // Get session to check if it's in tmux
            guard let session = await SessionStore.shared.session(for: sessionId),
                  session.isInTmux,
                  let tty = session.tty else {
                // Not in tmux - stick with predictive menu
                return
            }

            // Wait for Claude to render the menu (~300ms should be enough)
            try? await Task.sleep(for: .milliseconds(300))

            // Find the tmux target
            guard let target = await findTmuxTarget(tty: tty) else {
                return
            }

            // Capture the menu from terminal
            guard let capturedMenu = await TmuxMenuCapture.shared.captureMenu(from: target) else {
                return
            }

            // Convert to ExtractedMenu and emit event
            let menuOptions = capturedMenu.toMenuOptions()
            let extractedMenu = ExtractedMenu(
                prompt: capturedMenu.prompt,
                options: menuOptions,
                toolCategory: .unknown  // Category doesn't matter since we have the real options
            )

            await SessionStore.shared.process(
                .menuCaptured(sessionId: sessionId, toolUseId: toolUseId, menu: extractedMenu)
            )
        }
    }

    // MARK: - Dynamic Menu Option Selection

    /// Handle selection of a dynamic menu option
    /// Routes to appropriate action based on option properties
    func selectMenuOption(sessionId: String, option: MenuOption) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            // If option has a direct hook decision (allow/deny), use it
            if let hookDecision = option.hookDecision {
                if hookDecision == "allow" {
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission.toolUseId,
                        decision: "allow"
                    )
                    await SessionStore.shared.process(
                        .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
                    )
                } else if hookDecision == "deny" {
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission.toolUseId,
                        decision: "deny",
                        reason: "Denied by user"
                    )
                    await SessionStore.shared.process(
                        .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: "Denied by user")
                    )
                }
                return
            }

            // Option requires native menu (persistent options, special selections)
            if option.requiresNativeMenu {
                // Check if we can use tmux
                if session.isInTmux, let tty = session.tty {
                    // Close hook socket to let Claude show native menu
                    HookSocketServer.shared.closeWithoutResponse(toolUseId: permission.toolUseId)

                    // Wait for Claude to display its native menu
                    try? await Task.sleep(for: .milliseconds(200))

                    // Find tmux target and send the option key (e.g., "1", "2", "n")
                    if let target = await findTmuxTarget(tty: tty) {
                        _ = await ToolApprovalHandler.shared.selectOption(target: target, key: option.key)
                    }

                    // Update state
                    if option.isPersistent {
                        await SessionStore.shared.process(
                            .permissionApprovedForSession(sessionId: sessionId, toolUseId: permission.toolUseId)
                        )
                    } else {
                        await SessionStore.shared.process(
                            .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
                        )
                    }
                } else {
                    // Not in tmux - respond with "ask" to show native menu
                    // User will need to interact with Claude's terminal directly
                    HookSocketServer.shared.respondToPermission(
                        toolUseId: permission.toolUseId,
                        decision: "ask"
                    )
                    // Note: State will be updated when Claude sends next hook event
                }
            }
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
