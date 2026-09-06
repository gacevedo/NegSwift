import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of NegPy `tests/test_lab_colorspace.py`.
struct WorkingLabTests {
    @Test func roundTripIdentity() {
        var pixels = [Float](repeating: 0, count: 48 * 48 * 3)
        var seed: UInt64 = 1
        for i in 0..<pixels.count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            pixels[i] = Float(seed % 10_000) / 10_000
        }
        let img = LinearRGBBuffer(width: 48, height: 48, pixels: pixels)
        let back = WorkingLab.labToRgb(WorkingLab.rgbToLab(img))
        var maxAbs: Float = 0
        for i in pixels.indices {
            maxAbs = max(maxAbs, abs(back.pixels[i] - pixels[i]))
        }
        #expect(maxAbs < 1e-4)
    }

    @Test func neutralHasZeroChroma() {
        var pixels = [Float](repeating: 0, count: 12 * 3)
        for i in 0..<12 {
            let v = 0.05 + Float(i) * (0.90 / 11)
            pixels[i * 3] = v
            pixels[i * 3 + 1] = v
            pixels[i * 3 + 2] = v
        }
        let lab = WorkingLab.rgbToLab(LinearRGBBuffer(width: 12, height: 1, pixels: pixels))
        for i in 0..<12 {
            #expect(abs(lab.pixels[i * 3 + 1]) < 1e-3)
            #expect(abs(lab.pixels[i * 3 + 2]) < 1e-3)
        }
    }

    @Test func labScaleMatchesOpenCVConvention() {
        let black = WorkingLab.rgbToLab(rgb(0, 0, 0))
        let white = WorkingLab.rgbToLab(rgb(1, 1, 1))
        #expect(abs(black.pixels[0] - 0) < 1e-3)
        #expect(abs(white.pixels[0] - 100) < 1e-2)
    }

    @Test func adobeGreenDiffersFromNaiveSRGB() {
        let lab = WorkingLab.rgbToLab(rgb(0.1, 0.8, 0.2))
        // Working-space a* is strongly negative (Adobe green). A >5 delta vs the
        // old cv2 sRGB path is the characterization in test_lab_colorspace.py.
        #expect(lab.pixels[1] < -20)
    }

    @Test func primariesMatchVendorNegPy() {
        let red = WorkingLab.rgbToLab(rgb(1, 0, 0))
        #expect(abs(red.pixels[0] - 61.42723) < 1e-3)
        #expect(abs(red.pixels[1] - 89.56194) < 1e-3)
        #expect(abs(red.pixels[2] - 75.14870) < 1e-3)
        let green = WorkingLab.rgbToLab(rgb(0, 1, 0))
        #expect(abs(green.pixels[0] - 83.30270) < 1e-3)
        #expect(abs(green.pixels[1] + 137.9737) < 1e-2)
        let skin = WorkingLab.rgbToLab(rgb(0.53, 0.27, 0.16))
        #expect(abs(skin.pixels[0] - 64.88613) < 1e-3)
        #expect(abs(skin.pixels[1] - 21.58437) < 1e-3)
        #expect(abs(skin.pixels[2] - 27.30772) < 1e-3)
    }

    @Test func matrixMatchesManualXYZ() {
        let r: Float = 0.5
        let g: Float = 0.3
        let b: Float = 0.7
        let m = WorkingLab.workingToXYZ
        let y = m.3 * r + m.4 * g + m.5 * b
        #expect(y > 0 && y < 1)
    }

    private func rgb(_ r: Float, _ g: Float, _ b: Float) -> LinearRGBBuffer {
        LinearRGBBuffer(width: 1, height: 1, pixels: [r, g, b])
    }
}
