//
//  CropKeyCaptureView.swift
//  NegSwift
//

import AppKit
import SwiftUI

/// Captures Return / keypad Enter while the crop tool is active.
struct CropKeyCaptureView: NSViewRepresentable {
    var onApply: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CropKeyCaptureNSView {
        let view = CropKeyCaptureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CropKeyCaptureNSView, context: Context) {
        context.coordinator.onApply = onApply
        nsView.coordinator = context.coordinator
        nsView.claimKeyboardFocusIfNeeded()
    }

    final class Coordinator {
        var onApply: (() -> Void)?
    }
}

final class CropKeyCaptureNSView: NSView {
    weak var coordinator: CropKeyCaptureView.Coordinator?
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    deinit {
        removeKeyMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitorIfNeeded()
            claimKeyboardFocusIfNeeded()
        } else {
            removeKeyMonitor()
        }
    }

    func claimKeyboardFocusIfNeeded() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if !handleApplyKey(event) {
            super.keyDown(with: event)
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.handleApplyKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    @discardableResult
    private func handleApplyKey(_ event: NSEvent) -> Bool {
        guard CropToolKeyHandling.isApplyKey(event.keyCode) else { return false }
        coordinator?.onApply?()
        return true
    }
}
