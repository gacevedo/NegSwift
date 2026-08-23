//
//  EngineSessionPreviewStateTests.swift
//  NegSwiftTests
//

import AppKit
import Testing
@testable import NegSwift

struct EngineSessionPreviewStateTests {
    @Test @MainActor func isPreviewStaleWhenLoadingMessageSet() {
        let session = EngineSession.preview
        session.setPreviewLoadingMessageForTests("Loading preview…")
        #expect(session.isPreviewStale)
    }

    @Test @MainActor func isPreviewStaleFalseWithoutLoadingMessageWhenPathsMatch() {
        let session = EngineSession.preview
        session.setPreviewLoadingMessageForTests(nil)
        session.setCurrentPathForTests(session.frames[0].path)
        #expect(!session.isPreviewStale)
    }

    @Test @MainActor func memoHitShowsCurrentFrameWithoutSpinner() {
        let session = EngineSession.preview
        let path = session.frames[0].path
        let image = NSImage(size: NSSize(width: 100, height: 80))
        session.storePreviewMemoForTests(path: path, image: image, pixelSize: CGSize(width: 100, height: 80))
        session.setCurrentPathForTests(path)
        session.setPreviewImageForTests(image)
        session.setPreviewLoadingMessageForTests(nil)
        #expect(!session.isPreviewStale)
        #expect(session.previewMemoHitForTests(path: path))
    }

    @Test @MainActor func defersSelectedThumbnailWhilePreviewStale() {
        let session = EngineSession.preview
        let path = session.frames[0].path
        session.setCurrentPathForTests(nil)
        #expect(session.isPreviewStale)
        #expect(session.defersThumbnailLoadToPreviewForTests(path: path))
    }

    @Test @MainActor func isPreviewStaleWhenSelectedPathDiffersFromCurrent() {
        let session = EngineSession.preview
        session.setCurrentPathForTests(session.frames[0].path)
        session.setFilmStripSelectionForTests(primary: session.frames[1].id, ids: [session.frames[1].id])
        #expect(session.isPreviewStale)
    }

    @Test @MainActor func thumbnailInterimPreviewIsNotStale() {
        let session = EngineSession.preview
        let path = session.frames[1].path
        let thumbnail = NSImage(size: NSSize(width: 56, height: 42))
        session.setFramesForTests([
            session.frames[0],
            ScanFrame(
                id: session.frames[1].id,
                url: session.frames[1].url,
                path: path,
                name: session.frames[1].name,
                thumbnail: thumbnail
            ),
        ])
        session.setFilmStripSelectionForTests(primary: session.frames[1].id, ids: [session.frames[1].id])
        session.setPreviewImageForTests(thumbnail)
        session.setCurrentPathForTests(path)
        #expect(!session.isPreviewStale)
    }

    @Test @MainActor func doesNotDeferThumbnailForNonSelectedFrame() {
        let session = EngineSession.preview
        session.setCurrentPathForTests(nil)
        let otherPath = "/tmp/other-scan.tif"
        #expect(!session.defersThumbnailLoadToPreviewForTests(path: otherPath))
    }
}
