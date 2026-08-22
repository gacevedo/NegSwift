//
//  PreviewCanvasZoomTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

@Suite struct PreviewCanvasZoomTests {
    @Test func toggleSwitchesBetweenFitAndOneToOne() {
        let pixelSize = CGSize(width: 800, height: 600)
        let viewport = CGSize(width: 400, height: 300)
        var zoom = PreviewCanvasZoom.fit

        zoom.toggle(imageSize: pixelSize, viewport: viewport)
        #expect(zoom.isAtOneToOne(imageSize: pixelSize, viewport: viewport))

        zoom.toggle(imageSize: pixelSize, viewport: viewport)
        #expect(zoom.isAtFit())
    }

    @Test func clampsToMaximumDisplayScale() {
        let pixelSize = CGSize(width: 800, height: 600)
        let viewport = CGSize(width: 400, height: 300)
        let zoom = PreviewCanvasZoom(magnification: 999)

        let clamped = zoom.clampedMagnification(999, imageSize: pixelSize, viewport: viewport)
        let fit = PreviewCanvasGeometry.fitScale(imageSize: pixelSize, in: viewport)
        #expect(clamped == PreviewCanvasZoom.maxDisplayScale / fit)
    }
}
