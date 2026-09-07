import AppKit
import Testing
@testable import NegSwift
import NegSwiftEngine

struct EngineSessionProgressivePreviewTests {
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8BQz0AEYBxVSF+FABJ0" +
        "Afin5QAAAABJRU5ErkJggg=="

    @MainActor
    private func makeSession() -> EngineSession {
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
        session.setProgressiveFirstPaintForTests(true)
        session.clearRenderTestHandlerForTests()
        return session
    }

    @Test @MainActor func firstSelectPaintsDraftThenSettled() async {
        let session = makeSession()
        let frameB = session.frames[1]
        session.setRenderTestHandlerForTests { record in
            let edge = record.longEdgePx ?? 0
            return RenderResult(
                width: edge,
                height: 40,
                previewFormat: PreviewTransportFormat.png.rawValue,
                pngBase64: Self.tinyPNGBase64,
                jpegBase64: nil,
                metrics: nil
            )
        }

        await session.selectFrame(frameB.id)

        let canvas = session.canvasRenderTestRecordsForTests
        #expect(canvas.count == 2)
        #expect(canvas[0].draftPreview)
        #expect(canvas[0].longEdgePx == PreviewPass.draftLongEdge)
        #expect(!canvas[1].draftPreview)
        #expect(canvas[1].longEdgePx == session.previewSettingsForTests.longEdgePx)
        #expect(session.isPreviewSettled)
        #expect(!session.isPreviewDraft)
        #expect(!session.isPreviewStale)
    }

    @Test @MainActor func sliderReprintSkipsDraft() async {
        let session = makeSession()
        let frameA = session.frames[0]
        session.setCurrentPathForTests(frameA.path)
        session.setPreviewSettledForTests(true)
        session.setRenderTestHandlerForTests { _ in
            RenderResult(
                width: 100,
                height: 80,
                previewFormat: PreviewTransportFormat.png.rawValue,
                pngBase64: Self.tinyPNGBase64,
                jpegBase64: nil,
                metrics: nil
            )
        }

        await session.refreshPreviewNowForTests()

        let canvas = session.canvasRenderTestRecordsForTests
        #expect(canvas.count == 1)
        #expect(!canvas[0].draftPreview)
        #expect(canvas[0].longEdgePx == session.previewSettingsForTests.longEdgePx)
    }

    @Test @MainActor func processedDraftIsNotStale() {
        let session = makeSession()
        let path = session.frames[0].path
        session.setCurrentPathForTests(path)
        session.setPreviewImageForTests(NSImage(size: NSSize(width: 64, height: 48)))
        session.setPreviewDraftForTests(true)
        #expect(session.isPreviewDraft)
        #expect(!session.isPreviewSettled)
        #expect(!session.isPreviewStale)
    }
}
