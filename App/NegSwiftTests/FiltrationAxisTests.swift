//
//  FiltrationAxisTests.swift
//  NegSwiftTests
//

import AppKit
import Testing
@testable import NegSwift

@Suite struct FiltrationAxisTests {
    private let range = EditControlRanges.whiteBalance

    @Test func cyanEndpointsMatchNegPyConvention() {
        let axis = FiltrationAxis.cyan
        #expect(axis.trackColor(at: 0).isVisuallySimilar(to: axis.leftColor))
        #expect(axis.trackColor(at: 1).isVisuallySimilar(to: axis.rightColor))
        #expect(axis.trackColor(at: 0.5).isVisuallySimilar(to: FiltrationAxis.neutralTrack))
    }

    @Test func normalizedValueMapsRangeEndpoints() {
        let axis = FiltrationAxis.magenta
        #expect(axis.normalizedValue(-1, in: range) == 0)
        #expect(axis.normalizedValue(0, in: range) == 0.5)
        #expect(axis.normalizedValue(1, in: range) == 1)
    }

    @Test func disabledKnobUsesFlatGray() {
        let axis = FiltrationAxis.yellow
        let color = axis.knobColor(value: 0.4, in: range, enabled: false)
        #expect(color.isVisuallySimilar(to: FiltrationAxis.disabledKnob))
    }
}

private extension NSColor {
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
