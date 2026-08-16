//
//  FiltrationSlider.swift
//  NegSwift
//

import AppKit
import SwiftUI

/// CMY filtration axis colors — negative = axis color, positive = complement (NegPy convention).
enum FiltrationAxis: CaseIterable {
    case cyan
    case magenta
    case yellow

    var leftColor: NSColor {
        switch self {
        case .cyan: NSColor(srgbRed: 0.0, green: 0.69, blue: 0.69, alpha: 1.0)
        case .magenta: NSColor(srgbRed: 0.69, green: 0.0, blue: 0.69, alpha: 1.0)
        case .yellow: NSColor(srgbRed: 0.69, green: 0.69, blue: 0.0, alpha: 1.0)
        }
    }

    var rightColor: NSColor {
        switch self {
        case .cyan: NSColor(srgbRed: 0.69, green: 0.18, blue: 0.18, alpha: 1.0)
        case .magenta: NSColor(srgbRed: 0.18, green: 0.69, blue: 0.18, alpha: 1.0)
        case .yellow: NSColor(srgbRed: 0.18, green: 0.35, blue: 0.69, alpha: 1.0)
        }
    }

    static let neutralTrack = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)
    static let disabledTrack = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    static let disabledKnob = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)
    static let centerTick = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)

    func normalizedValue(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return (value - range.lowerBound) / span
    }

    func knobColor(value: Double, in range: ClosedRange<Double>, enabled: Bool) -> NSColor {
        guard enabled else { return Self.disabledKnob }
        return trackColor(at: normalizedValue(value, in: range))
    }

    func trackColor(at position: Double) -> NSColor {
        let t = min(max(position, 0), 1)
        if t <= 0.5 {
            return leftColor.interpolated(to: Self.neutralTrack, fraction: t * 2)
        }
        return Self.neutralTrack.interpolated(to: rightColor, fraction: (t - 0.5) * 2)
    }
}

private extension NSColor {
    func interpolated(to other: NSColor, fraction: Double) -> NSColor {
        blended(withFraction: CGFloat(min(max(fraction, 0), 1)), of: other) ?? other
    }
}

final class FiltrationGradientSliderCell: NSSliderCell {
    var filtrationAxis: FiltrationAxis = .cyan

    private var isControlEnabled: Bool {
        (controlView as? NSControl)?.isEnabled ?? true
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let barHeight: CGFloat = 6
        var bar = rect
        bar.origin.y += floor((rect.height - barHeight) / 2)
        bar.size.height = barHeight

        let path = NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3)

        if isControlEnabled {
            let gradient = NSGradient(
                colors: [
                    filtrationAxis.leftColor,
                    FiltrationAxis.neutralTrack,
                    filtrationAxis.rightColor,
                ],
                atLocations: [0, 0.5, 1],
                colorSpace: .sRGB
            )
            gradient?.draw(in: path, angle: 0)

            let tickX = floor(bar.midX) + 0.5
            FiltrationAxis.centerTick.setStroke()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: tickX, y: bar.minY + 1))
            tick.line(to: NSPoint(x: tickX, y: bar.maxY - 1))
            tick.lineWidth = 1
            tick.stroke()
        } else {
            FiltrationAxis.disabledTrack.setFill()
            path.fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let diameter = min(knobRect.width, knobRect.height, 12)
        let origin = NSPoint(
            x: knobRect.midX - diameter / 2,
            y: knobRect.midY - diameter / 2
        )
        let knob = NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: diameter, height: diameter)))
        let range = minValue ... maxValue
        let color = filtrationAxis.knobColor(value: doubleValue, in: range, enabled: isControlEnabled)
        color.setFill()
        knob.fill()
    }
}

/// Gradient-track CMY slider — double-click the knob to reset to ``defaultValue``.
struct FiltrationSlider: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var value: Double
    let axis: FiltrationAxis
    let range: ClosedRange<Double>
    let defaultValue: Double

    func makeCoordinator() -> SliderValueCoordinator {
        SliderValueCoordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let cell = FiltrationGradientSliderCell(textCell: "")
        cell.filtrationAxis = axis
        cell.minValue = range.lowerBound
        cell.maxValue = range.upperBound
        cell.isContinuous = true
        cell.doubleValue = value

        let slider = KnobDoubleClickResetSlider()
        slider.cell = cell
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
        if let cell = slider.cell as? FiltrationGradientSliderCell {
            cell.filtrationAxis = axis
        }
        slider.isEnabled = isEnabled
        context.coordinator.value = $value
        context.coordinator.scheduleSync(
            on: slider,
            to: value,
            range: range,
            defaultValue: defaultValue
        )
        slider.needsDisplay = true
    }
}
