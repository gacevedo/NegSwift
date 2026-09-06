//
//  NativeEngineBackendTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift
import NegSwiftEngine

private let sampleTIFFPath = "/Users/gacevedo/Development/NegSwift/App/NegSwiftUITests/Fixtures/sample.tif"

@Suite(.serialized)
struct NativeEngineBackendTests {
    @Test func infoReportsSwiftDecode() async throws {
        let backend = NativeEngineBackend()
        let info = try await backend.info()
        #expect(info.negpyVersion == "s10b-optical-dust")
        #expect(info.gpuBackend == "swift")
        #expect(info.gpuAvailable == false)
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

    @Test func normalizedRenderReturnsJPEG() async throws {
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
        #expect(result.imageData != nil)
        #expect(!(result.imageData?.isEmpty ?? true))
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

    @Test func factoryDefaultIsPython() {
        let backend = EngineBackendFactory.make(.python)
        #expect(backend is PythonEngineBackend)
    }

    @Test func factoryMakesSwiftBackend() {
        let backend = EngineBackendFactory.make(.swift)
        #expect(backend is NativeEngineBackend)
    }

    @Test func openReportsSourceDimensions() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.open(path: sampleTIFFPath, includeSplash: false, config: nil)
        #expect(result.width > 0)
        #expect(result.height > 0)
        #expect(result.path == sampleTIFFPath)
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
            export: .quickExport,
            preferGPU: false
        )
        #expect(result.width > 0)
        #expect(result.height > 0)
        #expect(result.format == "JPEG")
        #expect(FileManager.default.fileExists(atPath: result.outputPath))
        #expect(result.outputPath.hasSuffix(".jpg"))
    }

    @Test func exportAppliesCropAndShrinksPixels() async throws {
        let backend = NativeEngineBackend()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-be-crop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        let full = try await backend.export(
            path: sampleTIFFPath,
            destDir: dest.appendingPathComponent("full").path,
            config: FrameEditState(),
            export: .quickExport,
            preferGPU: false
        )
        var cropped = FrameEditState()
        cropped.manualCropRect = NormalizedRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        cropped.cropFromAuto = false
        let cut = try await backend.export(
            path: sampleTIFFPath,
            destDir: dest.appendingPathComponent("crop").path,
            config: cropped,
            export: .quickExport,
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

    @Test func normalizedRenderReturnsPNG() async throws {
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
        #expect(result.previewFormat == PreviewTransportFormat.png.rawValue)
        #expect(result.pngData != nil)
        #expect(!(result.pngData?.isEmpty ?? true))
    }
}
