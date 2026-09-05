import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of `Engine/tests/test_metering.py`.
struct MeteringRemapTests {
    @Test func cropMeteringUsesInsetAnalysisRect() {
        let out = MeteringRemap.flatForPipeline([
            "manual_crop_rect": [0.0, 0.0, 1.0, 1.0],
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.1,
        ])
        #expect(out["auto_density_uses_crop"] == nil)
        let rect = MeteringRemap.asRect(out["analysis_rect"])
        #expect(rect?.isApproximatelyEqual(to: NormalizedCropRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)) == true)
    }

    @Test func cropMeteringOffSetsFullFrameAnalysisRect() {
        let out = MeteringRemap.flatForPipeline([
            "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
            "auto_density_uses_crop": false,
        ])
        #expect(MeteringRemap.isFullFrameAnalysisRect(out["analysis_rect"]))
        #expect(out["crop_from_auto"] as? Bool == false)
        let crop = MeteringRemap.asRect(out["manual_crop_rect"])
        #expect(crop?.isApproximatelyEqual(to: NormalizedCropRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)) == true)
    }

    @Test func saveDoesNotPersistWireAnalysisRect() {
        let out = MeteringRemap.flatForSave([
            "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
            "auto_density_uses_crop": true,
            "analysis_rect": [0.2, 0.2, 0.8, 0.8],
        ])
        #expect(out["auto_density_uses_crop"] == nil)
        #expect(out["analysis_rect"] == nil)
    }

    @Test func pipelineStripsStaleSidecarAnalysisRectWithoutCrop() {
        let out = MeteringRemap.flatForPipeline([
            "auto_crop_enabled": true,
            "analysis_rect": [0.2, 0.2, 0.8, 0.8],
            "local_floors": [0.1, 0.2, 0.3],
        ])
        #expect(out["crop_from_auto"] as? Bool == true)
        #expect(out["analysis_rect"] == nil)
        #expect(out["local_floors"] as? [Double] == [0, 0, 0])
    }

    @Test func armedAutoCropMapsAutoCropEnabledToCropFromAuto() {
        let out = MeteringRemap.flatForPipeline(["auto_crop_enabled": true])
        #expect(out["crop_from_auto"] as? Bool == true)
        #expect(out["auto_crop_enabled"] == nil)
        #expect(out["analysis_rect"] == nil)
    }

    @Test func sidecarExtrasKeepsOnlyKnownKeys() {
        let extras = MeteringRemap.sidecarExtras([
            "auto_density_uses_crop": false,
            "density": 1.2,
            "analysis_buffer": 0.1,
        ])
        #expect(extras["auto_density_uses_crop"] as? Bool == false)
        #expect(extras.count == 1)
    }

    @Test func defaultAutoDensityUsesCrop() {
        #expect(MeteringRemap.defaultAutoDensityUsesCrop([:]) == true)
        #expect(MeteringRemap.defaultAutoDensityUsesCrop(["auto_density_uses_crop": false]) == false)
    }

    @Test func cropMeteringKeepsCropFromAutoWhenFrozen() {
        let out = MeteringRemap.flatForPipeline([
            "crop_rect": [0.1, 0.1, 0.9, 0.9],
            "crop_from_auto": true,
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.1,
        ])
        #expect(out["crop_from_auto"] as? Bool == true)
        let crop = MeteringRemap.asRect(out["crop_rect"])
        #expect(crop?.isApproximatelyEqual(to: NormalizedCropRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)) == true)
        #expect(out["analysis_rect"] == nil)
    }

    @Test func pipelineClearsStoredLocalBounds() {
        let out = MeteringRemap.flatForPipeline([
            "local_floors": [0.1, 0.2, 0.3],
            "local_ceils": [0.9, 0.8, 0.7],
        ])
        #expect(out["local_floors"] as? [Double] == [0, 0, 0])
        #expect(out["local_ceils"] as? [Double] == [0, 0, 0])
    }

    @Test func saveClearsLocalBounds() {
        let out = MeteringRemap.flatForSave([
            "local_floors": [0.1, 0.2, 0.3],
            "local_ceils": [0.9, 0.8, 0.7],
            "density": 1.1,
        ])
        #expect(out["local_floors"] as? [Double] == [0, 0, 0])
        #expect(out["local_ceils"] as? [Double] == [0, 0, 0])
        #expect(out["density"] as? Double == 1.1)
    }

    @Test func cropMeteringUsesAnalysisRectForManualCrop() {
        let out = MeteringRemap.flatForPipeline([
            "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
            "crop_from_auto": false,
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.1,
        ])
        #expect(out["crop_from_auto"] as? Bool == false)
        let rect = MeteringRemap.asRect(out["analysis_rect"])
        #expect(rect?.isApproximatelyEqual(to: NormalizedCropRect(x1: 0.18, y1: 0.18, x2: 0.82, y2: 0.82)) == true)
    }

    @Test func printConfigMergesAnalysisRectOverride() {
        let merged = PrintConfig.s5Pin.merging([
            "analysis_rect": [0.18, 0.18, 0.82, 0.82],
        ])
        #expect(merged.autoExposure)
        #expect(merged.autoNormalizeContrast)
        #expect(merged.analysisRect?.isApproximatelyEqual(
            to: NormalizedCropRect(x1: 0.18, y1: 0.18, x2: 0.82, y2: 0.82)
        ) == true)
        #expect(merged.resolvedAnalysisRegion().buffer == 0)
    }

    @Test func printConfigRemapsManualCropToAnalysisRect() {
        let merged = PrintConfig.s5Pin.merging([
            "manual_crop_rect": [0.1, 0.1, 0.9, 0.9],
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.1,
        ])
        #expect(merged.analysisRect?.isApproximatelyEqual(
            to: NormalizedCropRect(x1: 0.18, y1: 0.18, x2: 0.82, y2: 0.82)
        ) == true)
    }

    @Test func analysisBufferWidensCropInset() {
        let tight = PrintConfig.s5Pin.merging([
            "manual_crop_rect": [0.0, 0.0, 1.0, 1.0],
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.05,
        ])
        let loose = PrintConfig.s5Pin.merging([
            "manual_crop_rect": [0.0, 0.0, 1.0, 1.0],
            "auto_density_uses_crop": true,
            "analysis_buffer": 0.2,
        ])
        #expect(tight.analysisRect?.isApproximatelyEqual(
            to: NormalizedCropRect(x1: 0.05, y1: 0.05, x2: 0.95, y2: 0.95)
        ) == true)
        #expect(loose.analysisRect?.isApproximatelyEqual(
            to: NormalizedCropRect(x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8)
        ) == true)
    }
}
