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
}
