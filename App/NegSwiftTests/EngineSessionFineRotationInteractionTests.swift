import AppKit
import Testing
@testable import NegSwift

struct EngineSessionFineRotationInteractionTests {
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
        session.setCurrentPathForTests(frames[0].path)
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
        return session
    }

    @Test @MainActor func fineRotationDragPassesMeteringAnchor() async {
        let session = makeSession()
        let path = session.frames[0].path

        session.beginFineRotationInteraction()
        session.setFineRotation(2.5)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        let duringDrag = session.canvasRenderTestRecordsForTests
        #expect(duringDrag.contains { $0.meteringAnchorFineRotation == 0 })

        session.endFineRotationInteraction()
        await Task.yield()

        let settled = session.canvasRenderTestRecordsForTests.last
        #expect(settled?.meteringAnchorFineRotation == nil)
        #expect(session.frameEdits[path]?.fineRotation == 2.5)
    }

    @Test @MainActor func rotationGuideShowsDuringInteractionAndHidesAfterLinger() async {
        let session = makeSession()
        session.setRotationGuideLingerDurationForTests(.milliseconds(50))

        #expect(session.showRotationGuide == false)
        session.beginFineRotationInteraction()
        #expect(session.showRotationGuide == true)

        session.setFineRotation(1.0)
        #expect(session.showRotationGuide == true)

        session.endFineRotationInteraction()
        #expect(session.showRotationGuide == true)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(session.showRotationGuide == false)
    }
}
