//
//  NativeEngineBackendTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Foundation
import Testing
@testable import NegSwift
import NegSwiftEngine

private let sampleTIFFPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("NegSwiftUITests/Fixtures/sample.tif")
    .path

@Suite(.serialized)
struct NativeEngineBackendTests {
    @Test func infoReportsSwiftDecode() async throws {
        let backend = NativeEngineBackend()
        let info = try await backend.info()
        #expect(info.negpyVersion == EngineVersion.oracleLabel)
        #expect(info.gpuBackend == (MetalDevice.isAvailable ? MetalDevice.backendName : EngineVersion.backendName))
        #expect(info.gpuAvailable == MetalDevice.isAvailable)
    }

    @Test func stopDoesNotWaitForInFlightRender() async throws {
        let backend = NativeEngineBackend()
        let render = Task {
            try await backend.render(
                path: sampleTIFFPath,
                longEdgePx: 64,
                preferGPU: false,
                config: nil,
                cropPreviewFull: false,
                stripThumbnail: false,
                previewFormat: .jpeg,
                jpegQuality: 90
            )
        }
        await backend.stop()
        do {
            _ = try await render.value
        } catch is CancellationError {
            return
        }
    }

    @Test(.enabled(if: MetalDevice.isAvailable))
    func metalPreviewDoesNotDownloadFullFloatBuffer() async throws {
        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let backend = NativeEngineBackend()
        let result = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: true,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(result.nativePreview != nil)
        #expect(result.nativePreview?.cgImage.colorSpace?.name == CGColorSpace.adobeRGB1998)
        #expect(PipelineStats.snapshot().download == 0)
        let uploads = PipelineStats.snapshot().upload
        var edit = FrameEditState()
        edit.density = 1.15
        _ = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: true,
            config: edit,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(PipelineStats.snapshot().upload == uploads)
        #expect(PipelineStats.snapshot().download == 0)
    }

