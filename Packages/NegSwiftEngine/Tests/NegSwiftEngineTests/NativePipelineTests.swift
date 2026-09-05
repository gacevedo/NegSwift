import Foundation
import Testing
@testable import NegSwiftEngine

struct NativePipelineTests {
    @Test func infoReportsS3Identity() {
        let info = NativePipeline().infoJSON()
        #expect(info["protocol_version"] as? String == EngineVersion.protocolVersion)
        #expect(info["negswift_version"] as? String == EngineVersion.packageVersion)
        #expect(info["negpy_version"] as? String == "s3-oetf")
        #expect(info["backend"] as? String == "swift")
        #expect(info["gpu_available"] as? Bool == false)
    }

    @Test func renderNormalizedDoesNotApplyOETF() throws {
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        let linear = try pipeline.decode(path: url.path)
        let normalized = try pipeline.renderNormalized(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative
        )
        let expected = pipeline.normalize(linear, processMode: .colorNegative)
        #expect(normalized.pixels == expected.pixels)
        let encoded = WorkingOETF.encode(expected)
        #expect(normalized.pixels != encoded.pixels)
    }

    @Test func renderNormalizedTurnsC41MaskIntoUninvertedPositive() throws {
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        let linear = try pipeline.decode(path: url.path)
        let normalized = try pipeline.renderNormalized(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative
        )

        let linMeans = channelMeans(linear)
        #expect(linMeans.0 - linMeans.2 > 0.1)

        let means = channelMeans(normalized)
        #expect(abs(means.0 - means.1) < 0.05)
        #expect(abs(means.1 - means.2) < 0.05)

        let center = pixel(normalized, x: 20, y: 16)
        let corner = pixel(normalized, x: 0, y: 0)
        #expect(center.0 < corner.0)
    }

    @Test func writeLinearF32MatchesDecodeShape() throws {
        let url = try writeOrangeMaskTIFF(width: 8, height: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s1-\(UUID().uuidString).f32")
        defer { try? FileManager.default.removeItem(at: out) }
        let dims = try NativePipeline().writeLinearF32(path: url.path, to: out)
        #expect(dims.width == 8)
        #expect(dims.height == 4)
        let data = try Data(contentsOf: out)
        #expect(data.count == 8 * 4 * 3 * MemoryLayout<Float>.size)
    }

    @Test func detectProcessModeReadsTIFF() throws {
        let url = try writeDecorrelatedOrangeTIFF(width: 32, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try NativePipeline().detectProcessMode(path: url.path) == .colorNegative)
    }

    @Test func probeSourceReadsDimensions() throws {
        let url = try writeOrangeMaskTIFF(width: 12, height: 9)
        defer { try? FileManager.default.removeItem(at: url) }
        let dims = NativePipeline().probeSource(at: url.path)
        #expect(dims?.width == 12)
        #expect(dims?.height == 9)
    }
}

private func writeOrangeMaskTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    let cy = Double(height - 1) / 2
    let cx = Double(width - 1) / 2
    for y in 0..<height {
        for x in 0..<width {
            let dist = pow((Double(y) - cy) / Double(height), 2) + pow((Double(x) - cx) / Double(width), 2)
            let t = 0.25 + 0.55 * dist
            let i = (y * width + x) * 3
            samples[i] = UInt16(clamping: Int((min(1, max(1e-6, 0.70 * t)) * 65535).rounded()))
            samples[i + 1] = UInt16(clamping: Int((min(1, max(1e-6, 0.38 * t)) * 65535).rounded()))
            samples[i + 2] = UInt16(clamping: Int((min(1, max(1e-6, 0.16 * t)) * 65535).rounded()))
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s2-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

/// Constant orange plus per-pixel channel noise so detect does not see a B&W tint.
private func writeDecorrelatedOrangeTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    var rng = SplitMix64(seed: 0)
    for i in 0..<(width * height) {
        samples[i * 3] = UInt16(clamping: Int((clamp01(0.6 + rng.uniform(-0.15, 0.15)) * 65535).rounded()))
        samples[i * 3 + 1] = UInt16(clamping: Int((clamp01(0.4 + rng.uniform(-0.15, 0.15)) * 65535).rounded()))
        samples[i * 3 + 2] = UInt16(clamping: Int((clamp01(0.2 + rng.uniform(-0.15, 0.15)) * 65535).rounded()))
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s1-detect-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }

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

private func channelMeans(_ buffer: LinearRGBBuffer) -> (Float, Float, Float) {
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0
    let n = buffer.width * buffer.height
    for i in 0..<n {
        r += buffer.pixels[i * 3]
        g += buffer.pixels[i * 3 + 1]
        b += buffer.pixels[i * 3 + 2]
    }
    let count = Float(n)
    return (r / count, g / count, b / count)
}

private func pixel(_ buffer: LinearRGBBuffer, x: Int, y: Int) -> (Float, Float, Float) {
    let i = (y * buffer.width + x) * 3
    return (buffer.pixels[i], buffer.pixels[i + 1], buffer.pixels[i + 2])
}
