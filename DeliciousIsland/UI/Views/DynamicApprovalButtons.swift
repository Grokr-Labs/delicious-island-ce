//
//  DynamicApprovalButtons.swift
//  DeliciousIsland
//
//  Renders approval buttons dynamically based on MenuOption array.
//  Adapts to any permission type without hardcoded button sets.
//

import SwiftUI

/// Dynamic approval buttons that render from MenuOption array
struct DynamicApprovalButtons: View {
    let options: [MenuOption]
    let isInTmux: Bool
    let onSelectOption: (MenuOption) -> Void

    @State private var approvalState: ApprovalState = .pending
    @State private var selectedOption: MenuOption?
    @State private var buttonVisibility: [Int: Bool] = [:]

    enum ApprovalState {
        case pending
        case approved
        case denied
    }

    var body: some View {
        HStack(spacing: 8) {
            if approvalState == .pending {
                ForEach(options) { option in
                    // Skip options that require native menu when not in tmux
                    if !option.requiresNativeMenu || isInTmux {
                        optionButton(for: option)
                            .opacity(buttonVisibility[option.id] == true ? 1 : 0)
                            .scaleEffect(buttonVisibility[option.id] == true ? 1 : 0.8)
                    }
                }
            } else {
                confirmationView
            }
        }
        .onAppear {
            animateButtonsIn()
        }
    }

    // MARK: - Option Button

    private func optionButton(for option: MenuOption) -> some View {
        Button {
            selectOption(option)
        } label: {
            HStack(spacing: 4) {
                Text("\(option.id).")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(foregroundColor(for: option).opacity(0.7))
                Text(option.shortLabel)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(foregroundColor(for: option))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor(for: option))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(option.id). \(option.label)")
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        HStack(spacing: 6) {
            Image(systemName: approvalState == .denied ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(approvalState == .denied ? .red : .green)
            Text(confirmationText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var confirmationText: String {
        guard let option = selectedOption else { return "Done" }
        if option.style == .deny {
            return "Denied"
        } else if option.isPersistent {
            return "Remembered"
        } else {
            return "Approved"
        }
    }

    // MARK: - Styling

    private func foregroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return .black
        case .persistent:
            return .black
        case .deny:
            return .white.opacity(0.8)
        }
    }

    private func backgroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return Color.white.opacity(0.95)
        case .persistent:
            return TerminalColors.green
        case .deny:
            return Color.white.opacity(0.1)
        }
    }

    // MARK: - Actions

    private func selectOption(_ option: MenuOption) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedOption = option
            approvalState = option.style == .deny ? .denied : .approved
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSelectOption(option)
        }
    }

    private func animateButtonsIn() {
        for (index, option) in options.enumerated() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(Double(index) * 0.05)) {
                buttonVisibility[option.id] = true
            }
        }
    }
}

// MARK: - Inline Dynamic Buttons (for instance list)

/// Compact inline version of dynamic approval buttons
struct InlineDynamicApprovalButtons: View {
    let options: [MenuOption]
    let isInTmux: Bool
    let onSelectOption: (MenuOption) -> Void
    let onOpenChat: () -> Void

    @State private var approvalState: ApprovalState = .pending
    @State private var selectedOption: MenuOption?
    @State private var buttonVisibility: [Int: Bool] = [:]
    @State private var showChatButton = false

    enum ApprovalState {
        case pending
        case approved
        case denied
    }

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            Button {
                onOpenChat()
            } label: {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open chat")
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            if approvalState == .pending {
                ForEach(options) { option in
                    // Skip options that require native menu when not in tmux
                    if !option.requiresNativeMenu || isInTmux {
                        inlineOptionButton(for: option)
                            .opacity(buttonVisibility[option.id] == true ? 1 : 0)
                            .scaleEffect(buttonVisibility[option.id] == true ? 1 : 0.8)
                    }
                }
            } else {
                inlineConfirmationView
            }
        }
        .onAppear {
            animateButtonsIn()
        }
    }

    // MARK: - Inline Option Button

    private func inlineOptionButton(for option: MenuOption) -> some View {
        Button {
            selectOption(option)
        } label: {
            Text(option.shortLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(foregroundColor(for: option))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(backgroundColor(for: option))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(option.id). \(option.label)")
    }

    // MARK: - Inline Confirmation View

    private var inlineConfirmationView: some View {
        HStack(spacing: 4) {
            Image(systemName: approvalState == .denied ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(approvalState == .denied ? .red : .green)
            Text(confirmationText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var confirmationText: String {
        guard let option = selectedOption else { return "Done" }
        return option.style == .deny ? "Denied" : "Approved"
    }

    // MARK: - Styling

    private func foregroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return .black
        case .persistent:
            return .black
        case .deny:
            return .white.opacity(0.7)
        }
    }

    private func backgroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return Color.white.opacity(0.9)
        case .persistent:
            return TerminalColors.green
        case .deny:
            return Color.white.opacity(0.1)
        }
    }

    // MARK: - Actions

    private func selectOption(_ option: MenuOption) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedOption = option
            approvalState = option.style == .deny ? .denied : .approved
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onSelectOption(option)
        }
    }

    private func animateButtonsIn() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
            showChatButton = true
        }
        for (index, option) in options.enumerated() {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(index + 1) * 0.04)) {
                buttonVisibility[option.id] = true
            }
        }
    }
}

