//
//  PluginState.swift
//  DeliciousIsland
//
//  Plugin status models for external integrations
//

import Foundation

/// Status of an external plugin
enum PluginStatus: Equatable, Sendable {
    case unknown
    case checking
    case available
    case unavailable
    case error(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking..."
        case .available: return "Connected"
        case .unavailable: return "Not Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Known plugins that Delicious Island can integrate with
enum KnownPlugin: String, CaseIterable {
    case claudeMem = "claude-mem"

    var displayName: String {
        switch self {
        case .claudeMem: return "Claude-Mem"
        }
    }

    var healthEndpoint: URL? {
        switch self {
        case .claudeMem:
            return URL(string: "http://localhost:37777/health")
        }
    }

    var baseURL: URL? {
        switch self {
        case .claudeMem:
            return URL(string: "http://localhost:37777")
        }
    }
}
