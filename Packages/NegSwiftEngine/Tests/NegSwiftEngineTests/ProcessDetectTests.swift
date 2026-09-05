import Foundation
import Testing
@testable import NegSwiftEngine

struct ProcessDetectTests {
    @Test func detectsBW() {
        #expect(ProcessDetect.detect(bwScan()) == .bwNegative)
    }

    @Test func detectsTintedBW() {
        #expect(ProcessDetect.detect(tintedBWScan()) == .bwNegative)
    }

    @Test func detectsC41() {
        #expect(ProcessDetect.detect(c41Scan()) == .colorNegative)
    }

    @Test func detectsPhoenixC41() {
        #expect(ProcessDetect.detect(phoenixScan()) == .colorNegative)
    }

    @Test func detectsE6() {
        #expect(ProcessDetect.detect(e6Scan()) == .transparency)
    }

    @Test func liteMapsE6ToColorNegative() {
        #expect(ProcessDetect.detectLite(e6Scan()) == .colorNegative)
    }

    @Test func invalidFallsBackToC41() {
        #expect(ProcessDetect.detect(nil) == .colorNegative)
    }

    @Test func detectUsesHardcodedCenterCropNotBorder() {
        #expect(ProcessDetect.detect(orangeBorderGrayCenter()) == .bwNegative)
        #expect(ProcessDetect.detect(grayBorderOrangeCenter()) == .colorNegative)
    }

    @Test func detectFromOrangeMaskTIFF() throws {
        var samples = [UInt16](repeating: 0, count: 32 * 32 * 3)
        for i in 0..<(32 * 32) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-c41-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: 32, height: 32, samples: samples, to: url)
        let buffer = try LinearDecode.decode(url: url)
        #expect(abs(buffer.pixels[0] - Float(40000) / 65535) < 0.01)
        #expect(abs(buffer.pixels[2] - Float(10000) / 65535) < 0.01)
        #expect(ProcessDetect.detect(buffer) == .colorNegative)
        #expect(try NativePipeline().detectProcessMode(path: url.path) == .colorNegative)
    }

    @Test func detectFromLargeOrangeMaskUsesAnalysisDecode() throws {
        let width = 400
        let height = 300
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-c41-large-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
        #expect(try NativePipeline().detectProcessMode(path: url.path) == .colorNegative)
    }

    private func bwScan() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 128 * 128 * 3)
        for i in 0..<(128 * 128) {
            let g = 0.1 + 0.8 * Float(i) / Float(128 * 128 - 1)
            pixels[i * 3] = g
            pixels[i * 3 + 1] = g
            pixels[i * 3 + 2] = g
        }
        return LinearRGBBuffer(width: 128, height: 128, pixels: pixels)
    }

    private func tintedBWScan() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 128 * 128 * 3)
        for i in 0..<(128 * 128) {
            let g = 0.1 + 0.8 * Float(i) / Float(128 * 128 - 1)
            pixels[i * 3] = g * 0.8
            pixels[i * 3 + 1] = g * 0.95
            pixels[i * 3 + 2] = g
        }
        return LinearRGBBuffer(width: 128, height: 128, pixels: pixels)
    }

    private func c41Scan() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 128 * 128 * 3)
        var rng = SplitMix64(seed: 0)
        for i in 0..<(128 * 128) {
            pixels[i * 3] = clamp(0.6 + rng.uniform(-0.15, 0.15))
            pixels[i * 3 + 1] = clamp(0.4 + rng.uniform(-0.15, 0.15))
            pixels[i * 3 + 2] = clamp(0.2 + rng.uniform(-0.15, 0.15))
        }
        return LinearRGBBuffer(width: 128, height: 128, pixels: pixels)
    }

    private func phoenixScan() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 128 * 128 * 3)
        var rng = SplitMix64(seed: 2)
        for i in 0..<(128 * 128) {
            pixels[i * 3] = clamp(0.50 + rng.uniform(-0.10, 0.10))
            pixels[i * 3 + 1] = clamp(0.30 + rng.uniform(-0.10, 0.10))
            pixels[i * 3 + 2] = clamp(0.48 + rng.uniform(-0.10, 0.10))
        }
        return LinearRGBBuffer(width: 128, height: 128, pixels: pixels)
    }

    private func e6Scan() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 128 * 128 * 3)
        var rng = SplitMix64(seed: 1)
        for i in 0..<(128 * 128 * 3) {
            pixels[i] = rng.uniform(0, 1)
        }
        return LinearRGBBuffer(width: 128, height: 128, pixels: pixels)
    }

    private func clamp(_ x: Float) -> Float { min(1, max(0, x)) }

    /// Orange only in the 0.12 inset that detect must drop — remaining centre is B&W.
    private func orangeBorderGrayCenter() -> LinearRGBBuffer {
        framedScan(borderOrange: true)
    }

    /// Orange only inside the 0.12 analysis crop — detect must still see C-41.
    private func grayBorderOrangeCenter() -> LinearRGBBuffer {
        framedScan(borderOrange: false)
    }

    private func framedScan(borderOrange: Bool) -> LinearRGBBuffer {
        let n = 128
        let cut = Int(Float(n) * ProcessDetect.analysisBuffer)
        var pixels = [Float](repeating: 0, count: n * n * 3)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 3
                let inBorder = y < cut || y >= n - cut || x < cut || x >= n - cut
                let orange = borderOrange ? inBorder : !inBorder
                if orange {
                    pixels[i] = 0.75
                    pixels[i + 1] = 0.40
                    pixels[i + 2] = 0.20
                } else {
                    let g = 0.1 + 0.8 * Float(y * n + x) / Float(n * n - 1)
                    pixels[i] = g
                    pixels[i + 1] = g
                    pixels[i + 2] = g
                }
            }
        }
        return LinearRGBBuffer(width: n, height: n, pixels: pixels)
    }
}

/// Deterministic RNG so detect goldens stay stable (not numpy's Generator).
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform(_ lo: Float, _ hi: Float) -> Float {
        let u = Float(next() >> 40) / Float(1 << 24)
        return lo + (hi - lo) * u
    }
}
