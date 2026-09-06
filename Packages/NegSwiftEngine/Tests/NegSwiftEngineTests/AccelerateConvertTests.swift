import Foundation
import Testing
@testable import NegSwiftEngine

/// S13e: vImage / vDSP convert and resize stay look-identical to the scalar oracles.
struct AccelerateConvertTests {
    @Test func srgbToLinearMatchesScalarRamp() {
        var encoded = [Float](repeating: 0, count: 17 * 3)
        for i in 0..<17 {
            let v = Float(i) / 16
            encoded[i * 3] = v
            encoded[i * 3 + 1] = v * 0.5
            encoded[i * 3 + 2] = min(1, v * 1.2)
        }
        let buffer = LinearRGBBuffer(width: 17, height: 1, pixels: encoded)
        let accelerated = AccelerateConvert.applySRGBToLinear(buffer)
        for i in encoded.indices {
            let expected = LinearDecode.srgbToLinear(encoded[i])
            #expect(abs(accelerated.pixels[i] - expected) < 1e-6)
        }
    }

    @Test func rgbRGBARoundTripPreservesRGB() {
        var rgb = [Float](repeating: 0, count: 8 * 4 * 3)
        for i in 0..<(8 * 4) {
            rgb[i * 3] = Float(i) / 31
            rgb[i * 3 + 1] = Float(i % 5) / 4
            rgb[i * 3 + 2] = 1 - Float(i) / 31
        }
        let rgba = AccelerateConvert.rgbToRGBA(rgb, width: 8, height: 4)
        #expect(rgba.count == 8 * 4 * 4)
        for i in 0..<(8 * 4) {
            #expect(abs(rgba[i * 4 + 3] - 1) < 1e-6)
        }
        let back = AccelerateConvert.rgbaToRGB(rgba, width: 8, height: 4)
        for i in rgb.indices {
            #expect(abs(back[i] - rgb[i]) < 1e-6)
        }
    }

    @Test func areaResizedMatchesScalarOracle() {
        var pixels = [Float](repeating: 0.2, count: 9 * 6 * 3)
        pixels[0] = 0
        pixels[1] = 0.4
        pixels[2] = 0.8
        pixels[(5 * 9 + 4) * 3] = 1
        pixels[(5 * 9 + 8) * 3 + 2] = 0.55
        let buffer = LinearRGBBuffer(width: 9, height: 6, pixels: pixels)
        let accelerated = buffer.areaResized(width: 4, height: 3)
        let scalar = buffer.areaResizedScalar(width: 4, height: 3)
        #expect(accelerated.width == 4)
        #expect(accelerated.height == 3)
        #expect(accelerated.meanAbsoluteError(against: scalar) < 1e-6)
    }

    @Test func areaDownsampledStillAveragesPinholes() {
        var pixels = [Float](repeating: 0.2, count: 4 * 4 * 3)
        pixels[0] = 0
        pixels[1] = 0
        pixels[2] = 0
        let buffer = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let nearest = buffer.downsampled(toLongEdge: 2)
        let area = buffer.areaDownsampled(toLongEdge: 2)
        #expect(nearest.pixels[0] == 0)
        #expect(area.pixels[0] > 0.1)
    }

    @Test func uint16ExtractStaysLinear() throws {
        let width = 6
        let height = 3
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = UInt16(clamping: i * 3000)
            samples[i * 3 + 1] = UInt16(clamping: i * 1500)
            samples[i * 3 + 2] = UInt16(clamping: i * 700)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13e-u16-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
        let buffer = try LinearDecode.decode(url: url)
        for i in 0..<(width * height) {
            #expect(abs(buffer.pixels[i * 3] - Float(samples[i * 3]) / 65535) < 1.5 / 65535)
            #expect(abs(buffer.pixels[i * 3 + 1] - Float(samples[i * 3 + 1]) / 65535) < 1.5 / 65535)
            #expect(abs(buffer.pixels[i * 3 + 2] - Float(samples[i * 3 + 2]) / 65535) < 1.5 / 65535)
        }
    }
}
