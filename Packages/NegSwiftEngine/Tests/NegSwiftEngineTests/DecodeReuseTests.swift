import Foundation
import Testing
@testable import NegSwiftEngine

/// S13d: detect + open + render share one ImageIO pass via the linear LRU.
@Suite(.serialized)
struct DecodeReuseTests {
    @Test func firstSelectFrameDetectOpenRenderDecodesOnce() throws {
        let url = try writeOrangeMaskTIFF(width: 96, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.detectProcessMode(path: url.path)
        var armed = PrintConfig.s8Pin
        armed.autoCropEnabled = true
        armed.cropFromAuto = true
        _ = try pipeline.decode(
            path: url.path,
            maxLongEdge: Autocrop.detectResolution,
            analysisOversample: true
        )
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: Int(Autocrop.previewRenderSize),
            processMode: .colorNegative,
            config: armed
        )
        #expect(PipelineStats.snapshot().decode == 1)
    }

    @Test func smallerLongEdgeReusesLargerSample() throws {
        let url = try writeOrangeMaskTIFF(width: 80, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.decode(
            path: url.path,
            maxLongEdge: 64,
            analysisOversample: true
        )
        #expect(PipelineStats.snapshot().decode == 1)
        let reused = try pipeline.decode(
            path: url.path,
            maxLongEdge: ProcessDetect.detectDecodeLongEdge,
            analysisOversample: true
        )
        #expect(PipelineStats.snapshot().decode == 1)
        #expect(reused.width > 0 && reused.height > 0)
    }

    @Test func exactEdgeMissNoLongerForcesSecondDecode() throws {
        let url = try writeOrangeMaskTIFF(width: 72, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 48,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(PipelineStats.snapshot().decode == 1)
    }

    @Test func cheapThumbDoesNotServeOversampledPreview() throws {
        let url = try writeOrangeMaskTIFF(width: 96, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.decode(path: url.path, maxLongEdge: 32, analysisOversample: false)
        #expect(PipelineStats.snapshot().decode == 1)
        _ = try pipeline.decode(path: url.path, maxLongEdge: 64, analysisOversample: true)
        #expect(PipelineStats.snapshot().decode == 2)
    }

    @Test func resetWorkingSetsClearsLinearLRU() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.detectProcessMode(path: url.path)
        #expect(PipelineStats.snapshot().decode == 1)
        NativePipeline.resetWorkingSets()
        _ = try pipeline.detectProcessMode(path: url.path)
        #expect(PipelineStats.snapshot().decode == 1)
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
        .appendingPathComponent("negswift-s13d-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
