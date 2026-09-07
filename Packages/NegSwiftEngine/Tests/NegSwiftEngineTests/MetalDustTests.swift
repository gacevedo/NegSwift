import Foundation
import Testing
@testable import NegSwiftEngine

/// S13l: CPU-vs-Metal optical dust MAE (detect + bake).
@Suite(.serialized)
struct MetalDustTests {
    private static let detectMAE: Float = 1e-4
    private static let bakeMAE: Float = 0.002

    @Test func statsMatchCPU() throws {
        try requireMetal()
        let image = dustySource(width: 160, height: 160, grain: false)
        let cpu = OpticalDust.computeStats(image, dustSize: 4)
        let gpu = try #require(MetalDust.detect(image, threshold: 0.66, size: 4))
        let cpuDetect = OpticalDust.detectFromStats(cpu, threshold: 0.66, dustSize: 4, width: image.width, height: image.height)
        #expect(scoreMAE(cpuDetect.score, gpu.score) < Self.detectMAE)
    }

    @Test func bakeMatchesCPU() throws {
        try requireMetal()
        let image = dustySource(width: 160, height: 160, grain: false)
        let cpu = OpticalDust.bakeCPU(image, threshold: 0.66, size: 4)
        let gpu = try #require(MetalDust.bake(image, threshold: 0.66, size: 4))
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.bakeMAE)
    }

    @Test func pipelineDustToggleUsesMetalWhenAvailable() throws {
        try requireMetal()
        let w = 160
        let h = 160
        var samples = [UInt16](repeating: 12_000, count: w * h * 3)
        for y in 80..<83 {
            for x in 80..<83 {
                let i = (y * w + x) * 3
                samples[i] = 300
                samples[i + 1] = 300
                samples[i + 2] = 300
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13l-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: w, height: h, samples: samples, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = NativePipeline(pixelBackend: .metal)
        var on = PrintConfig.s8Pin
        on.dustRemove = true
        on.dustThreshold = 0.66
        on.dustSize = 4
        NativePipeline.resetWorkingSets()
        let baked = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: on
        )
        #expect(speckMean(baked, width: w) > 0.1)
    }

    private func requireMetal() throws {
        #expect(MetalDevice.isAvailable, "Metal required for S13l dust tests")
    }

    private func scoreMAE(_ a: [Float]?, _ b: [Float]?) -> Float {
        switch (a, b) {
        case (nil, nil): return 0
        case (nil, _), (_, nil): return .infinity
        case let (lhs?, rhs?):
            guard lhs.count == rhs.count else { return .infinity }
            var sum: Float = 0
            for i in 0..<lhs.count {
                sum += abs(lhs[i] - rhs[i])
            }
            return sum / Float(lhs.count)
        }
    }

    private func speckMean(_ buffer: LinearRGBBuffer, width: Int) -> Float {
        var mean: Float = 0
        var n: Float = 0
        for y in 80..<83 {
            for x in 80..<83 {
                let i = (y * width + x) * 3
                mean += buffer.pixels[i]
                n += 1
            }
        }
        return mean / n
    }
}

private func dustySource(width: Int, height: Int, grain: Bool = true) -> LinearRGBBuffer {
    var pixels = grainy(width: width, height: height, level: 0.18, sigma: 0.02, seed: 42)
    stampSpeck(&pixels, width: width, x0: width / 2, y0: height / 2, size: 3, level: 0.005)
    return LinearRGBBuffer(width: width, height: height, pixels: pixels)
}

private func grainy(width: Int, height: Int, level: Float, sigma: Float, seed: UInt64) -> [Float] {
    var rng = SplitMix64(seed: seed)
    var out = [Float](repeating: level, count: width * height * 3)
    for i in 0..<out.count {
        out[i] = max(0, min(1, level * (1 + Float(rng.next() % 10_000) / 10_000 * sigma * 2 - sigma)))
    }
    return out
}

private func stampSpeck(
    _ pixels: inout [Float],
    width: Int,
    x0: Int,
    y0: Int,
    size: Int,
    level: Float
) {
    for y in (y0 - size / 2)..<(y0 + size / 2 + 1) {
        for x in (x0 - size / 2)..<(x0 + size / 2 + 1) {
            let i = (y * width + x) * 3
            pixels[i] = level
            pixels[i + 1] = level
            pixels[i + 2] = level
        }
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
