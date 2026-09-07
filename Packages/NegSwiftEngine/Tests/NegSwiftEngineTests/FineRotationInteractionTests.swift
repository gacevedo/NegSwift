import Foundation
import Testing
@testable import NegSwiftEngine

/// Fine-rotation interaction: anchor render reuses metering, re-orients live.
@Suite(.serialized)
struct FineRotationInteractionTests {
    @Test func anchorRenderReusesAnalysisAndSkipsAnalyzeCounter() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var settled = PrintConfig.s5Pin
        settled.fineRotation = 0
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: settled
        )
        #expect(!first.reusedAnalysis)

        PipelineStats.reset()
        var dragged = settled
        dragged.fineRotation = 5
        let anchored = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: dragged,
            meteringAnchorFineRotation: 0
        )
        #expect(anchored.reusedAnalysis)
        #expect(PipelineStats.snapshot().analyze == 0)
        #expect(anchored.buffer.pixels != first.buffer.pixels)
    }

    @Test func settledRenderAfterAnchorReanalyzes() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var settled = PrintConfig.s5Pin
        settled.fineRotation = 0
        _ = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: settled
        )

        PipelineStats.reset()
        var dragged = settled
        dragged.fineRotation = 5
        _ = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: dragged,
            meteringAnchorFineRotation: 0
        )

        PipelineStats.reset()
        let final = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: dragged
        )
        #expect(!final.reusedAnalysis)
        #expect(PipelineStats.snapshot().analyze > 0)
    }

    @Test func anchorWithoutPriorCacheFallsBackToAnalyze() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var config = PrintConfig.s5Pin
        config.fineRotation = 3
        let result = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: config,
            meteringAnchorFineRotation: 0
        )
        #expect(!result.reusedAnalysis)
        #expect(PipelineStats.snapshot().analyze > 0)
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
        .appendingPathComponent("negswift-finerot-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
