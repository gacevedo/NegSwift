//
//  ExportSettingsTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct ExportSettingsTests {
    @Test func instagramDefaultsMatchSupportedRatios() {
        #expect(InstagramExportSizing.defaultLongEdge(for: .r1x1) == 1080)
        #expect(InstagramExportSizing.defaultLongEdge(for: .r4x5) == 1350)
        #expect(InstagramExportSizing.defaultLongEdge(for: .r3x2) == 1620)
        #expect(InstagramExportSizing.defaultLongEdge(for: .r16x9) == 1920)
        #expect(InstagramExportSizing.defaultLongEdge(for: .r5x4) == 1080)
    }

    @Test func instagramDefaultUsesCropRatioFromEdit() {
        var edit = FrameEditState()
        edit.autocropRatio = "4:5"
        #expect(InstagramExportSizing.defaultLongEdge(for: edit) == 1350)
    }

    @Test func instagramDefaultUsesFreeCropAspectWhenClose() {
        var edit = FrameEditState()
        edit.autocropRatio = "Free"
        edit.manualCropRect = NormalizedRect(x1: 0, y1: 0, x2: 0.8, y2: 1)
        #expect(InstagramExportSizing.defaultLongEdge(for: edit) == 1350)
    }

    @Test func instagramDefaultUsesNearestRatioForPanorama() {
        var edit = FrameEditState()
        edit.autocropRatio = "Free"
        edit.manualCropRect = NormalizedRect(x1: 0, y1: 0, x2: 1, y2: 24.0 / 65.0)
        #expect(InstagramExportSizing.defaultLongEdge(for: edit) == 1920)
    }

    @Test func instagramDefaultUsesSourceAspectWhenUncropped() {
        let edit = FrameEditState()
        let px = InstagramExportSizing.defaultLongEdge(
            for: edit,
            sourceSize: CGSize(width: 6500, height: 2400)
        )
        #expect(px == 1920)
    }

    @Test func quickExportUsesInstagramLongEdge() {
        var edit = FrameEditState()
        edit.autocropRatio = "16:9"
        let settings = ExportSettings.quickExport(for: edit)
        #expect(settings.resolutionMode == .targetLongEdge)
        #expect(settings.targetLongEdgePx == 1920)
    }

    @Test func flatExportDictIncludesTargetLongEdge() {
        var settings = ExportSettings()
        settings.resolutionMode = .targetLongEdge
        settings.targetLongEdgePx = 1620
        let dict = settings.flatExportDict()
        #expect(dict["export_resolution_mode"] as? String == "target_px")
        #expect(dict["export_target_long_edge_px"] as? Int == 1620)
    }
}
