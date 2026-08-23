//
//  EngineSessionPreviewMemoTests.swift
//  NegSwiftTests
//

import AppKit
import Testing
@testable import NegSwift

struct EngineSessionPreviewMemoTests {
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8BQz0AEYBxVSF+FABJ0" +
        "Afin5QAAAABJRU5ErkJggg=="

    @MainActor
    private func makeTwoFrameSession() -> EngineSession {
        let session = EngineSession.preview
        let thumb = NSImage(size: NSSize(width: 56, height: 42))
        let frames = session.frames.map { frame in
            ScanFrame(
                id: frame.id,
                url: frame.url,
                path: frame.path,
                name: frame.name,
                thumbnail: thumb
            )
        }
        session.setFramesForTests(frames)
        session.setFilmStripSelectionForTests(primary: frames[0].id, ids: [frames[0].id])
        session.setFrameEditForTests(path: frames[0].path, edit: FrameEditState())
        session.setFrameEditForTests(path: frames[1].path, edit: FrameEditState())
        session.setHasSidecarForTests(path: frames[0].path)
        session.setHasSidecarForTests(path: frames[1].path)
        session.clearRenderTestHandlerForTests()
        return session
    }

    private func mockRenderResult() -> RenderResult {
        RenderResult(
            width: 100,
            height: 80,
            previewFormat: PreviewTransportFormat.png.rawValue,
            pngBase64: Self.tinyPNGBase64,
            jpegBase64: nil,
            metrics: nil
        )
    }

    @Test @MainActor func selectFrameRevisitSkipsCanvasRenderOnMemoHit() async {
        let session = makeTwoFrameSession()
        let frameA = session.frames[0]
        let frameB = session.frames[1]
        let preview = NSImage(size: NSSize(width: 100, height: 80))
        session.storePreviewMemoForTests(
            path: frameA.path,
            image: preview,
            pixelSize: CGSize(width: 100, height: 80)
        )
        session.setRenderTestHandlerForTests { [mockRenderResult] _ in mockRenderResult() }

        await session.selectFrame(frameB.id)
        #expect(session.canvasRenderTestRecordsForTests.count == 1)
        #expect(session.canvasRenderTestRecordsForTests.first?.path == frameB.path)

        await session.selectFrame(frameA.id)
        #expect(session.canvasRenderTestRecordsForTests.count == 1)
        #expect(session.previewMemoHitForTests(path: frameA.path))
        #expect(session.currentPath == frameA.path)
        #expect(!session.isPreviewStale)
    }

    @Test @MainActor func selectFrameRevisitRendersWhenMemoInvalidated() async {
        let session = makeTwoFrameSession()
        let frameA = session.frames[0]
        let frameB = session.frames[1]
        let preview = NSImage(size: NSSize(width: 100, height: 80))
        session.storePreviewMemoForTests(
            path: frameA.path,
            image: preview,
            pixelSize: CGSize(width: 100, height: 80)
        )
        session.setRenderTestHandlerForTests { [mockRenderResult] _ in mockRenderResult() }

        await session.selectFrame(frameB.id)
        session.setFrameEditForTests(path: frameA.path, edit: FrameEditState(density: 1.25))
        await session.selectFrame(frameA.id)

        let canvasPaths = session.canvasRenderTestRecordsForTests.map(\.path)
        #expect(canvasPaths == [frameB.path, frameA.path])
    }
}
