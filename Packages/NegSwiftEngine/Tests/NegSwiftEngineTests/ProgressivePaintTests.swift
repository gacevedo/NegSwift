import Foundation
import Testing
@testable import NegSwiftEngine

/// S13g: draft first paint then settled refine. Settled look matches S8; draft skips oversample / dust / sharpen.
@Suite(.serialized)
struct ProgressivePaintTests {
    @Test func draftClampsLongEdgeAndSkipsOversample() throws {
        let url = try writeOrangeMaskTIFF(width: 96, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var dusty = PrintConfig.s8Pin
        dusty.dustRemove = true
        let draft = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: dusty,
            previewPass: .draft
        )
        #expect(draft.previewPass == .draft)
        #expect(draft.analysisOversampled == false)
        #expect(draft.buffer.longEdge <= PreviewPass.draftLongEdge)
        #expect(PipelineStats.snapshot().dust == 0)
        #expect(PipelineStats.timings().firstPaintMs > 0)
    }

    @Test func settledOversamplesAndMatchesDefaultS8Print() throws {
        let url = try writeOrangeMaskTIFF(width: 80, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        let settled = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: .s8Pin,
            previewPass: .settled
        )
        NativePipeline.resetWorkingSets()
        let baseline = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(settled.previewPass == .settled)
        #expect(settled.analysisOversampled)
        #expect(settled.buffer.width == baseline.width)
        #expect(settled.buffer.height == baseline.height)
        #expect(settled.buffer.meanAbsoluteError(against: baseline) == 0)
        #expect(PipelineStats.timings().fullPreviewMs > 0)
    }

    @Test func draftDoesNotReplaceSettledReprintCache() throws {
        let url = try writeOrangeMaskTIFF(width: 64, height: 40)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: .s8Pin,
            previewPass: .draft
        )
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin,
            previewPass: .settled
        )
        PipelineStats.reset()
        var reprint = PrintConfig.s8Pin
        reprint.density = 1.15
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: reprint,
            previewPass: .settled
        )
        let stats = PipelineStats.snapshot()
        #expect(stats.dust == 0)
        #expect(stats.orient == 0)
        #expect(stats.analyze == 0)
        #expect(stats.print == 1)
    }

    @Test func draftThenSettledRecordsBothTimings() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 512,
            processMode: .colorNegative,
            config: .s8Pin,
            previewPass: .draft
        )
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: .s8Pin,
            previewPass: .settled
        )
        let timings = PipelineStats.timings()
        #expect(timings.firstPaintMs > 0)
        #expect(timings.fullPreviewMs > 0)
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
        .appendingPathComponent("negswift-s13g-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
