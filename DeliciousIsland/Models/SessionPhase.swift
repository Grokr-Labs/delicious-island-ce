//
//  SessionPhase.swift
//  DeliciousIsland
//
//  Explicit state machine for Claude session lifecycle.
//  All state transitions are validated before being applied.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.jonathanworks.DeliciousIsland", category: "ApprovalType")

/// Type of approval prompt - determines which buttons to show
enum ApprovalType: Sendable, Equatable {
    /// Standard tool approval: Once / Session / Deny
    case standard

    /// Plan mode entry: "Enter plan mode?"
    /// Options: Yes (Plan) / No (Start Coding) / Deny
    case planEntry

    /// Plan mode execution: "Would you like to proceed?"
    /// Options: Auto-accept edits / Manual approve / Provide feedback
    case planExecution

    /// Folder/command access: "allow access to X/ and Y commands"
    /// Options: No / Yes / Allow Access (persistent)
    case folderCommandAccess

    /// MCP persistent permission: "don't ask again for plugin:X"
    /// Options: No / Yes / Remember
    case mcpPersistentPermission(pluginName: String)

    /// Detect approval type from the tool name and/or message content
    static func detect(toolName: String?, message: String?) -> ApprovalType {
        logger.info("ApprovalType.detect - toolName: \(toolName ?? "nil", privacy: .public), message: \(message ?? "nil", privacy: .public)")

        // Check tool name first - most reliable
        if let toolName = toolName {
            let lowerName = toolName.lowercased()

            // Plan mode detection
            if lowerName == "enterplanmode" || lowerName == "enter_plan_mode" {
                return .planEntry
            }
            if lowerName == "exitplanmode" || lowerName == "exit_plan_mode" {
                return .planExecution
            }

            // MCP tools: mcp__plugin_NAME_* pattern
            if lowerName.hasPrefix("mcp__") {
                let pluginName = extractMCPPluginName(from: toolName)
                return .mcpPersistentPermission(pluginName: pluginName)
            }
        }

        // Check message content for additional context
        if let message = message {
            // Normalize apostrophes (Claude uses curly quotes: ' vs straight: ')
            let normalizedMessage = message
                .replacingOccurrences(of: "'", with: "'")
                .replacingOccurrences(of: "'", with: "'")
                .lowercased()

            // Folder/command access detection - various phrasings
            if normalizedMessage.contains("allow access") ||
               normalizedMessage.contains("grant access") ||
               (normalizedMessage.contains("folder") && normalizedMessage.contains("command")) {
                return .folderCommandAccess
            }

            // Plan entry detection
            if normalizedMessage.contains("enter plan mode") ||
               normalizedMessage.contains("plan mode") ||
               normalizedMessage.contains("no code changes will be made until you approve") {
                return .planEntry
            }

            // Plan execution detection
            if normalizedMessage.contains("would you like to proceed") &&
               (normalizedMessage.contains("auto-accept") || normalizedMessage.contains("manually approve")) {
                return .planExecution
            }
        }

        return .standard
    }

    /// Extract MCP plugin name from tool name like "mcp__plugin_playwright_playwright__browser_click"
    private static func extractMCPPluginName(from toolName: String) -> String {
        // Pattern: mcp__plugin_NAME_SUBNAME__action or mcp__NAME__action
        let components = toolName.components(separatedBy: "__")
        if components.count >= 2 {
            // Try to get a readable name from the second component
            let namePart = components[1]
            // Remove "plugin_" prefix if present
            if namePart.hasPrefix("plugin_") {
                return String(namePart.dropFirst(7))
            }
            return namePart
        }
        return "MCP"
    }

    /// Extract plugin name from MCP permission message
    /// Example: "don't ask again for plugin:claude-mem:mcp-search - search commands"
    private static func extractPluginName(from message: String) -> String? {
        // Look for pattern: "plugin:NAME" or "plugin:NAME:SUBNAME"
        guard let range = message.range(of: "plugin:") else { return nil }
        let afterPlugin = message[range.upperBound...]

        // Find the end of the plugin name (space, dash, or end of string)
        var endIndex = afterPlugin.endIndex
        for (idx, char) in afterPlugin.enumerated() {
            if char == " " || char == "-" {
                endIndex = afterPlugin.index(afterPlugin.startIndex, offsetBy: idx)
                break
            }
        }

        let pluginName = String(afterPlugin[..<endIndex])
        return pluginName.isEmpty ? nil : pluginName
    }
}

