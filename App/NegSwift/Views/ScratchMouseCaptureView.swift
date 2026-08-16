//
//  ScratchMouseCaptureView.swift
//  NegSwift
//

import AppKit
import SwiftUI

/// Native mouse + keyboard capture for the scratch tool — reliable cursor and Enter handling.
struct ScratchMouseCaptureView: NSViewRepresentable {
    let imagePixelSize: CGSize
    let imageRect: CGRect
    var onAddPoint: (CGPoint) -> Void
    var onFinish: () -> Void
    var onBackspace: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ScratchCaptureNSView {
        let view = ScratchCaptureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ScratchCaptureNSView, context: Context) {
        context.coordinator.onAddPoint = onAddPoint
        context.coordinator.onFinish = onFinish
        context.coordinator.onBackspace = onBackspace
        context.coordinator.onEscape = onEscape

        nsView.imagePixelSize = imagePixelSize
        nsView.imageRect = imageRect
        nsView.coordinator = context.coordinator
        nsView.refreshAfterSwiftUIUpdate()
    }

    final class Coordinator {
        var onAddPoint: ((CGPoint) -> Void)?
        var onFinish: (() -> Void)?
        var onBackspace: (() -> Void)?
        var onEscape: (() -> Void)?
    }
}

final class ScratchCaptureNSView: NSView {
    var imagePixelSize: CGSize = .zero
    var imageRect: CGRect = .zero
    weak var coordinator: ScratchMouseCaptureView.Coordinator?

    private var mouseDownLocation: NSPoint?
    private var shouldHoldKeyboardFocus = false
    private var keyMonitor: Any?

    private let clickDragThreshold: CGFloat = 5

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    deinit {
        removeKeyMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window != nil {
            installKeyMonitorIfNeeded()
        } else {
            removeKeyMonitor()
        }
    }

    func refreshAfterSwiftUIUpdate() {
        if shouldHoldKeyboardFocus {
            window?.makeFirstResponder(self)
        }
        syncCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        addCursorRect(imageRect, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if imageRect.contains(point) {
            NSCursor.crosshair.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        shouldHoldKeyboardFocus = true
        window?.makeFirstResponder(self)
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let start = mouseDownLocation else { return }
        mouseDownLocation = nil

        let drag = hypot(point.x - start.x, point.y - start.y)
        guard drag < clickDragThreshold else { return }

        if event.clickCount >= 2 {
            coordinator?.onFinish?()
            syncCursor()
            return
        }

        guard let normalized = ScratchToolOverlayGeometry.normalizedPoint(point, imageRect: imageRect) else { return }
        coordinator?.onAddPoint?(normalized)
        syncCursor()
    }

    override func keyDown(with event: NSEvent) {
        if !handleScratchKey(event) {
            super.keyDown(with: event)
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            guard self.shouldHoldKeyboardFocus || self.isMouseOverImage() else { return event }
            return self.handleScratchKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    @discardableResult
    private func handleScratchKey(_ event: NSEvent) -> Bool {
        switch ScratchToolKeyHandling.action(forKeyCode: event.keyCode) {
        case .finish:
            coordinator?.onFinish?()
            return true
        case .backspace:
            coordinator?.onBackspace?()
            return true
        case .escape:
            coordinator?.onEscape?()
            return true
        case nil:
            return false
        }
    }

    private func isMouseOverImage() -> Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return imageRect.contains(point)
    }

    private func syncCursor() {
        window?.invalidateCursorRects(for: self)
        if isMouseOverImage() {
            NSCursor.crosshair.set()
        }
    }
}
