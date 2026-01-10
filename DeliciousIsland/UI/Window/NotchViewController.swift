//
//  NotchViewController.swift
//  DeliciousIsland
//
//  Hosts the SwiftUI NotchView in AppKit with click-through support
//

import AppKit
import SwiftUI

/// Custom NSHostingView that only accepts mouse events within the panel bounds.
/// Clicks outside the panel pass through to windows behind.
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Calculate the rect where we want to accept hits
        let rect = hitTestRect()

        // If outside our interactive area, pass through
        guard rect.contains(point) else {
            return nil  // Pass through to windows behind
        }

        return super.hitTest(point)
    }

    override var acceptsFirstResponder: Bool { true }
}

class NotchViewController: NSViewController {
    private let viewModel: NotchViewModel
    private var hostingView: PassThroughHostingView<NotchView>!

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(rootView: NotchView(viewModel: viewModel))

        // Calculate the hit-test rect based on panel state
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry

            // Window coordinates: origin at bottom-left, Y increases upward
            // The window is positioned at top of screen, so panel is at top of window
            let windowHeight = geometry.windowHeight

            switch vm.status {
            case .opened:
                // Use the maximum possible size to ensure all content types are covered
                // This fixes an issue where contentType changes aren't reflected in hitTestRect
                let maxHeight: CGFloat = 600  // Covers chat (580), menu (420+), instances (320)
                let panelWidth: CGFloat = min(geometry.screenRect.width * 0.5, 600) + 52
                let panelHeight = maxHeight
                let screenWidth = geometry.screenRect.width
                return CGRect(
                    x: (screenWidth - panelWidth) / 2,
                    y: windowHeight - panelHeight,
                    width: panelWidth,
                    height: panelHeight
                )
            case .closed, .popping:
                // When closed, use the notch rect
                let notchRect = geometry.deviceNotchRect
                let screenWidth = geometry.screenRect.width
                // Add some padding for easier interaction
                return CGRect(
                    x: (screenWidth - notchRect.width) / 2 - 10,
                    y: windowHeight - notchRect.height - 5,
                    width: notchRect.width + 20,
                    height: notchRect.height + 10
                )
            }
        }

        self.view = hostingView
    }
}
