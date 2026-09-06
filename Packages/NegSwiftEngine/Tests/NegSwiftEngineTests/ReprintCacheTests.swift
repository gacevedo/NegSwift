import Foundation
import Testing
@testable import NegSwiftEngine

/// S13a: density-only reprint skips heal / dust / orient / analyze.
@Suite(.serialized)
struct ReprintCacheTests {
    @Test func densityOnlyReprintSkipsBakeOrientAnalyze() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        var dust = PrintConfig.s8Pin
        dust.dustRemove = true
        dust.healStrokes = [
            HealStroke(points: [HealPoint(x: 0.4, y: 0.4), HealPoint(x: 0.6, y: 0.6)], size: 8),
        ]
        let pipeline = NativePipeline(pixelBackend: .cpu)
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: dust
        )
        #expect(!first.reusedBake)
        #expect(!first.reusedAnalysis)

        var density = dust
        density.density = dust.density + 0.15
        let second = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: density
        )
        #expect(second.reusedBake)
        #expect(second.reusedAnalysis)
        #expect(second.buffer.width == first.buffer.width && second.buffer.height == first.buffer.height)
        #expect(second.buffer.pixels != first.buffer.pixels)
    }

    @Test func densityReprintMatchesFreshPipeline() throws {
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        var a = PrintConfig.s8Pin
        a.density = 0.85
        let cached = try NativePipeline(pixelBackend: .cpu).renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        _ = cached
        let reprint = try NativePipeline(pixelBackend: .cpu).renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: a
        )
        NativePipeline.resetWorkingSets()
        let fresh = try NativePipeline(pixelBackend: .cpu).renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: a
        )
        #expect(reprint.meanAbsoluteError(against: fresh) == 0)
    }

    @Test func geometryChangeReorients() throws {
        let url = try writeOrangeMaskTIFF(width: 40, height: 24)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline(pixelBackend: .cpu)
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s5Pin
        )
        #expect(!first.reusedAnalysis)
        var rotated = PrintConfig.s5Pin
        rotated.rotation = 1
        let second = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: rotated
        )
        #expect(second.reusedBake)
        #expect(!second.reusedAnalysis)
    }

    @Test func goldenFixtureDensitySkipWhenPresent() throws {
        guard let fixture = sampleTIFF() else { return }
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var pin = PrintConfig.s8Pin
        _ = try pipeline.renderPrintDetailed(
            path: fixture.path,
            longEdgePx: 256,
            processMode: .colorNegative,
            config: pin
        )
        pin.density += 0.1
        let second = try pipeline.renderPrintDetailed(
            path: fixture.path,
            longEdgePx: 256,
            processMode: .colorNegative,
            config: pin
        )
        #expect(second.reusedBake)
        #expect(second.reusedAnalysis)
    }
}

private func sampleTIFF() -> URL? {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent("App/NegSwiftUITests/Fixtures/sample.tif")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
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
        .appendingPathComponent("negswift-s13a-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
