//
//  CanvasZoomScrollTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

@Suite struct CanvasZoomScrollTests {
    @Test func mouseWheelScrollDownZoomsIn() {
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: -1, precise: false)
        #expect(factor > 1)
    }

    @Test func mouseWheelScrollUpZoomsOut() {
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: 1, precise: false)
        #expect(factor < 1)
    }

    @Test func trackpadScrollDownZoomsIn() {
        let normalized = CanvasZoomScroll.normalizedScrollingDeltaY(-12, invertedFromDevice: false)
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: normalized, precise: true)
        #expect(factor > 1)
    }

    @Test func trackpadScrollUpZoomsOut() {
        let normalized = CanvasZoomScroll.normalizedScrollingDeltaY(12, invertedFromDevice: false)
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: normalized, precise: true)
        #expect(factor < 1)
    }

    @Test func magicMouseNaturalScrollDownZoomsIn() {
        let normalized = CanvasZoomScroll.normalizedScrollingDeltaY(12, invertedFromDevice: true)
        #expect(normalized < 0)
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: normalized, precise: true)
        #expect(factor > 1)
    }

    @Test func magicMouseNaturalScrollUpZoomsOut() {
        let normalized = CanvasZoomScroll.normalizedScrollingDeltaY(-12, invertedFromDevice: true)
        #expect(normalized > 0)
        let factor = CanvasZoomScroll.factor(fromScrollingDeltaY: normalized, precise: true)
        #expect(factor < 1)
    }
}
