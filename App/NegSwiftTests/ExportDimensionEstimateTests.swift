//
//  ExportDimensionEstimateTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct ExportDimensionEstimateTests {
    @Test func fullSizeUsesSourceLongEdge() {
        let px = ExportDimensionEstimate.exportLongEdgePx(
            sourceSize: CGSize(width: 4000, height: 3000),
            edit: FrameEditState(),
            settings: ExportSettings(resolutionMode: .original)
        )
        #expect(px == 4000)
    }

    @Test func fullSizeAccountsForCrop() {
        var edit = FrameEditState()
        edit.manualCropRect = NormalizedRect(x1: 0, y1: 0, x2: 0.5, y2: 0.5)
        let px = ExportDimensionEstimate.exportLongEdgePx(
            sourceSize: CGSize(width: 4000, height: 3000),
            edit: edit,
            settings: ExportSettings(resolutionMode: .original)
        )
        #expect(px == 2000)
    }

    @Test func rotationSwapsOrientedDimensions() {
        var edit = FrameEditState()
        edit.rotation = 1
        let px = ExportDimensionEstimate.exportLongEdgePx(
            sourceSize: CGSize(width: 4000, height: 3000),
            edit: edit,
            settings: ExportSettings(resolutionMode: .original)
        )
        #expect(px == 4000)
    }

    @Test func targetLongEdgeDoesNotUpscale() {
        var settings = ExportSettings()
        settings.resolutionMode = .targetLongEdge
        settings.targetLongEdgePx = 4000
        let px = ExportDimensionEstimate.exportLongEdgePx(
            sourceSize: CGSize(width: 800, height: 600),
            edit: FrameEditState(),
            settings: settings
        )
        #expect(px == 800)
    }
}
