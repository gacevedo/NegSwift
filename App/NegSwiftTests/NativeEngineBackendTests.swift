//
//  NativeEngineBackendTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

private let sampleTIFFPath = "/Users/gacevedo/Development/NegSwift/App/NegSwiftUITests/Fixtures/sample.tif"

@Suite(.serialized)
struct NativeEngineBackendTests {
    @Test func infoReportsSwiftDecode() async throws {
        let backend = NativeEngineBackend()
        let info = try await backend.info()
        #expect(info.negpyVersion == "s2-log-normalize")
        #expect(info.gpuBackend == "swift")
        #expect(info.gpuAvailable == false)
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
