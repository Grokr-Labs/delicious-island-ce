//
//  UpdateStubs.swift
//  DeliciousIsland CE
//
//  Stub implementation for Sparkle auto-updates (CE uses GitHub Releases)
//

import Foundation
import Combine

/// Stub for UpdateManager (premium feature - CE uses GitHub releases)
@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case found(version: String, notes: String?)
        case downloading(progress: Double)
        case extracting
        case readyToInstall
        case installing
        case error(String)
    }

    @Published var state: UpdateState = .idle
    @Published var hasUnseenUpdate: Bool = false

    func checkForUpdates() {
        // CE: Direct users to GitHub Releases
        // Premium features use Sparkle for auto-updates
    }

    func markUpdateSeen() {
        hasUnseenUpdate = false
    }
}
