import Foundation
import Testing
@testable import NegSwiftEngine

struct LinearDecodeTests {
    @Test func uint16RampStaysLinear() throws {
        let width = 8
        let height = 4
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let v = UInt16(clamping: i * 2000)
            samples[i * 3] = v
            samples[i * 3 + 1] = v / 2
            samples[i * 3 + 2] = v / 4
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-u16-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)

        let buffer = try LinearDecode.decode(url: url)
        #expect(buffer.width == width)
        #expect(buffer.height == height)
        for i in 0..<(width * height) {
            let expectedR = Float(samples[i * 3]) / 65535
            let expectedG = Float(samples[i * 3 + 1]) / 65535
            let expectedB = Float(samples[i * 3 + 2]) / 65535
            #expect(abs(buffer.pixels[i * 3] - expectedR) < 1.5 / 65535)
            #expect(abs(buffer.pixels[i * 3 + 1] - expectedG) < 1.5 / 65535)
            #expect(abs(buffer.pixels[i * 3 + 2] - expectedB) < 1.5 / 65535)
        }
    }

    @Test func uint8UntaggedAppliesSRGBToLinear() throws {
        let samples = [UInt8](repeating: 128, count: 4 * 4 * 3)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-u8-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB8(width: 4, height: 4, samples: samples, to: url)

        let buffer = try LinearDecode.decode(url: url)
        let expected = LinearDecode.srgbToLinear(128.0 / 255.0)
        #expect(abs(buffer.pixels[0] - expected) < 0.002)
        #expect(abs(buffer.pixels[0] - 128.0 / 255.0) > 0.05)
    }

    @Test func thumbnail16BitStaysLinearNotSRGB() throws {
        let width = 64
        let height = 32
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-thumb-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)

        let buffer = try LinearDecode.decode(url: url, maxLongEdge: 16)
        #expect(max(buffer.width, buffer.height) <= 16)
        let linearR = Float(40_000) / 65535
        let linearB = Float(10_000) / 65535
        let crushedR = LinearDecode.srgbToLinear(linearR)
        #expect(abs(buffer.pixels[0] - linearR) < 0.03)
        #expect(abs(buffer.pixels[2] - linearB) < 0.03)
        #expect(abs(buffer.pixels[0] - crushedR) > 0.1)
    }

    @Test func missingFileThrows() {
        #expect(throws: LinearDecodeError.self) {
            _ = try LinearDecode.decode(path: "/no/such/scan.tif")
        }
    }
}
