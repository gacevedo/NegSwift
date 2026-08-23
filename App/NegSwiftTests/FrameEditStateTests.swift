//
//  FrameEditStateTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct FrameEditStateTests {
    @Test func fromFlatConfigMapsZoneToneKeys() {
        let state = FrameEditState.fromFlatConfig([
            "shadow_density": -0.25,
            "highlight_density": 0.15,
            "shadow_grade": -12.0,
            "highlight_grade": 8.0,
        ])
        #expect(state.shadowDensity == -0.25)
        #expect(state.highlightDensity == 0.15)
        #expect(state.shadowGrade == -12.0)
        #expect(state.highlightGrade == 8.0)
    }

    @Test func fromFlatConfigMapsNegPyKeys() {
        let state = FrameEditState.fromFlatConfig([
            "process_mode": "B&W Negative",
            "density": 1.2,
            "grade": 120.0,
            "wb_magenta": 0.05,
            "auto_exposure": false,
            "analysis_buffer": 0.12,
            "auto_density_uses_crop": false,
            "auto_crop_enabled": false,
            "dust_remove": true,
            "dust_threshold": 0.5,
            "dust_size": 6,
            "manual_crop_rect": [0.1, 0.15, 0.9, 0.85],
            "flip_horizontal": true,
            "flip_vertical": true,
        ])
        #expect(state.processMode == .bw)
        #expect(state.density == 1.2)
        #expect(state.grade == 120.0)
        #expect(state.wbMagenta == 0.05)
        #expect(state.autoExposure == false)
        #expect(state.analysisBuffer == 0.12)
        #expect(state.autoDensityUsesCrop == false)
        #expect(state.autoCropEnabled == false)
        #expect(state.dustRemove == true)
        #expect(state.dustThreshold == 0.5)
        #expect(state.dustSize == 6)
        #expect(state.manualCropRect?.x2 == 0.9)
        #expect(state.flipHorizontal == true)
        #expect(state.flipVertical == true)
    }

    @Test func fromFlatConfigMapsNegPyCropKeys() {
        let armed = FrameEditState.fromFlatConfig([
            "crop_from_auto": true,
        ])
        #expect(armed.autoCropEnabled == true)
        #expect(armed.manualCropRect == nil)

        let resolved = FrameEditState.fromFlatConfig([
            "crop_from_auto": true,
            "crop_rect": [0.1, 0.15, 0.9, 0.85],
        ])
        #expect(resolved.autoCropEnabled == false)
        #expect(resolved.manualCropRect?.x1 == 0.1)
    }

    @Test func fromFlatConfigAcceptsLegacyProcessModeKeys() {
        #expect(FrameEditState.fromFlatConfig(["process_mode": "C41"]).processMode == .c41)
        #expect(FrameEditState.fromFlatConfig(["process_mode": "B&W"]).processMode == .bw)
    }

    @Test func fromFlatConfigMapsHealFields() {
        let stroke: [Any] = [[[0.2, 0.3], [0.7, 0.8]], 6.0, 0.0, 0.0]
        let state = FrameEditState.fromFlatConfig([
            "manual_heal_strokes": [stroke],
            "manual_dust_size": 8,
        ])
        #expect(state.manualHealStrokes.count == 1)
        #expect(state.manualHealStrokes[0].points.count == 2)
        #expect(state.manualHealStrokes[0].size == 6)
        #expect(state.manualDustSize == 8)
    }

    @Test func jsonRoundTripUsesFlatKeys() throws {
        let original = FrameEditState(
            processMode: .c41,
            density: 1.25,
            grade: 110.0,
            wbCyan: 0.1,
            autoExposure: false,
            analysisBuffer: 0.15,
            autoDensityUsesCrop: false,
            autoCropEnabled: false,
            dustRemove: true,
            dustThreshold: 0.55,
            dustSize: 5,
            rotation: 1,
            fineRotation: -3.0,
            flipHorizontal: true,
            flipVertical: false,
            autocropRatio: "4:3",
            manualCropRect: NormalizedRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)
        )
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["process_mode"] as? String == "Color Negative")
        #expect(object?["wb_cyan"] as? Double == 0.1)
        #expect(object?["auto_exposure"] as? Bool == false)
        #expect(object?["analysis_buffer"] as? Double == 0.15)
        #expect(object?["auto_density_uses_crop"] as? Bool == false)
        #expect(object?["auto_crop_enabled"] as? Bool == false)
        #expect(object?["dust_remove"] as? Bool == true)
        #expect(object?["dust_threshold"] as? Double == 0.55)
        #expect(object?["dust_size"] as? Int == 5)
        #expect(object?["flip_horizontal"] as? Bool == true)
        #expect(object?["flip_vertical"] as? Bool == false)
        #expect(object?["manual_crop_rect"] as? [Double] == [0.1, 0.1, 0.9, 0.9])

        let decoded = try JSONDecoder().decode(FrameEditState.self, from: data)
        #expect(decoded == original)
    }

    @Test func jsonRoundTripZoneToneKeys() throws {
        let original = FrameEditState(
            shadowDensity: -0.3,
            highlightDensity: 0.2,
            shadowGrade: -15.0,
            highlightGrade: 10.0
        )
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["shadow_density"] as? Double == -0.3)
        #expect(object?["highlight_density"] as? Double == 0.2)
        #expect(object?["shadow_grade"] as? Double == -15.0)
        #expect(object?["highlight_grade"] as? Double == 10.0)

        let decoded = try JSONDecoder().decode(FrameEditState.self, from: data)
        #expect(decoded == original)
    }

    @Test func encodeOmitsNeutralZoneToneDefaults() throws {
        let data = try JSONEncoder().encode(FrameEditState())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["shadow_density"] == nil)
        #expect(object?["highlight_density"] == nil)
        #expect(object?["shadow_grade"] == nil)
        #expect(object?["highlight_grade"] == nil)
    }
}
