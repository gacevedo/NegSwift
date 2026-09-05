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
}