/// Permission context for tools waiting for approval
struct PermissionContext: Sendable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date
    let transcriptPath: String?
    let message: String?
    let permissionMode: String?

    // Legacy approval type (for backward compatibility)
    let approvalType: ApprovalType

    // Dynamic menu generated from tool characteristics
    let menu: ExtractedMenu

    init(toolUseId: String, toolName: String, toolInput: [String: AnyCodable]?, receivedAt: Date, transcriptPath: String? = nil, message: String? = nil, permissionMode: String? = nil) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.receivedAt = receivedAt
        self.transcriptPath = transcriptPath
        self.message = message
        self.permissionMode = permissionMode
        self.approvalType = ApprovalType.detect(toolName: toolName, message: message)

        // Generate dynamic menu based on tool characteristics
        // Note: This is synchronous initialization using pre-computed menu
        // The actual ToolMenuMapper.generateMenu is called externally and passed in
        // For now, we generate a placeholder that will be replaced
        self.menu = ExtractedMenu(
            prompt: "Allow \(toolName)?",
            options: [],
            toolCategory: .unknown
        )
    }

    /// Full initializer with pre-generated menu
    init(toolUseId: String, toolName: String, toolInput: [String: AnyCodable]?, receivedAt: Date, transcriptPath: String? = nil, message: String? = nil, permissionMode: String? = nil, menu: ExtractedMenu) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.receivedAt = receivedAt
        self.transcriptPath = transcriptPath
        self.message = message
        self.permissionMode = permissionMode
        self.approvalType = ApprovalType.detect(toolName: toolName, message: message)
        self.menu = menu
    }

    /// Whether this is a plan mode approval (entry or execution)
    var isPlanMode: Bool {
        switch approvalType {
        case .planEntry, .planExecution:
            return true
        case .standard, .folderCommandAccess, .mcpPersistentPermission:
            return false
        }
    }

    /// The menu options to display (from dynamic menu)
    var menuOptions: [MenuOption] {
        menu.options
    }

    /// The prompt text to display
    var promptText: String {
        menu.prompt
    }

    /// Get the full command for Bash tool, or primary input for other tools
    var fullCommand: String? {
        guard let input = toolInput else { return nil }

        // For Bash tool, return the full command
        if toolName.lowercased() == "bash" {
            if let command = input["command"]?.value as? String {
                return command
            }
        }

        // For Write/Edit tools, show the file path
        if toolName.lowercased() == "write" || toolName.lowercased() == "edit" {
            if let path = input["file_path"]?.value as? String {
                return path
            }
        }

        // For Read tool, show the file path
        if toolName.lowercased() == "read" {
            if let path = input["file_path"]?.value as? String {
                return path
            }
        }

        return nil
    }

    /// Format tool input for display (truncated for UI)
    var formattedInput: String? {
        guard let input = toolInput else { return nil }
        var parts: [String] = []
        for (key, value) in input {
            let valueStr: String
            switch value.value {
            case let str as String:
                valueStr = str.count > 100 ? String(str.prefix(100)) + "..." : str
            case let num as Int:
                valueStr = String(num)
            case let num as Double:
                valueStr = String(num)
            case let bool as Bool:
                valueStr = bool ? "true" : "false"
            default:
                valueStr = "..."
            }
            parts.append("\(key): \(valueStr)")
        }
        return parts.joined(separator: "\n")
    }

    /// Format tool input with full details (not truncated)
    var fullFormattedInput: String? {
        guard let input = toolInput else { return nil }
        var parts: [String] = []
        for (key, value) in input {
            let valueStr: String
            switch value.value {
            case let str as String:
                valueStr = str
            case let num as Int:
                valueStr = String(num)
            case let num as Double:
                valueStr = String(num)
            case let bool as Bool:
                valueStr = bool ? "true" : "false"
            default:
                valueStr = String(describing: value.value)
            }
            parts.append("\(key): \(valueStr)")
        }
        return parts.joined(separator: "\n")
    }
}

