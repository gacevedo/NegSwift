//
//  ResetDefaultSlider.swift
//  NegSwift
//

import AppKit
import SwiftUI

/// ``NSSlider`` wrapper — double-click the knob to jump back to ``defaultValue``.
struct ResetDefaultSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = KnobDoubleClickResetSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isContinuous = true
        slider.doubleValue = value
        slider.defaultResetValue = defaultValue
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.sliderChanged(_:))
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        guard let slider = nsView as? KnobDoubleClickResetSlider else { return }
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.defaultResetValue = defaultValue
        if abs(slider.doubleValue - value) > 1e-9 {
            slider.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func sliderChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

private final class KnobDoubleClickResetSlider: NSSlider {
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
