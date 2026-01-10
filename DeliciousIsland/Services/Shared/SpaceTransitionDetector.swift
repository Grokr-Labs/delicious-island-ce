//
//  SpaceTransitionDetector.swift
//  DeliciousIsland
//
//  Detects when macOS Space/Desktop transitions occur
//  so the notch can hide during the animation
//

import AppKit
import Combine
import os.log

/// Detects Space transitions (virtual desktop changes) and publishes state
/// so the notch can hide during animations to avoid visual glitches
@MainActor
class SpaceTransitionDetector: ObservableObject {
    static let shared = SpaceTransitionDetector()

    /// Whether a Space transition is currently in progress
    @Published private(set) var isTransitioning: Bool = false

    private var workspaceObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var gestureMonitor: Any?
    private var transitionEndWorkItem: DispatchWorkItem?

    // Track horizontal scroll momentum for Space swipe detection
    private var horizontalScrollAccumulator: CGFloat = 0
    private var lastScrollTime: Date = .distantPast

    private let logger = Logger(subsystem: "com.deliciousisland", category: "SpaceTransition")

    private init() {
        setupWorkspaceObserver()
        setupScrollMonitor()
    }

    deinit {
        cleanup()
    }

    // MARK: - Workspace Observer

    private func setupWorkspaceObserver() {
        // Listen for Space change completion
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSpaceChangeComplete()
            }
        }
    }

    private func handleSpaceChangeComplete() {
        logger.debug("Space change completed")
        // Space change completed - end transition after brief delay
        // to ensure animation is fully finished
        transitionEndWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.endTransition()
        }
        transitionEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // MARK: - Scroll Monitor (for trackpad swipes)

    private func setupScrollMonitor() {
        // Monitor scroll wheel events - 4-finger swipes generate these
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in
                self?.handleScrollEvent(event)
            }
        }

        // Also try gesture events
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.gesture]) { [weak self] event in
            Task { @MainActor in
                self?.handleGestureEvent(event)
            }
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        // Reset accumulator if too much time has passed
        let now = Date()
        if now.timeIntervalSince(lastScrollTime) > 0.3 {
            horizontalScrollAccumulator = 0
        }
        lastScrollTime = now

        // Accumulate horizontal scroll
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        // Log significant scroll events
        if abs(deltaX) > 10 {
            logger.debug("Scroll event: deltaX=\(deltaX), deltaY=\(deltaY), phase=\(event.phase.rawValue), momentumPhase=\(event.momentumPhase.rawValue)")
        }

        // Check for horizontal-dominant scroll (potential Space swipe)
        if abs(deltaX) > abs(deltaY) * 2 && abs(deltaX) > 5 {
            horizontalScrollAccumulator += abs(deltaX)

            // If we've accumulated enough horizontal scroll, likely a Space swipe
            // Space swipes typically generate large cumulative horizontal movement
            if horizontalScrollAccumulator > 200 {
                logger.info("Detected potential Space swipe (accumulated: \(self.horizontalScrollAccumulator))")
                startTransition()
                horizontalScrollAccumulator = 0
            }
        }

        // Also check for scroll events with specific phases that indicate gesture start
        if event.phase == .mayBegin || event.phase == .began {
            // A gesture is starting - could be a Space swipe
            if abs(deltaX) > 20 && abs(deltaY) < 10 {
                logger.info("Horizontal gesture beginning detected")
                startTransition()
            }
        }
    }

    private func handleGestureEvent(_ event: NSEvent) {
        logger.debug("Gesture event received: type=\(event.type.rawValue), phase=\(event.phase.rawValue)")

        // Any gesture beginning could be a Space swipe
        if event.phase == .began {
            startTransition()
        }
    }

    // MARK: - Transition State Management

    private func startTransition() {
        guard !isTransitioning else { return }
        isTransitioning = true
        logger.info("Space transition STARTED")

        // Cancel any pending end transition
        transitionEndWorkItem?.cancel()

        // Set a maximum transition duration (safety fallback)
        let workItem = DispatchWorkItem { [weak self] in
            self?.endTransition()
        }
        transitionEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func endTransition() {
        guard isTransitioning else { return }
        isTransitioning = false
        logger.info("Space transition ENDED")
        transitionEndWorkItem?.cancel()
        transitionEndWorkItem = nil
        horizontalScrollAccumulator = 0
    }

    // MARK: - Cleanup

    private nonisolated func cleanup() {
        Task { @MainActor in
            transitionEndWorkItem?.cancel()
            transitionEndWorkItem = nil

            if let observer = workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }

            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }

            if let monitor = gestureMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
