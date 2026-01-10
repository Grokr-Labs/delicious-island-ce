//
//  ScreenPickerRow.swift
//  DeliciousIsland
//
//  Screen selection picker for settings menu
//

import SwiftUI

struct ScreenPickerRow: View {
    @ObservedObject var screenSelector: ScreenSelector
    @State private var isHovered = false

    private var isExpanded: Bool {
        get { screenSelector.isPickerExpanded }
    }

    private func setExpanded(_ value: Bool) {
        screenSelector.isPickerExpanded = value
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - shows current selection
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    setExpanded(!isExpanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Notch Display")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(currentSelectionLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Choose which monitor displays the notch overlay")

            // Expanded screen list
            if isExpanded {
                VStack(spacing: 2) {
                    // Automatic option
                    ScreenOptionRow(
                        label: "Automatic",
                        isSelected: screenSelector.selectionMode == .automatic,
                        tooltip: "Use laptop display if available, otherwise primary monitor"
                    ) {
                        screenSelector.selectAutomatic()
                        triggerWindowRecreation()
                        collapseAfterDelay()
                    }

                    // Individual screens
                    ForEach(screenSelector.availableScreens, id: \.self) { screen in
                        ScreenOptionRow(
                            label: screenLabel(for: screen),
                            isSelected: screenSelector.selectionMode == .specificScreen &&
                                       screenSelector.isSelected(screen),
                            tooltip: "Always show notch on this display"
                        ) {
                            screenSelector.selectScreen(screen)
                            triggerWindowRecreation()
                            collapseAfterDelay()
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }

    private var currentSelectionLabel: String {
        switch screenSelector.selectionMode {
        case .automatic:
            return "Auto"
        case .specificScreen:
            if let screen = screenSelector.selectedScreen {
                return screen.localizedName
            }
            return "Auto"
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func screenLabel(for screen: NSScreen) -> String {
        // Simplify display names for users
        if screen.isBuiltinDisplay {
            return "Built-in Display"
        }
        return screen.localizedName
    }

    private func triggerWindowRecreation() {
        // Notify to recreate the window
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func collapseAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                setExpanded(false)
            }
        }
    }
}

// MARK: - Screen Option Row

private struct ScreenOptionRow: View {
    let label: String
    let isSelected: Bool
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? TerminalColors.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TerminalColors.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
    }
}