// MARK: - Chat Approval Bar with Dynamic Buttons

/// Full approval bar for chat view with dynamic buttons
struct DynamicChatApprovalBar: View {
    let tool: String
    let toolInput: String?
    let prompt: String
    let options: [MenuOption]
    let isInTmux: Bool
    let onSelectOption: (MenuOption) -> Void

    @State private var showContent = false
    @State private var approvalState: ApprovalState = .pending
    @State private var selectedOption: MenuOption?
    @State private var buttonVisibility: [Int: Bool] = [:]

    enum ApprovalState {
        case pending
        case approved
        case denied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool info row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if let input = toolInput, !input.isEmpty {
                        Text(input)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(x: showContent ? 0 : -10)

                Spacer()

                if approvalState == .pending {
                    buttonRow
                } else {
                    confirmationView
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
            animateButtonsIn()
        }
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                // Skip options that require native menu when not in tmux
                if !option.requiresNativeMenu || isInTmux {
                    approvalButton(for: option)
                        .opacity(buttonVisibility[option.id] == true ? 1 : 0)
                        .scaleEffect(buttonVisibility[option.id] == true ? 1 : 0.8)
                }
            }
        }
    }

    private func approvalButton(for option: MenuOption) -> some View {
        Button {
            selectOption(option)
        } label: {
            HStack(spacing: 4) {
                Text("\(option.id).")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(foregroundColor(for: option).opacity(0.7))
                Text(option.shortLabel)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(foregroundColor(for: option))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor(for: option))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(option.id). \(option.label)")
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        HStack(spacing: 6) {
            Image(systemName: approvalState == .denied ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(approvalState == .denied ? .red : .green)
            Text(confirmationText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var confirmationText: String {
        guard let option = selectedOption else { return "Done" }
        if option.style == .deny {
            return "Denied"
        } else if option.isPersistent {
            return "Remembered"
        } else {
            return "Approved"
        }
    }

    // MARK: - Styling

    private func foregroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return .black
        case .persistent:
            return .black
        case .deny:
            return .white.opacity(0.8)
        }
    }

    private func backgroundColor(for option: MenuOption) -> Color {
        switch option.style {
        case .approve:
            return Color.white.opacity(0.95)
        case .persistent:
            return TerminalColors.green
        case .deny:
            return Color.white.opacity(0.1)
        }
    }

    // MARK: - Actions

    private func selectOption(_ option: MenuOption) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedOption = option
            approvalState = option.style == .deny ? .denied : .approved
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSelectOption(option)
        }
    }

    private func animateButtonsIn() {
        for (index, option) in options.enumerated() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1 + Double(index) * 0.05)) {
                buttonVisibility[option.id] = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Dynamic Approval Buttons") {
    VStack(spacing: 20) {
        // Standard approval
        DynamicApprovalButtons(
            options: [
                MenuOption(id: 1, label: "Yes", shortLabel: "Once", hookDecision: "allow", isPersistent: false, requiresNativeMenu: false),
                MenuOption(id: 2, label: "Yes, and don't ask again", shortLabel: "Session", hookDecision: nil, isPersistent: true, requiresNativeMenu: true),
                MenuOption(id: 3, label: "No", shortLabel: "Deny", hookDecision: "deny", isPersistent: false, requiresNativeMenu: false)
            ],
            isInTmux: true,
            onSelectOption: { option in print("Selected: \(option.label)") }
        )

        // MCP approval
        DynamicApprovalButtons(
            options: [
                MenuOption(id: 1, label: "Yes", shortLabel: "Once", hookDecision: "allow", isPersistent: false, requiresNativeMenu: false),
                MenuOption(id: 2, label: "Yes, and don't ask again for playwright", shortLabel: "Remember", hookDecision: nil, isPersistent: true, requiresNativeMenu: true),
                MenuOption(id: 3, label: "No", shortLabel: "Deny", hookDecision: "deny", isPersistent: false, requiresNativeMenu: false)
            ],
            isInTmux: false,  // Without tmux, Remember button hidden
            onSelectOption: { option in print("Selected: \(option.label)") }
        )
    }
    .padding()
    .background(Color.black)
}
