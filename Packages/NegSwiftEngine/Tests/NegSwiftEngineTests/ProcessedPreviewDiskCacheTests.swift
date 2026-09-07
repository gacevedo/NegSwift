import Foundation
import Testing
@testable import NegSwiftEngine

/// S13k: processed preview disk cache + longer-lived in-memory working sets.
@Suite(.serialized)
struct ProcessedPreviewDiskCacheTests {
    @Test func diskCacheHitSkipsDecodeAfterSessionReset() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeOrangeMaskTIFF(width: 72, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(PipelineStats.snapshot().decode == 1)

        NativePipeline.resetWorkingSets()
        let reopened = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(reopened.reusedDiskCache)
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(PipelineStats.snapshot().print == 0)
    }

    @Test func diskCacheMatchesFreshPipeline() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeOrangeMaskTIFF(width: 64, height: 40)
        defer { try? FileManager.default.removeItem(at: url) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        let cached = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )

        NativePipeline.resetWorkingSets()
        let reopened = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(reopened.meanAbsoluteError(against: cached) == 0)

        NativePipeline.resetWorkingSets()
        let fresh = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(reopened.meanAbsoluteError(against: fresh) == 0)
    }

    @Test func sidecarChangeInvalidatesDiskCache() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeOrangeMaskTIFF(width: 56, height: 36)
        defer { try? FileManager.default.removeItem(at: url) }
        let sidecar = SidecarStore.url(forScanPath: url.path)
        defer { try? FileManager.default.removeItem(at: sidecar) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )

        var edited = PrintConfig.s8Pin
        edited.density = 1.05
        _ = try SidecarStore.save(path: url.path, overrides: ["density": edited.density])

        NativePipeline.resetWorkingSets()
        let afterSidecar = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: edited
        )
        #expect(!afterSidecar.reusedDiskCache)
        #expect(PipelineStats.snapshot().decode == 1)
    }

    @Test func cropPreviewFullDoesNotSatisfyAppliedCropLookup() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeOrangeMaskTIFF(width: 64, height: 40)
        defer { try? FileManager.default.removeItem(at: url) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var cropped = PrintConfig.s8Pin
        cropped.cropRect = NormalizedCropRect(x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8)
        cropped.applyPixelCrop = true
        var preview = cropped
        preview.applyPixelCrop = false

        let applied = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: cropped
        )
        NativePipeline.resetWorkingSets()
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: preview
        )

        NativePipeline.resetWorkingSets()
        let reopened = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: cropped
        )
        #expect(reopened.reusedDiskCache)
        #expect(reopened.buffer.width == applied.width)
        #expect(reopened.buffer.height == applied.height)
        #expect(reopened.buffer.meanAbsoluteError(against: applied) == 0)
        #expect(PipelineStats.snapshot().decode == 0)
    }

    @Test func diskCacheHitsAfterAutoCropFreezeInSidecar() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeFrameTIFF(width: 180, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var armed = PrintConfig.s8Pin
        armed.cropFromAuto = true
        armed.autoCropEnabled = true

        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: armed
        )
        #expect(!first.reusedDiskCache)
        guard let resolved = first.resolvedAutocrop else {
            Issue.record("expected resolved autocrop rect")
            return
        }

        var reopened = armed
        reopened.cropRect = resolved.rect
        reopened.cropDetectKey = resolved.key
        reopened.cropFromAuto = true
        reopened.autoCropEnabled = false
        reopened.applyPixelCrop = true

        NativePipeline.resetWorkingSets()
        let hit = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: reopened
        )
        #expect(hit.reusedDiskCache)
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(PipelineStats.snapshot().print == 0)
    }

    @Test func legacyDiskCacheLookupFallsBackWithoutCropKey() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

        let url = try writeOrangeMaskTIFF(width: 64, height: 40)
        defer { try? FileManager.default.removeItem(at: url) }

        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var noCrop = PrintConfig.s8Pin
        noCrop.autoCropEnabled = true
        let buffer = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: noCrop
        )

        NativePipeline.resetWorkingSets()
        ProcessedPreviewDiskCache.shared.store(
            path: url.path,
            longEdgePx: 64,
            config: noCrop,
            processMode: .colorNegative,
            buffer: buffer
        )

        var withCrop = PrintConfig.s8Pin
        withCrop.cropRect = NormalizedCropRect(x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8)
        withCrop.cropFromAuto = true
        withCrop.autoCropEnabled = false
        withCrop.applyPixelCrop = true

        let hit = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: withCrop
        )
        #expect(hit.reusedDiskCache)
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(PipelineStats.snapshot().print == 0)
    }

    @Test func diskCacheLookupNormalizesFrozenAutoCropShape() throws {
        var armed = PrintConfig.s8Pin
        armed.cropRect = NormalizedCropRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 0.9)
        armed.cropFromAuto = true
        armed.autoCropEnabled = true

        var frozen = armed
        frozen.autoCropEnabled = false

        let armedKey = ProcessedPreviewDiskCache.cacheKey(
            path: "/tmp/a.tif",
            longEdgePx: 64,
            config: ProcessedPreviewDiskCache.diskCacheStoreConfig(pass: .s8Pin, resolved: armed),
            processMode: .colorNegative
        )
        let frozenKey = ProcessedPreviewDiskCache.cacheKey(
            path: "/tmp/a.tif",
            longEdgePx: 64,
            config: ProcessedPreviewDiskCache.diskCacheLookupConfig(frozen),
            processMode: .colorNegative
        )
        #expect(armedKey == frozenKey)
    }

    @Test func processedStripThumbDownscalesDiskCache() throws {
        let root = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        NativePipeline.configureDiskPreviewCache(rootDirectory: root)
        defer { NativePipeline.configureDiskPreviewCache(rootDirectory: nil) }

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

        NativePipeline.resetWorkingSets()
        let thumb = pipeline.processedStripThumb(
            path: url.path,
            thumbLongEdge: 24,
            previewLongEdge: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(thumb != nil)
        #expect(max(thumb!.width, thumb!.height) <= 24)
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(PipelineStats.snapshot().print == 0)
    }

    @Test func reprintCacheRetainsMoreThanEightFrames() throws {
        NativePipeline.resetWorkingSets()
        defer { NativePipeline.resetWorkingSets() }
        let pipeline = NativePipeline(pixelBackend: .cpu)
        var urls: [URL] = []
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        for index in 0..<10 {
            let url = try writeOrangeMaskTIFF(width: 32 + index, height: 24)
            urls.append(url)
            _ = try pipeline.renderPrint(
                path: url.path,
                longEdgePx: 48,
                processMode: .colorNegative,
                config: .s8Pin
            )
        }

        var density = PrintConfig.s8Pin
        density.density = 1.1
        for url in urls {
            let reprint = try pipeline.renderPrintDetailed(
                path: url.path,
                longEdgePx: 48,
                processMode: .colorNegative,
                config: density
            )
            #expect(reprint.reusedBake)
            #expect(reprint.reusedAnalysis)
        }
    }
}

private func makeCacheRoot() throws -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13k-\(UUID().uuidString)", isDirectory: true)
}

private func writeFrameTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 65535, count: width * height * 3)
    let y1 = Int((0.12 * Double(height)).rounded())
    let y2 = Int((0.88 * Double(height)).rounded())
    let x1 = Int((0.10 * Double(width)).rounded())
    let x2 = Int((0.90 * Double(width)).rounded())
    for y in y1..<y2 {
        for x in x1..<x2 {
            let i = (y * width + x) * 3
            samples[i] = 3277
            samples[i + 1] = 3277
            samples[i + 2] = 3277
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13k-frame-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
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
        .appendingPathComponent("negswift-s13k-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
