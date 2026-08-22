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
    let brushSize: Int
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
        nsView.brushSize = brushSize
        nsView.coordinator = context.coordinator
        nsView.updateTrackingAreas()
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
    var brushSize = EditControlDefaults.manualDustSize
    weak var coordinator: ScratchMouseCaptureView.Coordinator?

    private var mouseDownLocation: NSPoint?
    private var shouldHoldKeyboardFocus = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var isBrushCursorHidden = false

    private let clickDragThreshold: CGFloat = 5

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override var isOpaque: Bool { false }

    deinit {
        removeMonitors()
        restoreCursor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.acceptsMouseMovedEvents = true
            installKeyMonitorIfNeeded()
            installMouseMonitorIfNeeded()
            syncCursor()
        } else {
            removeMonitors()
            restoreCursor()
        }
    }

    func refreshAfterSwiftUIUpdate() {
        if shouldHoldKeyboardFocus {
            window?.makeFirstResponder(self)
        }
        needsDisplay = true
        syncCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        let area = NSTrackingArea(
            rect: imageRect,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard imageRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isMouseOverImage() else { return }
        let point = currentMouseLocation()
        let radius = ScratchToolOverlayGeometry.brushScreenRadius(
            brushSize: CGFloat(brushSize),
            imageRect: imageRect
        )
        guard radius > 0 else { return }

        let brushRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let fill = NSColor.controlAccentColor.withAlphaComponent(60 / 255)
        fill.setFill()
        NSBezierPath(ovalIn: brushRect).fill()

        NSColor.white.setStroke()
        let outline = NSBezierPath(ovalIn: brushRect)
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseMoved(with event: NSEvent) {
        needsDisplay = true
        syncCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        needsDisplay = true
        syncCursor()
    }

    override func mouseExited(with event: NSEvent) {
        needsDisplay = true
        restoreCursor()
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

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.window === event.window else { return event }
            self.syncCursor()
            return event
        }
    }

    private func removeMonitors() {
        removeKeyMonitor()
        removeMouseMonitor()
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
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

    private func currentMouseLocation() -> NSPoint {
        guard let window else { return .zero }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    private func isMouseOverImage() -> Bool {
        imageRect.contains(currentMouseLocation())
    }

    private func syncCursor() {
        let overImage = isMouseOverImage()
        if overImage {
            guard !isBrushCursorHidden else { return }
            isBrushCursorHidden = true
            NSCursor.hide()
        } else {
            guard isBrushCursorHidden else { return }
            isBrushCursorHidden = false
            NSCursor.unhide()
            NSCursor.arrow.set()
        }
    }

    private func restoreCursor() {
        guard isBrushCursorHidden else { return }
        isBrushCursorHidden = false
        NSCursor.unhide()
        NSCursor.arrow.set()
    }
}
