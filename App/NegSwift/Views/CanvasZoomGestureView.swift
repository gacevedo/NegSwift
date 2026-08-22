//
//  CanvasZoomGestureView.swift
//  NegSwift
//

import AppKit
import SwiftUI

/// Captures trackpad pinch, Option+scroll zoom, and two-finger scroll pan on the canvas.
struct CanvasZoomGestureView: NSViewRepresentable {
    var isZoomEnabled: Bool
    var isScrollPanEnabled: Bool
    var onZoomBy: (_ scaleFactor: CGFloat, _ anchorInView: CGPoint) -> Void
    var onScrollPanBy: (_ delta: CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CanvasZoomCaptureNSView {
        let view = CanvasZoomCaptureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CanvasZoomCaptureNSView, context: Context) {
        context.coordinator.isZoomEnabled = isZoomEnabled
        context.coordinator.isScrollPanEnabled = isScrollPanEnabled
        context.coordinator.onZoomBy = onZoomBy
        context.coordinator.onScrollPanBy = onScrollPanBy
        context.coordinator.hostView = nsView
        nsView.coordinator = context.coordinator
        nsView.refreshMonitors()
    }

    final class Coordinator {
        var isZoomEnabled = false
        var isScrollPanEnabled = false
        var onZoomBy: ((CGFloat, CGPoint) -> Void)?
        var onScrollPanBy: ((CGPoint) -> Void)?
        weak var hostView: NSView?
        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?

        func refreshMonitors() {
            guard hostView?.window != nil, isZoomEnabled || isScrollPanEnabled else {
                removeMonitors()
                return
            }
            installMonitorsIfNeeded()
        }

        private func installMonitorsIfNeeded() {
            guard scrollMonitor == nil, magnifyMonitor == nil else { return }

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.handleScrollWheel(event) else { return event }
                return nil
            }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, self.handleMagnify(event) else { return event }
                return nil
            }
        }

        private func removeMonitors() {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            }
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
                self.magnifyMonitor = nil
            }
        }

        private func handleScrollWheel(_ event: NSEvent) -> Bool {
            guard let hostView, let window = hostView.window, window.isKeyWindow else { return false }
            let location = hostView.convert(event.locationInWindow, from: nil)
            guard hostView.bounds.contains(location) else { return false }

            if isZoomEnabled, event.modifierFlags.contains(.option) {
                let factor: CGFloat
                if event.hasPreciseScrollingDeltas {
                    factor = pow(1.001, -event.scrollingDeltaY)
                } else {
                    factor = event.scrollingDeltaY > 0 ? 1.1 : 0.9
                }
                guard factor > 0 else { return false }
                onZoomBy?(factor, location)
                return true
            }

            guard isScrollPanEnabled else { return false }
            let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            guard delta.x != 0 || delta.y != 0 else { return false }
            onScrollPanBy?(delta)
            return true
        }

        private func handleMagnify(_ event: NSEvent) -> Bool {
            guard isZoomEnabled else { return false }
            guard let hostView, let window = hostView.window, window.isKeyWindow else { return false }
            let location = hostView.convert(event.locationInWindow, from: nil)
            guard hostView.bounds.contains(location) else { return false }

            let factor = 1.0 + event.magnification
            guard factor > 0 else { return false }
            onZoomBy?(factor, location)
            return true
        }

        deinit {
            removeMonitors()
        }
    }
}

final class CanvasZoomCaptureNSView: NSView {
    weak var coordinator: CanvasZoomGestureView.Coordinator?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshMonitors()
    }

    func refreshMonitors() {
        coordinator?.refreshMonitors()
    }
}
