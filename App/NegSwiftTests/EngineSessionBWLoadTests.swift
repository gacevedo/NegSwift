//
//  EngineSessionBWLoadTests.swift
//  NegSwiftTests
//

import AppKit
import Foundation
import Testing
@testable import NegSwift

/// End-to-end load path: autodetect B&W → canvas preview → strip thumbnails without
/// cancelling the in-flight preview on the engine worker.
struct EngineSessionBWLoadTests {
    @Test @MainActor func loadBWScanPreviewCompletesWithAutodetect() async throws {
        guard try Self.engineAvailable() else { return }

        let scan = try Self.makeBWScanURL()
        defer { try? FileManager.default.removeItem(at: scan) }

        let preferences = AppPreferences()
        preferences.autodetectProcessMode = true
        preferences.preferGPU = false
        let session = EngineSession(preferences: preferences)
        await session.start()
        await session.importFile(at: scan)

        #expect(session.currentEdit.processMode == .bw)
        #expect(session.previewImage != nil)
        #expect(session.currentPath == scan.path)
        #expect(!session.isPreviewStale)
        #expect(session.previewError == nil)

        await session.stop()
    }

    @Test @MainActor func loadBWScanPreviewSurvivesStripThumbnailLoad() async throws {
        guard try Self.engineAvailable() else { return }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-bw-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = try Self.makeBWScanURL(in: folder, name: "frame-a.tif")
        _ = try Self.makeBWScanURL(in: folder, name: "frame-b.tif")
        defer { try? FileManager.default.removeItem(at: folder) }

        let preferences = AppPreferences()
        preferences.autodetectProcessMode = true
        preferences.preferGPU = false
        let session = EngineSession(preferences: preferences)
        await session.start()
        await session.importFolder(at: folder)
        await session.runThumbnailLoadingForTests()

        #expect(session.frames.count == 2)
        #expect(session.currentEdit.processMode == .bw)
        #expect(session.previewImage != nil)
        #expect(session.currentPath == first.path)
        #expect(!session.isPreviewStale)
        #expect(session.previewError == nil)
        #expect(session.frames[0].thumbnail != nil)

        await session.stop()
    }

    private static func engineAvailable() throws -> Bool {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return false
        }
        return true
    }

    /// Monochrome RGB TIFF — same shape as ``Engine/tests/test_detect.py::_write_bw_tiff``.
    private static func makeBWScanURL(in directory: URL? = nil, name: String? = nil) throws -> URL {
        let fileName = name ?? "bw-\(UUID().uuidString).tif"
        let url = (directory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(fileName)
        let engineRoot = try EngineLocator.executableURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let python = engineRoot.appendingPathComponent("bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw NSError(domain: "EngineSessionBWLoadTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Engine venv python missing at \(python.path)",
            ])
        }
        let script = """
        import numpy as np, tifffile
        gray = np.linspace(0.1, 0.9, 128 * 128, dtype=np.float32).reshape(128, 128)
        rgb = np.stack([gray, gray, gray], axis=-1)
        tifffile.imwrite('\(url.path)', (rgb * 65535).astype(np.uint16), photometric='rgb')
        """
        let proc = Process()
        proc.executableURL = python
        proc.arguments = ["-c", script]
        proc.currentDirectoryURL = engineRoot
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "EngineSessionBWLoadTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to write B&W sample scan (exit \(proc.terminationStatus))",
            ])
        }
        return url
    }
}
