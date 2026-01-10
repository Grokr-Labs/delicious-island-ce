//
//  ClaudeInstancesView.swift
//  DeliciousIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var keyboardHandler = KeyboardShortcutHandler.shared

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    /// Get pending instances in sorted order for keyboard navigation
    private var sortedPendingInstances: [SessionState] {
        sortedInstances.filter { $0.phase.isWaitingForApproval }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(sortedInstances.enumerated()), id: \.element.stableId) { index, session in
                    // Check if this session is keyboard-selected
                    let pendingIndex = sortedPendingInstances.firstIndex(where: { $0.stableId == session.stableId })
                    let isKeyboardSelected = pendingIndex == keyboardHandler.selectedSessionIndex &&
                                            session.phase.isWaitingForApproval &&
                                            sortedPendingInstances.count > 1

                    InstanceRow(
                        session: session,
                        sessionIndex: index,
                        isKeyboardSelected: isKeyboardSelected,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onSelectOption: { option in
                            sessionMonitor.selectMenuOption(sessionId: session.sessionId, option: option)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let sessionIndex: Int
    var isKeyboardSelected: Bool = false
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onSelectOption: (MenuOption) -> Void

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var tmuxActionInProgress = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let planModePurple = Color(red: 0.55, green: 0.35, blue: 0.85)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Colors for session differentiation
    private static let sessionColors: [Color] = [
        Color(red: 0.3, green: 0.7, blue: 0.9),   // Blue
        Color(red: 0.4, green: 0.8, blue: 0.4),   // Green
        Color(red: 0.9, green: 0.6, blue: 0.3),   // Orange
        Color(red: 0.8, green: 0.4, blue: 0.7),   // Pink
        Color(red: 0.6, green: 0.5, blue: 0.9),   // Purple
        Color(red: 0.9, green: 0.8, blue: 0.3),   // Yellow
    ]

    /// Get unique color for this session
    private var sessionColor: Color {
        Self.sessionColors[sessionIndex % Self.sessionColors.count]
    }

    /// Whether to show the project badge (when displayTitle differs from projectName)
    private var shouldShowProjectBadge: Bool {
        session.displayTitle != session.projectName
    }

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Background fill color (with tmux tint)
    private var backgroundFill: Color {
        if isKeyboardSelected {
            return TerminalColors.amber.opacity(0.15)
        } else if isHovered {
            return session.isInTmux
                ? TerminalColors.cyan.opacity(0.08)
                : Color.white.opacity(0.06)
        } else {
            return session.isInTmux
                ? TerminalColors.cyan.opacity(0.03)
                : Color.clear
        }
    }

    /// Background stroke color
    private var backgroundStroke: Color {
        if isKeyboardSelected {
            return TerminalColors.amber.opacity(0.4)
        } else if session.isInTmux && isHovered {
            return TerminalColors.cyan.opacity(0.2)
        }
        return Color.clear
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Session number with color accent
            Text("\(sessionIndex + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(sessionColor)
                .frame(width: 14)

            // State indicator
            stateIndicator
                .frame(width: 14)

            // Tmux badge with action menu (shown for tmux sessions)
            if session.isInTmux {
                TmuxActionMenu(
                    session: session,
                    isActionInProgress: $tmuxActionInProgress,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText
                )
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Project badge (shown when displayTitle differs from project)
                    if shouldShowProjectBadge {
                        Text(session.projectName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(sessionColor.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(sessionColor.opacity(0.15))
                            )
                    }
                }

                // Show tool call when waiting for approval, otherwise last activity
                if isWaitingForApproval, let toolName = session.pendingToolName {
                    // Show tool name in amber + input on same line
                    HStack(spacing: 4) {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.9))
                        if isInteractiveTool {
                            Text("Needs your input")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        } else if let input = session.pendingToolInput {
                            Text(input)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                } else if let role = session.lastMessageRole {
                    switch role {
                    case "tool":
                        // Tool call - show tool name + input
                        HStack(spacing: 4) {
                            if let toolName = session.lastToolName {
                                Text(MCPToolFormatter.formatToolName(toolName))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            if let input = session.lastMessage {
                                Text(input)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    case "user":
                        // User message - prefix with "You:"
                        HStack(spacing: 4) {
                            Text("You:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    default:
                        // Assistant message - just show text
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                } else if let lastMsg = session.lastMessage {
                    Text(lastMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Action icons or approval buttons
            if isWaitingForApproval && isInteractiveTool {
                // Interactive tools like AskUserQuestion - show chat + terminal buttons
                HStack(spacing: 8) {
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Go to Terminal button (only if yabai available)
                    if isYabaiAvailable {
                        TerminalButton(
                            isEnabled: session.isInTmux,
                            onTap: { onFocus() }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval {
                InlineDynamicApprovalButtons(
                    options: session.activePermission?.menuOptions ?? [],
                    isInTmux: session.isInTmux,
                    onSelectOption: onSelectOption,
                    onOpenChat: onChat
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Chat icon - always show
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Focus icon (only for tmux instances with yabai)
                    if session.isInTmux && isYabaiAvailable {
                        IconButton(icon: "eye") {
                            onFocus()
                        }
                    }

                    // Archive button - only for idle or completed sessions
                    if session.phase == .idle || session.phase == .waitingForInput {
                        IconButton(icon: "archivebox") {
                            onArchive()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(backgroundStroke, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isKeyboardSelected)
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Inline Approval Button

/// Compact approval button with hover and click effects
struct InlineApprovalButton: View {
    let title: String
    let foregroundColor: Color
    let backgroundColor: Color
    var icon: String? = nil
    var tooltip: String? = nil
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                backgroundColor
                    .brightness(isHovered ? 0.1 : 0)
                    .saturation(isPressed ? 0.8 : 1.0)
            )
            .clipShape(Capsule())
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeInOut(duration: 0.08)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.08)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
/// Supports standard, plan entry, plan execution, folder access, and MCP permission approval types
struct InlineApprovalButtons: View {
    let approvalType: ApprovalType
    let isInTmux: Bool
    let onChat: () -> Void
    let onApprove: () -> Void
    let onApproveForSession: () -> Void
    let onReject: () -> Void
    // Plan mode callbacks
    let onEnterPlanMode: () -> Void
    let onSkipPlanMode: () -> Void
    let onApprovePlanAutoAccept: () -> Void
    let onApprovePlanManual: () -> Void
    // Folder/MCP access callbacks
    let onApproveWithFolderAccess: () -> Void
    let onApproveAndRememberMCP: () -> Void

    @State private var showChatButton = false
    @State private var showButton1 = false
    @State private var showButton2 = false
    @State private var showButton3 = false
    @State private var approvalState: ApprovalState = .pending

    // Colors
    private let planModePurple = Color(red: 0.55, green: 0.35, blue: 0.85)
    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let warningOrange = Color(red: 0.95, green: 0.6, blue: 0.2)

    enum ApprovalState {
        case pending
        case approved
        case approvedForSession
        case denied
    }

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            if approvalState == .pending {
                // For folder/MCP types, fall back to standard when not in tmux
                let effectiveType: ApprovalType = {
                    switch approvalType {
                    case .folderCommandAccess, .mcpPersistentPermission:
                        return isInTmux ? approvalType : .standard
                    default:
                        return approvalType
                    }
                }()

                switch effectiveType {
                case .standard:
                    standardApprovalButtons
                case .planEntry:
                    planEntryButtons
                case .planExecution:
                    planExecutionButtons
                case .folderCommandAccess:
                    folderAccessButtons
                case .mcpPersistentPermission:
                    mcpPermissionButtons
                }
            } else {
                // Confirmation feedback
                HStack(spacing: 4) {
                    Image(systemName: approvalState == .denied ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(approvalState == .denied ? .red : (approvalType == .standard ? .green : planModePurple))
                    Text(approvalState == .denied ? "Denied" : "Approved")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showButton1 = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showButton2 = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.15)) {
                showButton3 = true
            }
        }
    }

    // MARK: - Standard Approval Buttons

    private var standardApprovalButtons: some View {
        Group {
            InlineApprovalButton(
                title: "Deny",
                foregroundColor: .white.opacity(0.7),
                backgroundColor: Color.white.opacity(0.1)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .denied
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReject()
                }
            }
            .opacity(showButton1 ? 1 : 0)
            .scaleEffect(showButton1 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Once",
                foregroundColor: .black,
                backgroundColor: Color.white.opacity(0.9)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onApprove()
                }
            }
            .opacity(showButton2 ? 1 : 0)
            .scaleEffect(showButton2 ? 1 : 0.8)

            // Session button - only show when tmux is available (required for session approval)
            if isInTmux {
                InlineApprovalButton(
                    title: "Session",
                    foregroundColor: .black,
                    backgroundColor: claudeOrange
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        approvalState = .approvedForSession
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onApproveForSession()
                    }
                }
                .opacity(showButton3 ? 1 : 0)
                .scaleEffect(showButton3 ? 1 : 0.8)
            }
        }
    }

    // MARK: - Plan Entry Buttons

    private var planEntryButtons: some View {
        Group {
            InlineApprovalButton(
                title: "Deny",
                foregroundColor: .white.opacity(0.7),
                backgroundColor: Color.white.opacity(0.1)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .denied
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReject()
                }
            }
            .opacity(showButton1 ? 1 : 0)
            .scaleEffect(showButton1 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Plan",
                foregroundColor: .white,
                backgroundColor: planModePurple,
                icon: "doc.text.magnifyingglass"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onEnterPlanMode()
                }
            }
            .opacity(showButton2 ? 1 : 0)
            .scaleEffect(showButton2 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Code Now",
                foregroundColor: .black,
                backgroundColor: warningOrange,
                icon: "bolt.fill",
                tooltip: "Skip planning and start coding immediately"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onSkipPlanMode()
                }
            }
            .opacity(showButton3 ? 1 : 0)
            .scaleEffect(showButton3 ? 1 : 0.8)
        }
    }

    // MARK: - Plan Execution Buttons

    private var planExecutionButtons: some View {
        Group {
            InlineApprovalButton(
                title: "Deny",
                foregroundColor: .white.opacity(0.7),
                backgroundColor: Color.white.opacity(0.1)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .denied
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReject()
                }
            }
            .opacity(showButton1 ? 1 : 0)
            .scaleEffect(showButton1 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Auto",
                foregroundColor: .white,
                backgroundColor: planModePurple,
                icon: "bolt.circle.fill",
                tooltip: "Auto-accept all edits"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onApprovePlanAutoAccept()
                }
            }
            .opacity(showButton2 ? 1 : 0)
            .scaleEffect(showButton2 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Manual",
                foregroundColor: .black,
                backgroundColor: Color.white.opacity(0.9),
                icon: "hand.raised.fill",
                tooltip: "Manually approve each edit"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onApprovePlanManual()
                }
            }
            .opacity(showButton3 ? 1 : 0)
            .scaleEffect(showButton3 ? 1 : 0.8)
        }
    }

    // MARK: - Folder/Command Access Buttons

    private var folderAccessButtons: some View {
        Group {
            InlineApprovalButton(
                title: "No",
                foregroundColor: .white.opacity(0.7),
                backgroundColor: Color.white.opacity(0.1)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .denied
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReject()
                }
            }
            .opacity(showButton1 ? 1 : 0)
            .scaleEffect(showButton1 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Yes",
                foregroundColor: .black,
                backgroundColor: Color.white.opacity(0.9)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onApprove()
                }
            }
            .opacity(showButton2 ? 1 : 0)
            .scaleEffect(showButton2 ? 1 : 0.8)

            // Allow Access button - only show when tmux is available
            if isInTmux {
                InlineApprovalButton(
                    title: "Allow Access",
                    foregroundColor: .black,
                    backgroundColor: TerminalColors.green,
                    icon: "folder.badge.plus",
                    tooltip: "Grant persistent folder/command access"
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        approvalState = .approvedForSession
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onApproveWithFolderAccess()
                    }
                }
                .opacity(showButton3 ? 1 : 0)
                .scaleEffect(showButton3 ? 1 : 0.8)
            }
        }
    }

    // MARK: - MCP Persistent Permission Buttons

    private var mcpPermissionButtons: some View {
        Group {
            InlineApprovalButton(
                title: "No",
                foregroundColor: .white.opacity(0.7),
                backgroundColor: Color.white.opacity(0.1)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .denied
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReject()
                }
            }
            .opacity(showButton1 ? 1 : 0)
            .scaleEffect(showButton1 ? 1 : 0.8)

            InlineApprovalButton(
                title: "Yes",
                foregroundColor: .black,
                backgroundColor: Color.white.opacity(0.9)
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    approvalState = .approved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onApprove()
                }
            }
            .opacity(showButton2 ? 1 : 0)
            .scaleEffect(showButton2 ? 1 : 0.8)

            // Remember button - only show when tmux is available
            if isInTmux {
                InlineApprovalButton(
                    title: "Remember",
                    foregroundColor: .black,
                    backgroundColor: Color(red: 0.3, green: 0.7, blue: 0.9),
                    icon: "memorychip",
                    tooltip: "Don't ask again for this MCP command"
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        approvalState = .approvedForSession
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onApproveAndRememberMCP()
                    }
                }
                .opacity(showButton3 ? 1 : 0)
                .scaleEffect(showButton3 ? 1 : 0.8)
            }
        }
    }
}

#Preview("Inline Approval Buttons") {
    VStack(spacing: 20) {
        Text("Standard (tmux)").foregroundColor(.white)
        InlineApprovalButtons(
            approvalType: .standard,
            isInTmux: true,
            onChat: { print("Chat") },
            onApprove: { print("Approved once") },
            onApproveForSession: { print("Approved for session") },
            onReject: { print("Denied") },
            onEnterPlanMode: { },
            onSkipPlanMode: { },
            onApprovePlanAutoAccept: { },
            onApprovePlanManual: { },
            onApproveWithFolderAccess: { },
            onApproveAndRememberMCP: { }
        )

        Text("Plan Entry").foregroundColor(.white)
        InlineApprovalButtons(
            approvalType: .planEntry,
            isInTmux: true,
            onChat: { print("Chat") },
            onApprove: { },
            onApproveForSession: { },
            onReject: { print("Denied") },
            onEnterPlanMode: { print("Enter plan mode") },
            onSkipPlanMode: { print("Skip plan mode") },
            onApprovePlanAutoAccept: { },
            onApprovePlanManual: { },
            onApproveWithFolderAccess: { },
            onApproveAndRememberMCP: { }
        )

        Text("Folder/Command Access").foregroundColor(.white)
        InlineApprovalButtons(
            approvalType: .folderCommandAccess,
            isInTmux: true,
            onChat: { print("Chat") },
            onApprove: { print("Approved once") },
            onApproveForSession: { },
            onReject: { print("Denied") },
            onEnterPlanMode: { },
            onSkipPlanMode: { },
            onApprovePlanAutoAccept: { },
            onApprovePlanManual: { },
            onApproveWithFolderAccess: { print("Allow Access") },
            onApproveAndRememberMCP: { }
        )

        Text("MCP Permission").foregroundColor(.white)
        InlineApprovalButtons(
            approvalType: .mcpPersistentPermission(pluginName: "claude-mem"),
            isInTmux: true,
            onChat: { print("Chat") },
            onApprove: { print("Approved once") },
            onApproveForSession: { },
            onReject: { print("Denied") },
            onEnterPlanMode: { },
            onSkipPlanMode: { },
            onApprovePlanAutoAccept: { },
            onApprovePlanManual: { },
            onApproveWithFolderAccess: { },
            onApproveAndRememberMCP: { print("Remember MCP") }
        )
    }
    .padding()
    .background(Color.black.opacity(0.9))
    .frame(width: 400, height: 450)
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tmux Action Menu

/// Menu for tmux session actions (attach, detach, rename, kill)
struct TmuxActionMenu: View {
    let session: SessionState
    @Binding var isActionInProgress: Bool
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String

    @State private var isHovered = false
    @ObservedObject private var tmuxManager = TmuxIntegrationManager.shared

    var body: some View {
        Menu {
            // Attach section
            Section {
                Button {
                    attachToSession()
                } label: {
                    Label("Attach in \(tmuxManager.preferredTerminal.rawValue)", systemImage: "rectangle.connected.to.line.below")
                }

                // Terminal picker submenu
                Menu {
                    ForEach(TmuxIntegrationManager.TerminalApp.allCases.filter { $0.isInstalled && $0 != .systemDefault }) { terminal in
                        Button {
                            attachToSession(terminal: terminal)
                        } label: {
                            Text(terminal.rawValue)
                        }
                    }
                } label: {
                    Label("Attach in...", systemImage: "chevron.right")
                }
            }

            Divider()

            // Session management section
            Section {
                Button {
                    detachOthers()
                } label: {
                    Label("Detach Others", systemImage: "person.2.slash")
                }

                Button {
                    renameText = session.tmuxSessionName ?? ""
                    showRenameAlert = true
                } label: {
                    Label("Rename Session...", systemImage: "pencil")
                }
            }

            Divider()

            // Destructive action
            Section {
                Button(role: .destructive) {
                    killSession()
                } label: {
                    Label("Kill Session", systemImage: "xmark.circle")
                }
            }
        } label: {
            // Tmux badge as menu trigger
            ZStack {
                if isActionInProgress {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 8))
                        .foregroundColor(TerminalColors.cyan)
                }
            }
            .padding(3)
            .background(
                Circle()
                    .fill(isHovered ? TerminalColors.cyan.opacity(0.35) : TerminalColors.cyan.opacity(0.2))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Tmux session actions")
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                renameSession()
            }
        } message: {
            Text("Enter a new name for the tmux session")
        }
    }

    // MARK: - Actions

    private func attachToSession(terminal: TmuxIntegrationManager.TerminalApp? = nil) {
        guard let sessionName = session.tmuxSessionName else { return }
        isActionInProgress = true

        Task {
            await TmuxSessionTracker.shared.attachToSession(sessionName, terminal: terminal)
            await MainActor.run {
                isActionInProgress = false
            }
        }
    }

    private func detachOthers() {
        guard let sessionName = session.tmuxSessionName else { return }
        isActionInProgress = true

        Task {
            _ = await TmuxSessionTracker.shared.detachOthers(sessionName)
            await MainActor.run {
                isActionInProgress = false
            }
        }
    }

    private func renameSession() {
        guard let oldName = session.tmuxSessionName, !renameText.isEmpty else { return }
        isActionInProgress = true

        Task {
            _ = await TmuxSessionTracker.shared.renameSession(oldName, to: renameText)
            await MainActor.run {
                isActionInProgress = false
            }
        }
    }

    private func killSession() {
        guard let sessionName = session.tmuxSessionName else { return }
        isActionInProgress = true

        Task {
            _ = await TmuxSessionTracker.shared.killSession(sessionName)
            await MainActor.run {
                isActionInProgress = false
            }
        }
    }
}
