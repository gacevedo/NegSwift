//
//  NativeEngineBackendTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

@Suite(.serialized)
struct NativeEngineBackendTests {
    @Test func infoReportsSwiftStub() async throws {
        let backend = NativeEngineBackend()
        let info = try await backend.info()
        #expect(info.negpyVersion == "s0-stub")
        #expect(info.gpuBackend == "swift")
        #expect(info.gpuAvailable == false)
    }

    @Test func stubRenderReturnsJPEG() async throws {
        let backend = NativeEngineBackend()
        let result = try await backend.render(
            path: "/tmp/missing.tif",
            longEdgePx: 64,
            preferGPU: false,
            config: nil,
            cropPreviewFull: false,
            stripThumbnail: false,
            previewFormat: .jpeg,
            jpegQuality: 90
        )
        #expect(result.width == 64)
        #expect(result.height == 64)
        #expect(result.imageData != nil)
        #expect(!(result.imageData?.isEmpty ?? true))
    }

    @Test func factoryDefaultIsPython() {
        let backend = EngineBackendFactory.make(.python)
        #expect(backend is PythonEngineBackend)
    }
}
