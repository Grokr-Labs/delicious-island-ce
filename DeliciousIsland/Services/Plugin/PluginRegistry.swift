//
//  PluginRegistry.swift
//  DeliciousIsland
//
//  Central registry for external plugin integrations
//  Manages health checks and status tracking
//

import Combine
import Foundation
import os.log

/// Manages external plugin integrations and their health status
@MainActor
class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()

    /// Logger for plugin registry
    private let logger = Logger(subsystem: "com.deliciousisland", category: "Plugins")

    /// Published status for each known plugin
    @Published private(set) var pluginStatus: [KnownPlugin: PluginStatus] = [:]

    /// Health check interval (60 seconds)
    private let healthCheckInterval: TimeInterval = 60

    /// Health check timer task
    private var healthCheckTask: Task<Void, Never>?

    private init() {
        // Initialize all plugins as unknown
        for plugin in KnownPlugin.allCases {
            pluginStatus[plugin] = .unknown
        }
    }

    // MARK: - Public API

    /// Get status for a specific plugin
    func status(for plugin: KnownPlugin) -> PluginStatus {
        pluginStatus[plugin] ?? .unknown
    }

    /// Check health of a specific plugin
    func checkHealth(for plugin: KnownPlugin) async {
        pluginStatus[plugin] = .checking

        guard let healthURL = plugin.healthEndpoint else {
            pluginStatus[plugin] = .error("No health endpoint")
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    pluginStatus[plugin] = .available
                    logger.info("\(plugin.displayName) is available")
                } else {
                    pluginStatus[plugin] = .unavailable
                    logger.info("\(plugin.displayName) returned status \(httpResponse.statusCode)")
                }
            } else {
                pluginStatus[plugin] = .unavailable
            }
        } catch {
            // Connection refused or timeout means plugin isn't running
            if (error as NSError).code == NSURLErrorCannotConnectToHost ||
               (error as NSError).code == NSURLErrorTimedOut {
                pluginStatus[plugin] = .unavailable
            } else {
                pluginStatus[plugin] = .error(error.localizedDescription)
            }
            logger.debug("\(plugin.displayName) health check failed: \(error.localizedDescription)")
        }
    }

    /// Check health of all known plugins
    func checkAllPlugins() async {
        await withTaskGroup(of: Void.self) { group in
            for plugin in KnownPlugin.allCases {
                group.addTask { [weak self] in
                    await self?.checkHealth(for: plugin)
                }
            }
        }
    }

    /// Start periodic health checks
    func startHealthChecks() {
        guard healthCheckTask == nil else { return }

        // Initial check
        Task {
            await checkAllPlugins()
        }

        // Periodic checks
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthCheckInterval ?? 60))
                await self?.checkAllPlugins()
            }
        }

        logger.info("Started plugin health checks")
    }

    /// Stop periodic health checks
    func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        logger.info("Stopped plugin health checks")
    }

    // MARK: - Convenience

    /// Whether Claude-Mem is available
    var isClaudeMemAvailable: Bool {
        status(for: .claudeMem).isAvailable
    }
}