    @Test func normalizedRenderReturnsNativePreview() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: false,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(result.width > 0)
        #expect(result.height > 0)
        #expect(result.nativePreview != nil)
        #expect(result.jpegBase64 == nil)
        #expect(result.pngBase64 == nil)
        #expect(result.imageData == nil)
    }

    @Test func detectC41OnSampleTIFF() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.detectProcessMode(path: sampleTIFFPath, force: true)
        #expect(result.skipped == false)
        #expect(result.processMode == "Color Negative")
    }

    @Test func detectSkipsWhenSidecarPresent() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.detectProcessMode(path: sampleTIFFPath, force: false)
        #expect(result.skipped == true)
        #expect(result.reason == "has_sidecar")
    }

    @Test func loadConfigWithoutSidecarReturnsShippedDefaults() async throws {
        let backend = NativeEngineBackend()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s7-be-\(UUID().uuidString).tif")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sampleTIFFPath), to: dest)
        defer {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.removeItem(at: SidecarLocator.url(forScanPath: dest.path))
        }
        let loaded = try await backend.loadConfig(path: dest.path)
        #expect(loaded.hasSidecar == false)
        #expect(loaded.config["process_mode"]?.anyValue as? String == "Color Negative")
        if case let .double(grade) = loaded.config["grade"] {
            #expect(grade == 100)
        } else if case let .int(grade) = loaded.config["grade"] {
            #expect(grade == 100)
        } else {
            Issue.record("grade missing")
        }
    }

    @Test func saveConfigWritesFullNegPySidecar() async throws {
        let backend = NativeEngineBackend()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s7-save-\(UUID().uuidString).tif")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sampleTIFFPath), to: dest)
        defer {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.removeItem(at: SidecarLocator.url(forScanPath: dest.path))
        }
        var edit = FrameEditState()
        edit.density = 1.25
        edit.autoExposure = false
        let saved = try await backend.saveConfig(path: dest.path, config: edit)
        #expect(saved.sidecarPath.hasSuffix(".negpy"))
        let loaded = try await backend.loadConfig(path: dest.path)
        #expect(loaded.hasSidecar)
        if case let .double(density) = loaded.config["density"] {
            #expect(density == 1.25)
        } else {
            Issue.record("density missing")
        }
        #expect(loaded.config["clahe_strength"] != nil)
        #expect(loaded.config["sharpen"] != nil)
    }

    @Test func openReportsSourceDimensions() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.open(path: sampleTIFFPath, includeSplash: false, config: nil)
        #expect(result.width > 0)
        #expect(result.height > 0)
        #expect(result.path == sampleTIFFPath)
        #expect(result.suggestedCropRect == nil)
    }

    @Test func openWithSplashSuggestsArmedAutocrop() async throws {
        let url = try writeFrameTIFF(width: 160, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let backend = NativeEngineBackend()
        var edit = FrameEditState()
        edit.autoCropEnabled = true
        edit.cropFromAuto = true
        let result = try await backend.open(path: url.path, includeSplash: true, config: edit)
        #expect(result.suggestedCropRect?.count == 4)
        #expect(result.cropDetectKey?.isEmpty == false)
    }

    @Test func stripThumbnailDoesNotTakeThePrintPath() async throws {
        let url = try writeFrameTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let backend = NativeEngineBackend()
        let result = try await backend.render(
            path: url.path,
            longEdgePx: 32,
            preferGPU: false,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: true,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(result.width > 0 && result.height > 0)
        #expect(result.nativePreview != nil)
        #expect(PipelineStats.snapshot().print == 0)
        #expect(PipelineStats.snapshot().decode == 0)
    }

    @Test(.enabled(if: RawDecode.isAvailable && localCameraRawPath() != nil))
    func openIncludeSplashReturnsEmbeddedJPEGOnLocalRAW() async throws {
        guard let url = localCameraRawPath() else { return }
        NativePipeline.resetWorkingSets()
        let backend = NativeEngineBackend()
        let result = try await backend.open(path: url.path, includeSplash: true, config: nil)
        #expect(result.splashJPEGBase64?.isEmpty == false)
        #expect((result.splashWidth ?? 0) > 0)
        #expect((result.splashHeight ?? 0) > 0)
        #expect(PipelineStats.snapshot().decode == 0)
    }

    @Test func queuedStripThumbsCompleteWithoutASiblingDetect() async throws {
        let urls = try (0..<3).map { _ in try writeFrameTIFF(width: 48, height: 32) }
        defer {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
        NativePipeline.resetWorkingSets()
        let backend = NativeEngineBackend()
        let results = try await withThrowingTaskGroup(of: RenderResult.self) { group in
            for url in urls {
                group.addTask {
                    try await backend.render(
                        path: url.path,
                        longEdgePx: 32,
                        preferGPU: false,
                        config: nil,
                        cropPreviewFull: false,
                        stripThumbnail: true,
                        previewFormat: .jpeg,
                        jpegQuality: 90
                    )
                }
            }
            var collected: [RenderResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.width > 0 && $0.nativePreview != nil })
    }

    @Test func firstSelectFrameDetectOpenRenderDecodesOnce() async throws {
        let url = try writeFrameTIFF(width: 160, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let backend = NativeEngineBackend()
        var edit = FrameEditState()
        edit.autoCropEnabled = true
        edit.cropFromAuto = true
        _ = try await backend.detectProcessMode(path: url.path, force: true)
        _ = try await backend.open(path: url.path, includeSplash: true, config: edit)
        _ = try await backend.render(
            path: url.path,
            longEdgePx: Int(Autocrop.previewRenderSize),
            preferGPU: false,
            config: edit,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(PipelineStats.snapshot().decode == 1)
    }

    @Test func prefetchLinearWarmsTheNextRender() async throws {
        let url = try writeFrameTIFF(width: 80, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let backend = NativeEngineBackend()
        try await backend.prefetchLinear(
            path: url.path,
            maxLongEdge: 64,
            analysisOversample: true
        )
        #expect(PipelineStats.snapshot().decode == 1)
        _ = try await backend.render(
            path: url.path,
            longEdgePx: 64,
            preferGPU: false,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(PipelineStats.snapshot().decode == 1)
        #expect(PipelineStats.snapshot().print == 1)
    }

    @Test func detectMissingFileIsNotFound() async {
        let backend = NativeEngineBackend()
        do {
            _ = try await backend.detectProcessMode(path: "/no/such/scan.tif", force: true)
            Issue.record("expected NOT_FOUND")
        } catch let EngineClientError.engine(payload) {
            #expect(payload.code == "NOT_FOUND")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func cropPreviewFullKeepsFullBleedDimensions() async throws {
        let backend = NativeEngineBackend()
        var edit = FrameEditState()
        edit.manualCropRect = NormalizedRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        edit.cropFromAuto = false
        let full = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: false,
            config: edit,
            cropPreviewFull: true,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        let cropped = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: false,
            config: edit,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(full.width * full.height > cropped.width * cropped.height)
        #expect(full.width == cropped.width * 2)
        #expect(full.height == cropped.height * 2)
    }

    @Test func rotationSwapsPreviewDimensions() async throws {
        let backend = NativeEngineBackend()
        let base = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: false,
            config: FrameEditState(),
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        var rotated = FrameEditState()
        rotated.rotation = 1
        let out = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 64,
            preferGPU: false,
            config: rotated,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(base.width == out.height)
        #expect(base.height == out.width)
    }

    @Test func exportJPEGWritesFileAndReportsDimensions() async throws {
        let backend = NativeEngineBackend()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-be-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        let result = try await backend.export(
            path: sampleTIFFPath,
            destDir: dest.path,
            config: FrameEditState(),
            export: ExportSettings.quickExport(),
            preferGPU: false
        )
        #expect(result.width > 0)
        #expect(result.height > 0)
        #expect(result.format == "JPEG")
        #expect(FileManager.default.fileExists(atPath: result.outputPath))
        #expect(result.outputPath.hasSuffix(".jpg"))
    }

    @Test func exportAppliesCropAndShrinksPixels() async throws {
        NativePipeline.resetWorkingSets()
        let scan = try writeFrameTIFF(width: 160, height: 120)
        defer { try? FileManager.default.removeItem(at: scan) }
        let backend = NativeEngineBackend()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-be-crop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        var exportSettings = ExportSettings.quickExport()
        exportSettings.resolutionMode = .original
        var fullConfig = FrameEditState()
        fullConfig.autoCropEnabled = false
        fullConfig.cropFromAuto = false
        let full = try await backend.export(
            path: scan.path,
            destDir: dest.appendingPathComponent("full").path,
            config: fullConfig,
            export: exportSettings,
            preferGPU: false
        )
        var cropped = FrameEditState()
        cropped.autoCropEnabled = false
        cropped.manualCropRect = NormalizedRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        cropped.cropFromAuto = false
        cropped.autoDensityUsesCrop = false
        let cut = try await backend.export(
            path: scan.path,
            destDir: dest.appendingPathComponent("crop").path,
            config: cropped,
            export: exportSettings,
            preferGPU: false
        )
        #expect(cut.width * cut.height < full.width * full.height)
    }

    @Test func printInputsForwardsHealStrokes() {
        var edit = FrameEditState()
        edit.manualHealStrokes = [
            HealStroke(points: [HealStrokePoint(x: 0.4, y: 0.55)], size: 8),
        ]
        let mapped = NativeEngineBackend.printInputs(from: edit)
        #expect(mapped.printConfig.healStrokes.count == 1)
        #expect(mapped.printConfig.healStrokes[0].size == 8)
        #expect(mapped.printConfig.healStrokes[0].points[0].x == 0.4)
        #expect(mapped.printConfig.healStrokes[0].points[0].y == 0.55)
    }

    @Test func normalizedRenderSkipsEncodedPNG() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.render(
            path: sampleTIFFPath,
            longEdgePx: 32,
            preferGPU: false,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .png,
            jpegQuality: 90
        )
        #expect(result.nativePreview != nil)
        #expect(result.pngBase64 == nil)
        #expect(result.pngData == nil)
    }
}

/// Bright bed + dark frame — same fixture as NegSwiftEngine `AutocropTests`.
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
        .appendingPathComponent("negswift-native-open-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func localCameraRawPath() -> URL? {
    let keys = ["NEGSWIFT_S14_NEF", "NEGSWIFT_S14_ARW", "NEGSWIFT_S14_RAW"]
    for key in keys {
        guard let path = ProcessInfo.processInfo.environment[key], !path.isEmpty else { continue }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    return nil
}
