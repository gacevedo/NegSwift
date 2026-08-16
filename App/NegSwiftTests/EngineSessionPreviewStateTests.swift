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
}
