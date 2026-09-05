import CoreGraphics
import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of NegPy `tests/test_working_oetf.py`.
struct WorkingOETFTests {
    private let gamma = 563.0 / 256.0

    @Test func encodeKnownGammaValues() {
        let enc = WorkingOETF.encode(rgb(0, 0.5, 1))
        let mid = Float(pow(0.5, 1.0 / gamma))
        #expect(abs(enc.pixels[0] - 0) < 1e-5)
        #expect(abs(enc.pixels[1] - mid) < 1e-5)
        #expect(abs(enc.pixels[2] - 1) < 1e-5)
    }

    @Test func encodeIsPurePowerNearBlack() {
        let linear: [Float] = [0.0005, 0.001, 0.0015]
        let enc = WorkingOETF.encode(rgb(linear[0], linear[1], linear[2]))
        for i in 0..<3 {
            let expected = Float(pow(Double(linear[i]), 1.0 / gamma))
            #expect(abs(enc.pixels[i] - expected) / expected < 1e-5)
        }
    }

    @Test func roundtripIdentity() {
        var pixels = [Float](repeating: 0, count: 256 * 3)
        for i in 0..<256 {
            let v = Float(i) / 255
            pixels[i * 3] = v
            pixels[i * 3 + 1] = v
            pixels[i * 3 + 2] = v
        }
        let ramp = LinearRGBBuffer(width: 256, height: 1, pixels: pixels)
        let back = WorkingOETF.decode(WorkingOETF.encode(ramp))
        for i in pixels.indices {
            #expect(abs(back.pixels[i] - pixels[i]) < 1e-5)
        }
    }

    @Test func encodeClampsToDisplayRange() {
        let enc = WorkingOETF.encode(rgb(-0.5, 1.5, 0.2))
        let minV = enc.pixels.min() ?? -1
        let maxV = enc.pixels.max() ?? 2
        #expect(minV >= 0)
        #expect(maxV <= 1)
        #expect(abs(enc.pixels[0] - 0) < 1e-6)
        #expect(abs(enc.pixels[1] - 1) < 1e-6)
        #expect(abs(enc.pixels[2] - WorkingOETF.encode(0.2)) < 1e-6)
    }

    @Test func decodeDoesNotClampHigh() {
        let high = WorkingOETF.decode(1.5)
        #expect(high > 1)
        #expect(abs(high - pow(Float(1.5), WorkingOETF.gamma)) < 1e-5)
    }

    @Test func encodeComposesWithWorkingICC() throws {
        guard let adobe = CGColorSpace(name: CGColorSpace.adobeRGB1998),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            Issue.record("Adobe RGB / sRGB color spaces unavailable")
            return
        }

        let lin = (0..<7).map { i -> Float in
            0.05 + (0.95 - 0.05) * Float(i) / 6
        }
        var pixels = [Float](repeating: 0, count: 7 * 3)
        for i in 0..<7 {
            pixels[i * 3] = lin[i]
            pixels[i * 3 + 1] = lin[i]
            pixels[i * 3 + 2] = lin[i]
        }
        let enc = WorkingOETF.encode(LinearRGBBuffer(width: 7, height: 1, pixels: pixels))

        var rgb = [UInt8](repeating: 0, count: 7 * 3)
        for i in 0..<7 {
            rgb[i * 3] = quantize8(enc.pixels[i * 3])
            rgb[i * 3 + 1] = quantize8(enc.pixels[i * 3 + 1])
            rgb[i * 3 + 2] = quantize8(enc.pixels[i * 3 + 2])
        }
        guard let provider = CGDataProvider(data: Data(rgb) as CFData),
              let image = CGImage(
                  width: 7,
                  height: 1,
                  bitsPerComponent: 8,
                  bitsPerPixel: 24,
                  bytesPerRow: 21,
                  space: adobe,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .relativeColorimetric
              )
        else {
            throw ICCComposeError.couldNotBuildAdobeImage
        }

        var out = [UInt8](repeating: 0, count: 7 * 4)
        guard let ctx = CGContext(
            data: &out,
            width: 7,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 28,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ICCComposeError.couldNotCreateSRGBContext
        }
        ctx.interpolationQuality = .none
        ctx.setRenderingIntent(.relativeColorimetric)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 7, height: 1))

        for i in 0..<7 {
            let encoded = Float(out[i * 4 + 1]) / 255
            let recovered = LinearDecode.srgbToLinear(encoded)
            #expect(abs(recovered - lin[i]) < 0.01)
        }
    }

    @Test func scalarMatchesBuffer() {
        #expect(abs(WorkingOETF.encode(0.5) - WorkingOETF.encode(rgb(0.5, 0.5, 0.5)).pixels[0]) < 1e-7)
        #expect(abs(WorkingOETF.decode(0.73) - WorkingOETF.decode(rgb(0.73, 0.73, 0.73)).pixels[0]) < 1e-7)
    }

    @Test func writeRampPNGs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s3-ramps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try NativePipeline().writeOETFRampPNGs(to: dir, width: 64, height: 8)
        let linearURL = dir.appendingPathComponent("oetf-linear.png")
        let encodedURL = dir.appendingPathComponent("oetf-encoded.png")
        #expect(FileManager.default.fileExists(atPath: linearURL.path))
        #expect(FileManager.default.fileExists(atPath: encodedURL.path))
        #expect(ImageCoding.probeDimensions(at: linearURL)?.width == 64)
        #expect(ImageCoding.probeDimensions(at: encodedURL)?.height == 8)
    }

    private func rgb(_ r: Float, _ g: Float, _ b: Float) -> LinearRGBBuffer {
        LinearRGBBuffer(width: 1, height: 1, pixels: [r, g, b])
    }

    private func quantize8(_ sample: Float) -> UInt8 {
        UInt8(min(255, max(0, sample * 255 + 0.5)))
    }
}

private enum ICCComposeError: Error {
    case couldNotBuildAdobeImage
    case couldNotCreateSRGBContext
}
