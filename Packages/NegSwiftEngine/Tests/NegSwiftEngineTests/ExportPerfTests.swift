import Foundation
import Testing
@testable import NegSwiftEngine

/// S13m: target_px export prints at the requested long edge and reuses preview caches.
@Suite(.serialized)
struct ExportPerfTests {
    @Test func targetPxExportPrintsAtLongEdge() throws {
        let frame = try writeSizingTIFF(width: 512, height: 384)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13m-edge-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        NativePipeline.resetWorkingSets()
        let exported = try NativePipeline(pixelBackend: .cpu).export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: sizedPrintConfig,
            settings: NativeExportSettings(
                format: .jpeg,
                resolutionMode: .targetPx,
                targetLongEdgePx: 256
            )
        )
        #expect(max(exported.width, exported.height) == 256)
        #expect(PipelineStats.timings().exportMs > 0)
    }

    @Test func exportAfterPreviewReusesLinearDecode() throws {
        let frame = try writeSizingTIFF(width: 512, height: 384)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13m-cache-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrintDetailed(
            path: frame.path,
            longEdgePx: 256,
            processMode: .colorNegative,
            config: sizedPrintConfig
        )
        #expect(PipelineStats.snapshot().decode == 1)

        PipelineStats.reset()
        _ = try pipeline.export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: sizedPrintConfig,
            settings: NativeExportSettings(
                format: .jpeg,
                resolutionMode: .targetPx,
                targetLongEdgePx: 256
            )
        )
        let stats = PipelineStats.snapshot()
        #expect(stats.decode == 0)
        #expect(stats.orient == 0)
        #expect(stats.analyze == 0)
    }

    @Test func exportAfterLargerPreviewReusesLinearDecode() throws {
        let frame = try writeSizingTIFF(width: 512, height: 384)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13m-larger-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrintDetailed(
            path: frame.path,
            longEdgePx: 384,
            processMode: .colorNegative,
            config: sizedPrintConfig
        )
        PipelineStats.reset()
        _ = try pipeline.export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: sizedPrintConfig,
            settings: NativeExportSettings(
                format: .jpeg,
                resolutionMode: .targetPx,
                targetLongEdgePx: 256
            )
        )
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(try exportedLongEdge(dest: dest) == 256)
    }

    @Test func originalExportStillFullRes() throws {
        let frame = try writeSizingTIFF(width: 512, height: 384)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13m-full-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        NativePipeline.resetWorkingSets()
        let exported = try NativePipeline(pixelBackend: .cpu).export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: sizedPrintConfig,
            settings: NativeExportSettings(format: .jpeg, resolutionMode: .original)
        )
        #expect(max(exported.width, exported.height) == 512)
    }
}

private func writeSizingTIFF(width: Int, height: Int) throws -> URL {
    let samples = [UInt16](repeating: 40_000, count: width * height * 3)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13m-size-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func exportedLongEdge(dest: URL) throws -> Int {
    let files = try FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
    guard let file = files.first else {
        throw NSError(domain: "ExportPerfTests", code: 1)
    }
    let dims = ImageCoding.probeDimensions(at: file)
    return max(dims?.width ?? 0, dims?.height ?? 0)
}

private var sizedPrintConfig: PrintConfig {
    var config = PrintConfig.s8Pin
    config.autoCropEnabled = false
    config.cropFromAuto = false
    return config
}
