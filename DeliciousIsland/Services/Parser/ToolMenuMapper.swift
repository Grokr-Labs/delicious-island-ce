//
//  ToolMenuMapper.swift
//  DeliciousIsland
//
//  Maps tool names to their expected approval menu options.
//  Claude Code generates predictable menus based on tool type.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.jonathanworks.DeliciousIsland", category: "ToolMenuMapper")

/// Represents a single menu option that Claude Code displays
struct MenuOption: Sendable, Equatable, Identifiable {
    let id: Int          // Option number for UI (1, 2, 3, etc.)
    let key: String      // Actual key to send ("1", "2", "n", etc.) - may differ from id
    let label: String    // Display text ("Yes", "Yes, and don't ask again", etc.)
    let shortLabel: String  // Compact label for buttons
    let hookDecision: String?  // Hook response: "allow", "deny", nil (needs native)
    let isPersistent: Bool     // Does this option persist the permission?
    let requiresNativeMenu: Bool  // Must use Claude's native menu (via tmux or ask)

    /// Convenience initializer that sets key = id
    init(id: Int, label: String, shortLabel: String, hookDecision: String?, isPersistent: Bool, requiresNativeMenu: Bool) {
        self.id = id
        self.key = "\(id)"
        self.label = label
        self.shortLabel = shortLabel
        self.hookDecision = hookDecision
        self.isPersistent = isPersistent
        self.requiresNativeMenu = requiresNativeMenu
    }

    /// Full initializer with explicit key
    init(id: Int, key: String, label: String, shortLabel: String, hookDecision: String?, isPersistent: Bool, requiresNativeMenu: Bool) {
        self.id = id
        self.key = key
        self.label = label
        self.shortLabel = shortLabel
        self.hookDecision = hookDecision
        self.isPersistent = isPersistent
        self.requiresNativeMenu = requiresNativeMenu
    }

    /// Button style based on option semantics
    var style: MenuOptionStyle {
        if label.lowercased().contains("no") || label.lowercased().contains("deny") {
            return .deny
        } else if isPersistent {
            return .persistent
        } else {
            return .approve
        }
    }
}

enum MenuOptionStyle: Sendable {
    case approve    // Standard approval (white button)
    case persistent // Persistent approval (green/blue button)
    case deny       // Denial (gray button)
}

/// The extracted menu for a permission request
struct ExtractedMenu: Sendable {
    let prompt: String         // "Allow Claude to use [Tool]?"
    let options: [MenuOption]  // Available options
    let toolCategory: ToolCategory  // Category for logging/debugging

    /// Get option by number (1-indexed)
    func option(number: Int) -> MenuOption? {
        options.first { $0.id == number }
    }
}

/// Tool categories for menu generation
enum ToolCategory: Sendable {
    case standard           // Bash, Edit, Write, Read, etc.
    case mcp(plugin: String) // MCP tools: mcp__plugin_NAME__action
    case planEntry          // EnterPlanMode
    case planExecution      // ExitPlanMode
    case folderAccess       // Folder/command access requests
    case unknown
}

/// Maps tools to their expected menus
struct ToolMenuMapper {

    /// Generate menu options for a permission request
    static func generateMenu(
        toolName: String?,
        toolInput: [String: Any]?,
        permissionMode: String?,
        message: String? = nil
    ) -> ExtractedMenu {

        guard let toolName = toolName else {
            return defaultMenu(prompt: "Allow this action?")
        }

        let category = categorize(toolName: toolName, toolInput: toolInput, message: message)

        logger.info("Generating menu for tool: \(toolName, privacy: .public), category: \(String(describing: category), privacy: .public)")

        switch category {
        case .planEntry:
            return planEntryMenu()

        case .planExecution:
            return planExecutionMenu()

        case .mcp(let plugin):
            return mcpMenu(plugin: plugin, toolName: toolName)

        case .folderAccess:
            return folderAccessMenu(toolInput: toolInput)

        case .standard:
            return standardMenu(toolName: toolName)

        case .unknown:
            return defaultMenu(prompt: "Allow \(toolName)?")
        }
    }

    // MARK: - Tool Categorization

    private static func categorize(toolName: String, toolInput: [String: Any]?, message: String?) -> ToolCategory {
        let lowerName = toolName.lowercased()

        // Plan mode tools
        if lowerName == "enterplanmode" || lowerName == "enter_plan_mode" {
            return .planEntry
        }
        if lowerName == "exitplanmode" || lowerName == "exit_plan_mode" {
            return .planExecution
        }

        // MCP tools: mcp__plugin_NAME_SUBNAME__action
        if lowerName.hasPrefix("mcp__") {
            let plugin = extractMCPPlugin(from: toolName)
            return .mcp(plugin: plugin)
        }

        // Check message content for folder access patterns
        // Claude Code shows "allow access to X/" when first accessing a folder outside the project
        if let message = message {
            let normalizedMessage = message
                .replacingOccurrences(of: "'", with: "'")
                .replacingOccurrences(of: "'", with: "'")
                .lowercased()

            // Folder access detection: "allow access to X/" or "always allow access"
            if normalizedMessage.contains("allow access to") ||
               normalizedMessage.contains("always allow access") {
                return .folderAccess
            }
        }

        // Standard tools
        let standardTools = ["bash", "edit", "write", "read", "glob", "grep", "ls", "webfetch", "websearch"]
        if standardTools.contains(lowerName) {
            return .standard
        }

        return .standard
    }

