//
//  PreviewCanvasGeometryTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

@Suite struct PreviewCanvasGeometryTests {
    @Test func centeredScrollWhenNoClickProvided() {
        let offset = PreviewCanvasGeometry.oneToOneScrollOffset(
            clickInViewport: nil,
            viewportSize: CGSize(width: 400, height: 300),
            pixelSize: CGSize(width: 800, height: 600)
        )
        #expect(offset.x == 200)
        #expect(offset.y == 150)
    }

    @Test func clickAnchorKeepsViewportPointFixed() {
        let viewport = CGSize(width: 400, height: 400)
        let pixelSize = CGSize(width: 800, height: 800)
        let imageRect = PreviewCanvasGeometry.aspectFitRect(imageSize: pixelSize, in: viewport)
        let click = CGPoint(x: imageRect.midX, y: imageRect.midY)

        let offset = PreviewCanvasGeometry.oneToOneScrollOffset(
            clickInViewport: click,
            viewportSize: viewport,
            pixelSize: pixelSize
        )

        #expect(abs((offset.x + click.x) - pixelSize.width / 2) < 0.001)
        #expect(abs((offset.y + click.y) - pixelSize.height / 2) < 0.001)
    }
}
