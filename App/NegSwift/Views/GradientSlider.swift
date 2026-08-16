//
//  GradientSlider.swift
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
}

enum SliderTrackStyle {
    case filtration(FiltrationAxis)
    case density
    case grade
    case chroma
    case analysisBuffer
    case fineRotation

    fileprivate var gradient: (colors: [NSColor], locations: [CGFloat]) {
        switch self {
        case .filtration(let axis):
            return (
                [axis.leftColor, SliderTrackPalette.neutral, axis.rightColor],
                [0, 0.5, 1]
            )
        case .density:
            // Lower density = brighter print; higher density = darker.
            return (
                [
                    NSColor(srgbRed: 0.86, green: 0.86, blue: 0.86, alpha: 1.0),
                    NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
                ],
                [0, 1]
            )
        case .grade:
            // Lower ISO-R = harder/contrastier; higher = softer/flatter.
            return (
                [
                    NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1.0),
                    NSColor(srgbRed: 0.72, green: 0.72, blue: 0.72, alpha: 1.0),
                ],
                [0, 1]
            )
        case .chroma:
            // Flat gray toward a slightly richer neutral — no hue.
            return (
                [
                    NSColor(srgbRed: 0.52, green: 0.52, blue: 0.52, alpha: 1.0),
                    NSColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1.0),
                ],
                [0, 1]
            )
        case .analysisBuffer:
            // Full frame toward stronger edge inset.
            return (
                [
                    NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1.0),
                    NSColor(srgbRed: 0.24, green: 0.24, blue: 0.24, alpha: 1.0),
                ],
                [0, 1]
            )
        case .fineRotation:
            return (
                [
                    NSColor(srgbRed: 0.36, green: 0.36, blue: 0.36, alpha: 1.0),
                    SliderTrackPalette.neutral,
                    NSColor(srgbRed: 0.36, green: 0.36, blue: 0.36, alpha: 1.0),
                ],
                [0, 0.5, 1]
            )
        }
    }

    func knobColor(at position: Double, enabled: Bool) -> NSColor {
        guard enabled else { return SliderTrackPalette.disabledKnob }
        let gradient = gradient
        return SliderTrackPalette.interpolatedColor(at: position, colors: gradient.colors, locations: gradient.locations)
    }
}

enum SliderTrackPalette {
    static let neutral = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)
    static let disabledTrack = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    static let disabledKnob = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)
    static let defaultTick = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1.0)

    static func normalizedValue(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return (value - range.lowerBound) / span
    }

    static func interpolatedColor(at position: Double, colors: [NSColor], locations: [CGFloat]) -> NSColor {
        let t = min(max(position, 0), 1)
        guard colors.count == locations.count, colors.count >= 2 else {
            return colors.first ?? neutral
        }

        if t <= locations[0] { return colors[0] }
        if t >= locations[locations.count - 1] { return colors[colors.count - 1] }

        for index in 1 ..< locations.count where t <= locations[index] {
            let startLocation = locations[index - 1]
            let endLocation = locations[index]
            let segmentSpan = endLocation - startLocation
            let fraction = segmentSpan > 0 ? (t - startLocation) / segmentSpan : 0
            return colors[index - 1].interpolated(to: colors[index], fraction: fraction)
        }

        return colors[colors.count - 1]
    }
}

private extension NSColor {
    func interpolated(to other: NSColor, fraction: Double) -> NSColor {
        blended(withFraction: CGFloat(min(max(fraction, 0), 1)), of: other) ?? other
    }
}

final class GradientSliderCell: NSSliderCell {
    var trackStyle: SliderTrackStyle = .density
    var defaultPosition: Double = 0.5

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
            let gradient = trackStyle.gradient
            NSGradient(
                colors: gradient.colors,
                atLocations: gradient.locations,
                colorSpace: .sRGB
            )?.draw(in: path, angle: 0)

            let tickX = bar.minX + CGFloat(defaultPosition) * bar.width
            let alignedTickX = floor(tickX) + 0.5
            SliderTrackPalette.defaultTick.setStroke()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: alignedTickX, y: bar.minY + 1))
            tick.line(to: NSPoint(x: alignedTickX, y: bar.maxY - 1))
            tick.lineWidth = 1
            tick.stroke()
        } else {
            SliderTrackPalette.disabledTrack.setFill()
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
        let position = SliderTrackPalette.normalizedValue(doubleValue, in: range)
        let color = trackStyle.knobColor(at: position, enabled: isControlEnabled)
        color.setFill()
        knob.fill()
    }
}

/// Gradient-track slider — double-click the knob to reset to ``defaultValue``.
struct GradientSlider: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var value: Double
    let style: SliderTrackStyle
    let range: ClosedRange<Double>
    let defaultValue: Double

    func makeCoordinator() -> SliderValueCoordinator {
        SliderValueCoordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let cell = GradientSliderCell(textCell: "")
        cell.trackStyle = style
        cell.defaultPosition = SliderTrackPalette.normalizedValue(defaultValue, in: range)
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
        if let cell = slider.cell as? GradientSliderCell {
            cell.trackStyle = style
            cell.defaultPosition = SliderTrackPalette.normalizedValue(defaultValue, in: range)
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

typealias FiltrationSlider = GradientSlider

extension GradientSlider {
    init(
        value: Binding<Double>,
        axis: FiltrationAxis,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) {
        self.init(
            value: value,
            style: .filtration(axis),
            range: range,
            defaultValue: defaultValue
        )
    }
}