    private static func extractMCPPlugin(from toolName: String) -> String {
        // Pattern: mcp__plugin_NAME_SUBNAME__action or mcp__NAME__action
        let components = toolName.components(separatedBy: "__")
        if components.count >= 2 {
            let namePart = components[1]
            // Remove "plugin_" prefix if present
            if namePart.lowercased().hasPrefix("plugin_") {
                let afterPrefix = String(namePart.dropFirst(7))
                // Get first underscore-separated part
                return afterPrefix.components(separatedBy: "_").first ?? afterPrefix
            }
            return namePart
        }
        return "MCP"
    }

    // MARK: - Menu Generators

    private static func standardMenu(toolName: String) -> ExtractedMenu {
        return ExtractedMenu(
            prompt: "Allow Claude to use \(toolName)?",
            options: [
                MenuOption(
                    id: 1,
                    label: "Yes",
                    shortLabel: "Once",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 2,
                    label: "Yes, and don't ask again this session",
                    shortLabel: "Session",
                    hookDecision: nil,  // Hook doesn't support session-level yet
                    isPersistent: true,
                    requiresNativeMenu: true  // Need native menu for session approval
                ),
                MenuOption(
                    id: 3,
                    label: "No",
                    shortLabel: "Deny",
                    hookDecision: "deny",
                    isPersistent: false,
                    requiresNativeMenu: false
                )
            ],
            toolCategory: .standard
        )
    }

    private static func mcpMenu(plugin: String, toolName: String) -> ExtractedMenu {
        return ExtractedMenu(
            prompt: "Allow \(plugin) MCP tool?",
            options: [
                MenuOption(
                    id: 1,
                    label: "Yes",
                    shortLabel: "Once",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 2,
                    label: "Yes, and don't ask again for \(plugin)",
                    shortLabel: "Remember",
                    hookDecision: nil,  // Persistent MCP requires native menu
                    isPersistent: true,
                    requiresNativeMenu: true
                ),
                MenuOption(
                    id: 3,
                    label: "No",
                    shortLabel: "Deny",
                    hookDecision: "deny",
                    isPersistent: false,
                    requiresNativeMenu: false
                )
            ],
            toolCategory: .mcp(plugin: plugin)
        )
    }

    private static func planEntryMenu() -> ExtractedMenu {
        return ExtractedMenu(
            prompt: "Enter plan mode?",
            options: [
                MenuOption(
                    id: 1,
                    label: "Yes, enter plan mode",
                    shortLabel: "Plan",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 2,
                    label: "No, start coding now",
                    shortLabel: "Code",
                    hookDecision: nil,  // Need native menu for skip
                    isPersistent: false,
                    requiresNativeMenu: true
                ),
                MenuOption(
                    id: 3,
                    label: "Cancel",
                    shortLabel: "Cancel",
                    hookDecision: "deny",
                    isPersistent: false,
                    requiresNativeMenu: false
                )
            ],
            toolCategory: .planEntry
        )
    }

    private static func planExecutionMenu() -> ExtractedMenu {
        return ExtractedMenu(
            prompt: "Execute plan?",
            options: [
                MenuOption(
                    id: 1,
                    label: "Auto-accept all edits",
                    shortLabel: "Auto",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 2,
                    label: "Manually approve each edit",
                    shortLabel: "Manual",
                    hookDecision: nil,
                    isPersistent: false,
                    requiresNativeMenu: true
                ),
                MenuOption(
                    id: 3,
                    label: "Provide feedback",
                    shortLabel: "Feedback",
                    hookDecision: nil,
                    isPersistent: false,
                    requiresNativeMenu: true
                )
            ],
            toolCategory: .planExecution
        )
    }

    private static func folderAccessMenu(toolInput: [String: Any]?) -> ExtractedMenu {
        let folder = (toolInput?["folder"] as? String) ?? "folder"
        return ExtractedMenu(
            prompt: "Allow access to \(folder)?",
            options: [
                MenuOption(
                    id: 1,
                    label: "Yes, allow once",
                    shortLabel: "Once",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 2,
                    label: "Yes, allow access to folder and commands",
                    shortLabel: "Allow",
                    hookDecision: nil,
                    isPersistent: true,
                    requiresNativeMenu: true
                ),
                MenuOption(
                    id: 3,
                    label: "No",
                    shortLabel: "Deny",
                    hookDecision: "deny",
                    isPersistent: false,
                    requiresNativeMenu: false
                )
            ],
            toolCategory: .folderAccess
        )
    }

    private static func defaultMenu(prompt: String) -> ExtractedMenu {
        return ExtractedMenu(
            prompt: prompt,
            options: [
                MenuOption(
                    id: 1,
                    label: "Yes",
                    shortLabel: "Once",
                    hookDecision: "allow",
                    isPersistent: false,
                    requiresNativeMenu: false
                ),
                MenuOption(
                    id: 3,
                    label: "No",
                    shortLabel: "Deny",
                    hookDecision: "deny",
                    isPersistent: false,
                    requiresNativeMenu: false
                )
            ],
            toolCategory: .unknown
        )
    }
}
