//
//  ScratchToolOverlayTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct ScratchToolOverlayTests {
    @Test func normalizedPointMapsLetterboxedImageRect() {
        let imageRect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let point = ScratchToolOverlayGeometry.normalizedPoint(CGPoint(x: 110, y: 70), imageRect: imageRect)
        #expect(point?.x == 0.5)
        #expect(point?.y == 0.5)
    }

    @Test func normalizedPointOutsideImageRectIsNil() {
        let imageRect = CGRect(x: 10, y: 20, width: 200, height: 100)
        #expect(ScratchToolOverlayGeometry.normalizedPoint(CGPoint(x: 5, y: 70), imageRect: imageRect) == nil)
    }

    @Test func normalizedPointInImageUsesLocalCoordinates() {
        let point = ScratchToolOverlayGeometry.normalizedPointInImage(
            CGPoint(x: 100, y: 50),
            imageSize: CGSize(width: 200, height: 100)
        )
        #expect(point?.x == 0.5)
        #expect(point?.y == 0.5)
    }

    @Test func dedupeRemovesPointsCloserThanScreenThreshold() {
        let imageRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let points = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.501, y: 0.5),
            CGPoint(x: 0.8, y: 0.2),
        ]
        let deduped = ScratchToolOverlayGeometry.dedupeNormalizedPoints(points, imageRect: imageRect, minScreenDistance: 2)
        #expect(deduped.count == 2)
        #expect(deduped[0].x == 0.5)
        #expect(deduped[1].x == 0.8)
    }

    @Test func dedupeKeepsDistinctPoints() {
        let imageRect = CGRect(x: 10, y: 20, width: 200, height: 100)
        let points = [
            CGPoint(x: 0.2, y: 0.3),
            CGPoint(x: 0.7, y: 0.8),
        ]
        let deduped = ScratchToolOverlayGeometry.dedupeNormalizedPoints(points, imageRect: imageRect)
        #expect(deduped == points)
    }

    @Test func brushScreenRadiusMatchesNegPyFormula() {
        let imageRect = CGRect(x: 0, y: 0, width: 160, height: 100)
        let radius = ScratchToolOverlayGeometry.brushScreenRadius(brushSize: 12, imageRect: imageRect)
        let expected = 12 / (2 * ScratchToolOverlayGeometry.healSizeRef) * 160
        #expect(abs(radius - expected) < 1e-6)
    }

    @Test func scratchBandWidthScalesWithBrushSize() {
        let imageRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let small = ScratchToolOverlayGeometry.scratchBandWidth(brushSize: 2, imageRect: imageRect)
        let large = ScratchToolOverlayGeometry.scratchBandWidth(brushSize: 16, imageRect: imageRect)
        #expect(large > small)
        #expect(small >= 1.5)
    }
}
