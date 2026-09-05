import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of NegPy `tests/test_auto_exposure_contrast.py` (anchor + grade-range).
struct ExposureMeteringTests {
    private let bounds = LogNegativeBounds(
        floors: (-2, -2, -2),
        ceils: (0, 0, 0)
    )

    @Test func anchorTracksMidtonePartial() {
        let assumed = ExposureConstants.assumedAnchor
        let strength = ExposureConstants.anchorMeterStrength
        func expected(_ norm: Double) -> Double {
            assumed + strength * (norm - assumed)
        }
        #expect(abs(measureAnchor(-1.2) - expected(0.4)) < 1e-4)
        #expect(abs(measureAnchor(-0.9) - expected(0.55)) < 1e-4)
        #expect(abs(measureAnchor(-1.2) - measureAnchor(-0.9)) > 1e-3)
    }

    @Test func anchorUsesTrimmedMeanAndMidpoint() {
        let assumed = ExposureConstants.assumedAnchor
        let strength = ExposureConstants.anchorMeterStrength
        var pixels = [Float](repeating: 0, count: 64 * 64 * 3)
        let cols: [Float] = [-1.6, -0.4, -1.6, -1.0]
        for y in 0..<64 {
            for x in 0..<64 {
                let v = cols[x % 4]
                let o = (y * 64 + x) * 3
                pixels[o] = v
                pixels[o + 1] = v
                pixels[o + 2] = v
            }
        }
        let img = LinearRGBBuffer(width: 64, height: 64, pixels: pixels)
        let got = ExposureMetering.measureAnchorFromLog(img, bounds: bounds)
        #expect(abs(got - (assumed + strength * (0.4625 - assumed))) < 1e-4)
    }

    @Test func anchorClampedToBand() {
        let assumed = ExposureConstants.assumedAnchor
        let band = ExposureConstants.anchorMeterBand
        let hi = measureAnchor(-0.02)
        let lo = measureAnchor(-1.98)
        #expect(hi > assumed)
        #expect(lo < assumed)
        #expect(hi <= assumed + band + 1e-6)
        #expect(lo >= assumed - band - 1e-6)
    }

    @Test func effectiveRangeOffReturnsFloorCeil() {
        #expect(PrintCurve.effectiveGradeRange(autoNormalizeContrast: false, floorCeilRange: 1.7, texturalRange: 0.9) == 1.7)
        #expect(PrintCurve.effectiveGradeRange(autoNormalizeContrast: false, floorCeilRange: nil, texturalRange: 0.9) == nil)
    }

    @Test func effectiveRangeBlendsTowardNorm() {
        let k = ExposureConstants.autoGradeTarget
        let nominal = ExposureConstants.autoGradeNominalRange
        let s = ExposureConstants.autoGradeStrength
        let expected = k * 1.6 * ((1 - s) + s * nominal / 1.2)
        let got = PrintCurve.effectiveGradeRange(
            autoNormalizeContrast: true,
            floorCeilRange: 1.6,
            texturalRange: 1.2
        )
        #expect(abs((got ?? -1) - expected) < 1e-6)
    }

    @Test func effectiveRangeNormalNegativeIsTargetTimesRange() {
        let got = PrintCurve.effectiveGradeRange(
            autoNormalizeContrast: true,
            floorCeilRange: 1.8,
            texturalRange: ExposureConstants.autoGradeNominalRange
        )
        #expect(abs((got ?? -1) - ExposureConstants.autoGradeTarget * 1.8) < 1e-6)
    }

    @Test func texturalRangeUniformIsZero() {
        let img = LinearRGBBuffer(width: 16, height: 16, pixels: [Float](repeating: -1, count: 16 * 16 * 3))
        #expect(abs(ExposureMetering.measureTexturalRangeFromLog(img)) < 1e-5)
    }

    @Test func texturalRangeTracksSpread() {
        var pixels = [Float](repeating: 0, count: 64 * 64 * 3)
        for y in 0..<64 {
            for x in 0..<64 {
                let v: Float = x < 32 ? -1.5 : -0.5
                let o = (y * 64 + x) * 3
                pixels[o] = v
                pixels[o + 1] = v
                pixels[o + 2] = v
            }
        }
        let img = LinearRGBBuffer(width: 64, height: 64, pixels: pixels)
        #expect(abs(ExposureMetering.measureTexturalRangeFromLog(img) - 1.0) < 0.02)
    }

    @Test func s4aPinLeavesAutosOff() {
        #expect(PrintConfig.s4aPin.autoExposure == false)
        #expect(PrintConfig.s4aPin.autoNormalizeContrast == false)
    }

    @Test func s5PinTurnsAutosOn() {
        #expect(PrintConfig.s5Pin.autoExposure == true)
        #expect(PrintConfig.s5Pin.autoNormalizeContrast == true)
        #expect(PrintConfig.s5Pin.autoDensityUsesCrop == true)
    }

    @Test func autoExposureShiftsPrintVsPin() throws {
        let url = try writeMeteredTIFF()
        defer { try? FileManager.default.removeItem(at: url) }
        let linear = try LinearDecode.decode(url: url)
        let pin = PhotometricPrint.process(linear: linear, processMode: .colorNegative, config: .s4aPin)
        var auto = PrintConfig.s4aPin
        auto.autoExposure = true
        let metered = PhotometricPrint.process(linear: linear, processMode: .colorNegative, config: auto)
        #expect(pin.pixels != metered.pixels)
    }

    private func measureAnchor(_ logVal: Float) -> Double {
        let img = LinearRGBBuffer(width: 16, height: 16, pixels: [Float](repeating: logVal, count: 16 * 16 * 3))
        return ExposureMetering.measureAnchorFromLog(img, bounds: bounds)
    }

    private func writeMeteredTIFF() throws -> URL {
        let width = 48
        let height = 32
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 3
                let thin = x > width / 3
                samples[o] = thin ? 42_000 : 8_000
                samples[o + 1] = thin ? 28_000 : 5_000
                samples[o + 2] = thin ? 12_000 : 3_000
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-meter-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
        return url
    }
}
