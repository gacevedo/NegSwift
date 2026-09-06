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

    @Test func renderReturnsValidJPEG() async throws {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return
        }

        let scan = try Self.makeSampleScanURL()
        defer { try? FileManager.default.removeItem(at: scan) }

        let client = EngineClient()
        let result = try await client.render(
            path: scan.path,
            preferGPU: false,
            cropPreviewFull: true,
            previewFormat: .jpeg
        )
        guard let data = result.imageData else {
            Issue.record("render returned invalid base64")
            await client.stop()
            return
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("render JPEG failed ImageIO decode")
            await client.stop()
            return
        }
        #expect(result.previewFormat == PreviewTransportFormat.jpeg.rawValue)
        #expect(image.width == result.width)
        #expect(image.height == result.height)
        await client.stop()
    }

    @Test func renderReturnsValidPNGWhenRequested() async throws {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return
        }

        let scan = try Self.makeSampleScanURL()
        defer { try? FileManager.default.removeItem(at: scan) }

        let client = EngineClient()
        let result = try await client.render(
            path: scan.path,
            preferGPU: false,
            cropPreviewFull: true,
            previewFormat: .png
        )
        guard let data = result.pngData else {
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
        #expect(result.previewFormat == PreviewTransportFormat.png.rawValue)
        #expect(image.width == result.width)
        #expect(image.height == result.height)
        await client.stop()
    }

    @Test func healStrokeAppendAndUndoRoundTrip() async throws {
        let executable = try EngineLocator.executableURL()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Issue.record("Dev engine not found at \(executable.path). Run `cd Engine && uv sync`.")
            return
        }

        let scan = try Self.makeSampleScanURL()
        defer { try? FileManager.default.removeItem(at: scan) }

        let client = EngineClient()
        var config = FrameEditState()
        let append = try await client.appendHealStroke(
            path: scan.path,
            points: [[0.25, 0.5], [0.75, 0.5]],
            brushSize: 6,
            config: config
        )
        #expect(append.manualHealStrokes.count == 1)
        #expect(append.strokeIndex == 0)

        config.manualHealStrokes = append.manualHealStrokes
        let undo = try await client.undoLastHeal(path: scan.path, config: config)
        #expect(undo.removed != nil)
        #expect(undo.manualHealStrokes.isEmpty)
        await client.stop()
    }

    private static func makeSampleScanURL() throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-test-\(UUID().uuidString).tif")
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NegSwiftUITests/Fixtures/sample.tif")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw NSError(domain: "EngineClientIntegrationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "sample.tif fixture missing at \(fixture.path)",
            ])
        }
        try FileManager.default.copyItem(at: fixture, to: dest)
        return dest
    }
}
