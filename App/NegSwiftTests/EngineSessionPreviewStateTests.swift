//
//  EngineSessionPreviewStateTests.swift
//  NegSwiftTests
//

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
}
