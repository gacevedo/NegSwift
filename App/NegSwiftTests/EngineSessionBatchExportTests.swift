//
//  EngineSessionBatchExportTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct EngineSessionBatchExportTests {
    @MainActor
    private func makeSessionWithFrames(_ count: Int) -> EngineSession {
        let session = EngineSession.preview
        let frames = (0 ..< count).map { index in
            ScanFrame(
                id: UUID(),
                url: URL(fileURLWithPath: "/batch/frame\(index).tif"),
                path: "/batch/frame\(index).tif",
                name: "frame\(index).tif"
            )
        }
        session.setFramesForTests(frames)
        session.setFilmStripSelectionForTests(primary: frames[0].id, ids: [frames[0].id])
        session.clearExportTestHandlerForTests()
        return session
    }

    private func mockResult(for record: EngineExportCallRecord) -> ExportResult {
        ExportResult(
            outputPath: "/tmp/out/\(record.path).jpg",
            width: 100,
            height: 80,
            format: "JPEG"
        )
    }

    @Test @MainActor func exportBatchAllScopeCallsExportPerFrameInStripOrder() async throws {
        let session = makeSessionWithFrames(3)
        session.setFrameEditForTests(path: "/batch/frame0.tif", edit: FrameEditState(density: 1.1))
        session.setFrameEditForTests(path: "/batch/frame1.tif", edit: FrameEditState(density: 1.2))
        session.setFrameEditForTests(path: "/batch/frame2.tif", edit: FrameEditState(density: 1.3))
        session.setExportTestHandlerForTests { [mockResult] record in mockResult(record) }

        let destination = URL(fileURLWithPath: "/tmp/NegSwiftBatchExportTests")
        let results = try await session.exportBatch(
            scope: .all,
            to: destination,
            settings: .quickExport
        )

        #expect(results.count == 3)
        #expect(session.exportTestRecordsForTests.map(\.path) == [
            "/batch/frame0.tif",
            "/batch/frame1.tif",
            "/batch/frame2.tif",
        ])
        #expect(session.exportTestRecordsForTests.map(\.config.density) == [1.1, 1.2, 1.3])
    }

    @Test @MainActor func exportBatchSelectedScopeUsesOnlySelectedFrames() async throws {
        let session = makeSessionWithFrames(3)
        let frames = session.frames
        session.setFilmStripSelectionForTests(
            primary: frames[0].id,
            ids: [frames[0].id, frames[2].id]
        )
        session.setExportTestHandlerForTests { [mockResult] record in mockResult(record) }

        let destination = URL(fileURLWithPath: "/tmp/NegSwiftBatchExportTests")
        let results = try await session.exportBatch(
            scope: .selected,
            to: destination,
            settings: .quickExport
        )

        #expect(results.count == 2)
        #expect(session.exportTestRecordsForTests.map(\.path) == [
            "/batch/frame0.tif",
            "/batch/frame2.tif",
        ])
    }

    @Test @MainActor func exportBatchCancelStopsAfterCurrentFrame() async throws {
        let session = makeSessionWithFrames(3)
        session.setExportTestHandlerForTests { [mockResult] record in
            if record.path != "/batch/frame0.tif" {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            return mockResult(record)
        }

        let destination = URL(fileURLWithPath: "/tmp/NegSwiftBatchExportTests")
        let exportTask = Task {
            try await session.exportBatch(scope: .all, to: destination, settings: .quickExport)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        session.cancelExport()

        do {
            _ = try await exportTask.value
            Issue.record("Expected batch export to cancel")
        } catch is CancellationError {
            #expect(session.exportTestRecordsForTests.count >= 1)
            #expect(session.exportTestRecordsForTests.count <= 2)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!session.isExporting)
    }

    @Test @MainActor func exportBatchBlocksFrameSelectionWhileRunning() async throws {
        let session = makeSessionWithFrames(2)
        let secondID = session.frames[1].id
        session.setExportTestHandlerForTests { record in
            try await Task.sleep(nanoseconds: 200_000_000)
            return ExportResult(
                outputPath: "/tmp/out/\(record.path).jpg",
                width: 10,
                height: 10,
                format: "JPEG"
            )
        }

        let destination = URL(fileURLWithPath: "/tmp/NegSwiftBatchExportTests")
        let exportTask = Task {
            try await session.exportBatch(scope: .all, to: destination, settings: .quickExport)
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(session.isExporting)
        await session.selectFrame(secondID)
        #expect(session.selectedFrameID == session.frames[0].id)

        _ = try await exportTask.value
        #expect(!session.isExporting)
    }

    @Test @MainActor func exportBatchClearsProgressWhenFinished() async throws {
        let session = makeSessionWithFrames(2)
        session.setExportTestHandlerForTests { [mockResult] record in mockResult(record) }

        let destination = URL(fileURLWithPath: "/tmp/NegSwiftBatchExportTests")
        _ = try await session.exportBatch(scope: .all, to: destination, settings: .quickExport)

        #expect(!session.isExporting)
        #expect(session.batchExportProgress == nil)
        #expect(session.activeExportSettings == nil)
    }
}
