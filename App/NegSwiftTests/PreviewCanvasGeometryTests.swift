//
//  PreviewCanvasGeometryTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

@Suite struct PreviewCanvasGeometryTests {
    @Test func centeredOffsetWhenNoClickProvided() {
        let offset = PreviewCanvasGeometry.oneToOneContentOffset(
            clickInViewport: nil,
            viewportSize: CGSize(width: 400, height: 300),
            pixelSize: CGSize(width: 800, height: 600)
        )
        #expect(offset.x == -200)
        #expect(offset.y == -150)
    }

    @Test func clickAnchorKeepsViewportPointFixed() {
        let viewport = CGSize(width: 400, height: 400)
        let pixelSize = CGSize(width: 800, height: 800)
        let imageRect = PreviewCanvasGeometry.aspectFitRect(imageSize: pixelSize, in: viewport)
        let click = CGPoint(x: imageRect.midX, y: imageRect.midY)

        let offset = PreviewCanvasGeometry.oneToOneContentOffset(
            clickInViewport: click,
            viewportSize: viewport,
            pixelSize: pixelSize
        )

        #expect(abs((click.x - offset.x) - pixelSize.width / 2) < 0.001)
        #expect(abs((click.y - offset.y) - pixelSize.height / 2) < 0.001)
    }

    @Test func zoomAnchorKeepsViewportPointFixed() {
        let viewport = CGSize(width: 400, height: 400)
        let oldContent = CGSize(width: 800, height: 800)
        let newContent = CGSize(width: 1200, height: 1200)
        let anchor = CGPoint(x: 200, y: 200)
        let currentOffset = CGPoint(x: -100, y: -100)

        let offset = PreviewCanvasGeometry.zoomAnchorContentOffset(
            currentContentOffset: currentOffset,
            viewportSize: viewport,
            oldContentSize: oldContent,
            newContentSize: newContent,
            anchorInViewport: anchor
        )

        let oldPoint = PreviewCanvasGeometry.contentPointUnderAnchor(
            anchorInViewport: anchor,
            contentOffset: currentOffset,
            contentSize: oldContent
        )
        let newPoint = PreviewCanvasGeometry.contentPointUnderAnchor(
            anchorInViewport: anchor,
            contentOffset: offset,
            contentSize: newContent
        )
        #expect(abs((oldPoint.x / oldContent.width) - (newPoint.x / newContent.width)) < 0.001)
    }

    @Test func contentPointTracksContentOffset() {
        let contentSize = CGSize(width: 800, height: 600)
        let point = PreviewCanvasGeometry.contentPointUnderAnchor(
            anchorInViewport: CGPoint(x: 50, y: 50),
            contentOffset: CGPoint(x: -100, y: -80),
            contentSize: contentSize
        )
        #expect(point == CGPoint(x: 150, y: 130))
    }

    @Test func visibleContentRectMatchesClippedViewportWhenPanned() {
        let contentSize = CGSize(width: 3200, height: 2400)
        let viewport = CGSize(width: 800, height: 600)
        let contentOffset = CGPoint(x: -400, y: -300)

        let visible = PreviewCanvasGeometry.visibleContentRect(
            contentSize: contentSize,
            contentOffset: contentOffset,
            viewportSize: viewport
        )

        #expect(visible.origin == CGPoint(x: 400, y: 300))
        #expect(visible.size == viewport)
    }

    @Test func visibleContentRectMatchesCenteredFitContent() {
        let contentSize = CGSize(width: 400, height: 300)
        let viewport = CGSize(width: 800, height: 600)
        let contentOffset = CGPoint(x: 200, y: 150)

        let visible = PreviewCanvasGeometry.visibleContentRect(
            contentSize: contentSize,
            contentOffset: contentOffset,
            viewportSize: viewport
        )

        #expect(visible == CGRect(origin: .zero, size: contentSize))
    }
}