extension PermissionContext: Equatable {
    nonisolated static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
        // Compare by identity fields only (AnyCodable doesn't conform to Equatable)
        lhs.toolUseId == rhs.toolUseId &&
        lhs.toolName == rhs.toolName &&
        lhs.receivedAt == rhs.receivedAt
    }
}

/// Explicit session phases - the state machine
enum SessionPhase: Sendable {
    /// Session is idle, waiting for user input or new activity
    case idle

    /// Claude is actively processing (running tools, generating response)
    case processing

    /// Claude has finished and is waiting for user input
    case waitingForInput

    /// A tool is waiting for user permission approval
    case waitingForApproval(PermissionContext)

    /// Context is being compacted (auto or manual)
    case compacting

    /// Session has ended
    case ended

    // MARK: - State Machine Transitions

    /// Check if a transition to the target phase is valid
    nonisolated func canTransition(to next: SessionPhase) -> Bool {
        switch (self, next) {
        // Terminal state - no transitions out
        case (.ended, _):
            return false

        // Any state can transition to ended
        case (_, .ended):
            return true

        // Idle transitions
        case (.idle, .processing):
            return true
        case (.idle, .waitingForApproval):
            return true  // Direct permission request on idle session
        case (.idle, .compacting):
            return true

        // Processing transitions
        case (.processing, .waitingForInput):
            return true
        case (.processing, .waitingForApproval):
            return true
        case (.processing, .compacting):
            return true
        case (.processing, .idle):
            return true  // Interrupt or quick completion

        // WaitingForInput transitions
        case (.waitingForInput, .processing):
            return true
        case (.waitingForInput, .idle):
            return true  // Can become idle
        case (.waitingForInput, .compacting):
            return true

        // WaitingForApproval transitions
        case (.waitingForApproval, .processing):
            return true  // Approved - tool will run
        case (.waitingForApproval, .idle):
            return true  // Denied or cancelled
        case (.waitingForApproval, .waitingForInput):
            return true  // Denied and Claude stopped
        case (.waitingForApproval, .waitingForApproval):
            return true  // Another tool needs approval (multiple pending permissions)

        // Compacting transitions
        case (.compacting, .processing):
            return true
        case (.compacting, .idle):
            return true
        case (.compacting, .waitingForInput):
            return true

        // Allow staying in same state (no-op transitions)
        default:
            return self == next
        }
    }

    /// Attempt to transition to a new phase, returns the new phase if valid
    nonisolated func transition(to next: SessionPhase) -> SessionPhase? {
        canTransition(to: next) ? next : nil
    }

    /// Whether this phase indicates the session needs user attention
    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput:
            return true
        default:
            return false
        }
    }

    /// Whether this phase indicates active processing
    var isActive: Bool {
        switch self {
        case .processing, .compacting:
            return true
        default:
            return false
        }
    }

    /// Whether this is a waitingForApproval phase
    var isWaitingForApproval: Bool {
        if case .waitingForApproval = self {
            return true
        }
        return false
    }

    /// Extract tool name if waiting for approval
    var approvalToolName: String? {
        if case .waitingForApproval(let ctx) = self {
            return ctx.toolName
        }
        return nil
    }
}

// MARK: - Equatable

extension SessionPhase: Equatable {
    nonisolated static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.waitingForInput, .waitingForInput): return true
        case (.waitingForApproval(let ctx1), .waitingForApproval(let ctx2)):
            return ctx1 == ctx2
        case (.compacting, .compacting): return true
        case (.ended, .ended): return true
        default: return false
        }
    }
}

// MARK: - Debug Description

extension SessionPhase: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .idle:
            return "idle"
        case .processing:
            return "processing"
        case .waitingForInput:
            return "waitingForInput"
        case .waitingForApproval(let ctx):
            return "waitingForApproval(\(ctx.toolName))"
        case .compacting:
            return "compacting"
        case .ended:
            return "ended"
        }
    }
}
