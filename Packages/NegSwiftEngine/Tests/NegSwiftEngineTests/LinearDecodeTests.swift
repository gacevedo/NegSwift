import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
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

    @Test func analysisSampleLongEdgeOversamplesPreview() {
        #expect(LinearDecode.analysisSampleLongEdge(requested: 1600, sourceLongEdge: 8256) == 4096)
        #expect(LinearDecode.analysisSampleLongEdge(requested: 1200, sourceLongEdge: 8256) == 4096)
        #expect(LinearDecode.analysisSampleLongEdge(requested: 2400, sourceLongEdge: 8256) == 4800)
        #expect(LinearDecode.analysisSampleLongEdge(requested: 1600, sourceLongEdge: 2000) == 2000)
    }

    @Test func srgbToLinearMatchesIEC61966() {
        #expect(LinearDecode.srgbToLinear(0) == 0)
        #expect(abs(LinearDecode.srgbToLinear(0.04045) - 0.04045 / 12.92) < 1e-7)
        #expect(abs(LinearDecode.srgbToLinear(1) - 1) < 1e-6)
        let mid = Foundation.pow((0.5 + 0.055) / 1.055, 2.4)
        #expect(abs(LinearDecode.srgbToLinear(0.5) - Float(mid)) < 1e-6)
    }

    @Test func transferPolicyFollowsBitDepthAndJPEG() {
        #expect(LinearDecode.shouldApplySRGBToLinear(uti: "public.jpeg", bitsPerComponent: 8, properties: [:]))
        #expect(LinearDecode.shouldApplySRGBToLinear(uti: "public.tiff", bitsPerComponent: 8, properties: [:]))
        #expect(!LinearDecode.shouldApplySRGBToLinear(uti: "public.tiff", bitsPerComponent: 16, properties: [:]))
        #expect(
            LinearDecode.shouldApplySRGBToLinear(
                uti: "public.tiff",
                bitsPerComponent: 16,
                properties: [kCGImagePropertyProfileName: "sRGB IEC61966-2.1"]
            )
        )
    }

    @Test func jpegAppliesSRGBToLinear() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-jpeg-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSolidJPEG(gray: 128, width: 8, height: 8, to: url)

        let buffer = try LinearDecode.decode(url: url)
        let encoded = Float(128) / 255
        let expected = LinearDecode.srgbToLinear(encoded)
        #expect(abs(buffer.pixels[0] - expected) < 0.03)
        #expect(abs(buffer.pixels[0] - encoded) > 0.04)
    }
}

private func writeSolidJPEG(gray: UInt8, width: Int, height: Int, to url: URL) throws {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) {
        rgba[i * 4] = gray
        rgba[i * 4 + 1] = gray
        rgba[i * 4 + 2] = gray
    }
    let data = Data(rgba)
    guard let provider = CGDataProvider(data: data as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: space,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(
              url as CFURL,
              UTType.jpeg.identifier as CFString,
              1,
              nil
          )
    else {
        throw LinearDecodeError.decodeFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw LinearDecodeError.decodeFailed
    }
}
