//
//  FrameEditStateTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct FrameEditStateTests {
    @Test func fromFlatConfigMapsNegPyKeys() {
        let state = FrameEditState.fromFlatConfig([
            "process_mode": "B&W",
            "density": 1.2,
            "grade": 120.0,
            "wb_magenta": 0.05,
            "auto_exposure": false,
            "manual_crop_rect": [0.1, 0.15, 0.9, 0.85],
        ])
        #expect(state.processMode == .bw)
        #expect(state.density == 1.2)
        #expect(state.grade == 120.0)
        #expect(state.wbMagenta == 0.05)
        #expect(state.autoExposure == false)
        #expect(state.manualCropRect?.x2 == 0.9)
    }

    @Test func jsonRoundTripUsesFlatKeys() throws {
        let original = FrameEditState(
            processMode: .c41,
            density: 1.25,
            grade: 110.0,
            wbCyan: 0.1,
            autoExposure: false,
            rotation: 1,
            fineRotation: -3.0,
            autocropRatio: "4:3",
            manualCropRect: NormalizedRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)
        )
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["process_mode"] as? String == "C41")
        #expect(object?["wb_cyan"] as? Double == 0.1)
        #expect(object?["auto_exposure"] as? Bool == false)
        #expect(object?["manual_crop_rect"] as? [Double] == [0.1, 0.1, 0.9, 0.9])

        let decoded = try JSONDecoder().decode(FrameEditState.self, from: data)
        #expect(decoded == original)
    }
}
