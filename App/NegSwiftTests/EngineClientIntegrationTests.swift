//
//  EngineClientIntegrationTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NegSwift

struct EngineClientIntegrationTests {
    @Test func infoRoundTripAgainstDevEngine() async throws {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return
        }

        let client = EngineClient()
        let info = try await client.info()
        #expect(!info.negswiftVersion.isEmpty)
        #expect(!info.negpyVersion.isEmpty)
        try await client.ping()
        await client.stop()
    }

    @Test func renderReturnsValidPNG() async throws {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return
        }

        let scan = try Self.makeSampleScanURL()
        defer { try? FileManager.default.removeItem(at: scan) }

        let client = EngineClient()
        let result = try await client.render(path: scan.path, preferGPU: false, cropPreviewFull: true)
        guard let data = Data(base64Encoded: result.pngBase64) else {
            Issue.record("render returned invalid base64")
            await client.stop()
            return
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("render PNG failed ImageIO decode (CRC/truncation)")
            await client.stop()
            return
        }
        #expect(image.width == result.width)
        #expect(image.height == result.height)
        await client.stop()
    }

    private static func makeSampleScanURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-test-\(UUID().uuidString).tif")
        let engineRoot = try EngineLocator.executableURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let python = engineRoot.appendingPathComponent("bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw NSError(domain: "EngineClientIntegrationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Engine venv python missing at \(python.path)",
            ])
        }
        let script = """
        import numpy as np, tifffile
        rgb = np.zeros((64, 96, 3), dtype=np.uint16)
        rgb[:, :, 0] = 40000
        rgb[:, :, 1] = 20000
        rgb[:, :, 2] = 10000
        tifffile.imwrite('\(url.path)', rgb, photometric='rgb')
        """
        let proc = Process()
        proc.executableURL = python
        proc.arguments = ["-c", script]
        proc.currentDirectoryURL = engineRoot
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "EngineClientIntegrationTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to write sample scan (exit \(proc.terminationStatus))",
            ])
        }
        return url
    }
}
