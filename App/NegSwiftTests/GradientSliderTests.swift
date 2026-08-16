//
//  GradientSliderTests.swift
//  NegSwiftTests
//

import AppKit
import Testing
@testable import NegSwift

@Suite struct GradientSliderTests {
    private let whiteBalanceRange = EditControlRanges.whiteBalance
    private let densityRange = EditControlRanges.density

    @Test func filtrationCyanEndpointsMatchSliderDirection() {
        let style = SliderTrackStyle.filtration(.cyan)
        // Left (−1) = complement; right (+1) = cyan filtration.
        #expect(style.knobColor(at: 0, enabled: true).isVisuallySimilar(to: FiltrationAxis.cyan.leftColor))
        #expect(style.knobColor(at: 1, enabled: true).isVisuallySimilar(to: FiltrationAxis.cyan.rightColor))
        #expect(style.knobColor(at: 0.5, enabled: true).isVisuallySimilar(to: SliderTrackPalette.neutral))
    }

    @Test func densityGradientRunsLightToDark() {
        let style = SliderTrackStyle.density
        #expect(style.knobColor(at: 0, enabled: true).luminance > style.knobColor(at: 1, enabled: true).luminance)
    }

    @Test func defaultPositionMapsRangeEndpoints() {
        #expect(SliderTrackPalette.normalizedValue(-1, in: whiteBalanceRange) == 0)
        #expect(SliderTrackPalette.normalizedValue(0, in: whiteBalanceRange) == 0.5)
        #expect(SliderTrackPalette.normalizedValue(1, in: whiteBalanceRange) == 1)
        #expect(SliderTrackPalette.normalizedValue(1, in: densityRange) == 0.5)
    }

    @Test func disabledKnobUsesFlatGray() {
        let style = SliderTrackStyle.chroma
        let color = style.knobColor(at: 0.4, enabled: false)
        #expect(color.isVisuallySimilar(to: SliderTrackPalette.disabledKnob))
    }
}

private extension NSColor {
    var luminance: Double {
        guard let color = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    func isVisuallySimilar(to other: NSColor) -> Bool {
        guard
            let a = usingColorSpace(.sRGB),
            let b = other.usingColorSpace(.sRGB)
        else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
