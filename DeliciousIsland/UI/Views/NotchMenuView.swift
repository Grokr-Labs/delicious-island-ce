//
//  NotchMenuView.swift
//  DeliciousIsland
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @ObservedObject private var pluginRegistry = PluginRegistry.shared
    @State private var hooksInstalled: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var alwaysExpandForApprovals: Bool = AppSettings.alwaysExpandForApprovals
    @State private var playSoundForApprovals: Bool = AppSettings.playSoundForApprovals
    @State private var focusBehavior: AppSettings.FocusBehavior = AppSettings.focusBehavior

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                // Back button
                MenuRow(
                    icon: "chevron.left",
                    label: "Back"
                ) {
                    viewModel.toggleMenu()
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

            // Appearance settings
            ScreenPickerRow(screenSelector: screenSelector)
            SoundPickerRow(soundSelector: soundSelector)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Notification settings
            MenuToggleRow(
                icon: "bell.badge",
                label: "Always Expand for Approvals",
                isOn: alwaysExpandForApprovals
            ) {
                alwaysExpandForApprovals.toggle()
                AppSettings.alwaysExpandForApprovals = alwaysExpandForApprovals
            }
            .help("Expand notch for approvals even when terminal is visible")

            MenuToggleRow(
                icon: "speaker.wave.2",
                label: "Sound for Approvals",
                isOn: playSoundForApprovals
            ) {
                playSoundForApprovals.toggle()
                AppSettings.playSoundForApprovals = playSoundForApprovals
            }
            .help("Play notification sound when Claude needs approval")

            FocusBehaviorRow(selection: $focusBehavior)
                .onChange(of: focusBehavior) { _, newValue in
                    AppSettings.focusBehavior = newValue
                }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // System settings
            MenuToggleRow(
                icon: "power",
                label: "Launch at Login",
                isOn: launchAtLogin
            ) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.unregister()
                        launchAtLogin = false
                    } else {
                        try SMAppService.mainApp.register()
                        launchAtLogin = true
                    }
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }
            .help("Automatically start Delicious Island when you log in")

            MenuToggleRow(
                icon: "arrow.triangle.2.circlepath",
                label: "Hooks",
                isOn: hooksInstalled
            ) {
                if hooksInstalled {
                    HookInstaller.uninstall()
                    hooksInstalled = false
                } else {
                    HookInstaller.installIfNeeded()
                    hooksInstalled = true
                }
            }
            .help("Install hooks in ~/.claude/hooks/ to monitor Claude sessions")

            AccessibilityRow(isEnabled: AXIsProcessTrusted())

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Plugins
            PluginStatusRow(
                plugin: .claudeMem,
                status: pluginRegistry.status(for: .claudeMem)
            ) {
                Task {
                    await pluginRegistry.checkHealth(for: .claudeMem)
                }
            } onOpenViewer: {
                if let url = KnownPlugin.claudeMem.baseURL {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // About
            VersionRow()
                .help("Current app version")

            MenuRow(
                icon: "star",
                label: "Star on GitHub"
            ) {
                if let url = URL(string: "https://github.com/Grokr-Labs/delicious-island-ce") {
                    NSWorkspace.shared.open(url)
                }
            }
            .help("Open the GitHub repository in your browser")

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            MenuRow(
                icon: "xmark.circle",
                label: "Quit",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
    }

    private func refreshStates() {
        hooksInstalled = HookInstaller.isInstalled()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        alwaysExpandForApprovals = AppSettings.alwaysExpandForApprovals
        playSoundForApprovals = AppSettings.playSoundForApprovals
        screenSelector.refreshScreens()
        // Collapse any expanded pickers when menu opens
        screenSelector.isPickerExpanded = false
        soundSelector.isPickerExpanded = false
    }
}

// MARK: - Terminal Detection Permission Row

struct AccessibilityRow: View {
    let isEnabled: Bool

    @State private var isHovered = false
    @State private var refreshTrigger = false

    private var currentlyEnabled: Bool {
        // Re-check on each render when refreshTrigger changes
        _ = refreshTrigger
        return isEnabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("Terminal Detection")
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
                Button(action: openAccessibilitySettings) {
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
        .help("Detect when terminal is focused to avoid interrupting you")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrigger.toggle()
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
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
    }

    private var textColor: Color {
        if isDestructive {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

struct MenuToggleRow: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 11))
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
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - Focus Behavior Picker

struct FocusBehaviorRow: View {
    @Binding var selection: AppSettings.FocusBehavior

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Focus Behavior")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(selection.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered || isExpanded ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Control when Delicious Island takes keyboard focus")

            // Expanded options
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(AppSettings.FocusBehavior.allCases, id: \.rawValue) { option in
                        FocusOptionRow(
                            option: option,
                            isSelected: selection == option
                        ) {
                            selection = option
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered || isExpanded ? 1.0 : 0.7)
    }
}

struct FocusOptionRow: View {
    let option: AppSettings.FocusBehavior
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? TerminalColors.green : .white.opacity(0.4))

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isSelected || isHovered ? 1.0 : 0.7))

                    Text(option.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
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
    }
}

// MARK: - Plugin Status Row

struct PluginStatusRow: View {
    let plugin: KnownPlugin
    let status: PluginStatus
    let onRefresh: () -> Void
    let onOpenViewer: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text(plugin.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            // Status indicator
            statusView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .help(status.isAvailable ? "Open Claude-Mem viewer in browser" : "Check connection to Claude-Mem")
        .onTapGesture {
            if status.isAvailable {
                onOpenViewer()
            } else {
                onRefresh()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .unknown, .unavailable:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text("Offline")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

        case .checking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

        case .available:
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("Open")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .error:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 6, height: 6)
                Text("Error")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}


// MARK: - Version Row

struct VersionRow: View {
    @State private var isHovered = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))
                .frame(width: 16)

            Text("Version")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

            Spacer()

            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}
