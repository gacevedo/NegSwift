//
//  ResetDefaultSlider.swift
//  NegSwift
//

import AppKit
import SwiftUI

final class KnobDoubleClickResetSlider: NSSlider {
    var defaultResetValue: Double = 0

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let cell = cell as? NSSliderCell {
            let point = convert(event.locationInWindow, from: nil)
            let knob = cell.knobRect(flipped: isFlipped).insetBy(dx: -6, dy: -6)
            if knob.contains(point) {
                doubleValue = defaultResetValue
                sendAction(action, to: target)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

final class SliderValueCoordinator: NSObject {
    var value: Binding<Double>
    private var syncTask: Task<Void, Never>?
    private var isProgrammaticUpdate = false

    init(value: Binding<Double>) {
        self.value = value
    }

    func scheduleSync(
        on slider: NSSlider,
        to target: Double,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        if let cell = slider.cell as? NSSliderCell {
            cell.minValue = range.lowerBound
            cell.maxValue = range.upperBound
        }
        if let resetSlider = slider as? KnobDoubleClickResetSlider {
            resetSlider.defaultResetValue = defaultValue
        }
        guard abs(slider.doubleValue - target) > 1e-9 else { return }

        syncTask?.cancel()
        syncTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard abs(slider.doubleValue - target) > 1e-9 else { return }
            isProgrammaticUpdate = true
            slider.doubleValue = target
            isProgrammaticUpdate = false
            slider.needsDisplay = true
        }
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        guard !isProgrammaticUpdate else { return }
        value.wrappedValue = sender.doubleValue
        sender.needsDisplay = true
    }
}

/// ``NSSlider`` wrapper — double-click the knob to jump back to ``defaultValue``.
struct ResetDefaultSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    func makeCoordinator() -> SliderValueCoordinator {
        SliderValueCoordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = KnobDoubleClickResetSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isContinuous = true
        slider.doubleValue = value
        slider.defaultResetValue = defaultValue
        slider.target = context.coordinator
        slider.action = #selector(SliderValueCoordinator.sliderChanged(_:))
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        guard let slider = nsView as? KnobDoubleClickResetSlider else { return }
        context.coordinator.value = $value
        context.coordinator.scheduleSync(
            on: slider,
            to: value,
            range: range,
            defaultValue: defaultValue
        )
    }
}
