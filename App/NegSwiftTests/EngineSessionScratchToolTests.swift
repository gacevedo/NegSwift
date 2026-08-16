//
//  EngineSessionScratchToolTests.swift
//  NegSwiftTests
//

import AppKit
import CoreGraphics
import Testing
@testable import NegSwift

struct EngineSessionScratchToolTests {
    @Test @MainActor func scratchToolActivatesAndClearsInProgressOnDeactivate() {
        let session = EngineSession.preview
        session.setPreviewImageForTests(NSImage(size: NSSize(width: 100, height: 80)))

        session.setScratchToolActive(true)
        #expect(session.isScratchToolActive)
        session.appendScratchInProgressPoint(CGPoint(x: 0.2, y: 0.3))
        #expect(session.scratchInProgressPoints.count == 1)

        session.setScratchToolActive(false)
        #expect(!session.isScratchToolActive)
        #expect(session.scratchInProgressPoints.isEmpty)
    }

    @Test @MainActor func scratchToolDeactivatesCropTool() {
        let session = EngineSession.preview
        session.setPreviewImageForTests(NSImage(size: NSSize(width: 100, height: 80)))

        session.setCropToolActive(true)
        #expect(session.isCropToolActive)

        session.setScratchToolActive(true)
        #expect(session.isScratchToolActive)
        #expect(!session.isCropToolActive)
    }

    @Test @MainActor func cropToolDeactivatesScratchTool() {
        let session = EngineSession.preview
        session.setPreviewImageForTests(NSImage(size: NSSize(width: 100, height: 80)))

        session.setScratchToolActive(true)
        session.appendScratchInProgressPoint(CGPoint(x: 0.5, y: 0.5))

        session.setCropToolActive(true)
        #expect(session.isCropToolActive)
        #expect(!session.isScratchToolActive)
        #expect(session.scratchInProgressPoints.isEmpty)
    }

    @Test @MainActor func appendAndRemoveScratchPointsUpdatesRevision() {
        let session = EngineSession.preview
        session.setScratchToolActive(true)

        let revision0 = session.scratchInteractionRevision
        session.appendScratchInProgressPoint(CGPoint(x: 0.1, y: 0.2))
        #expect(session.scratchInteractionRevision == revision0 + 1)

        session.appendScratchInProgressPoint(CGPoint(x: 0.3, y: 0.4))
        #expect(session.scratchInProgressPoints.count == 2)

        let revision1 = session.scratchInteractionRevision
        session.removeLastScratchInProgressPoint()
        #expect(session.scratchInProgressPoints.count == 1)
        #expect(session.scratchInteractionRevision == revision1 + 1)

        session.clearScratchInProgressPoints()
        #expect(session.scratchInProgressPoints.isEmpty)
    }

    @Test @MainActor func escapeClearsPointsBeforeDeactivatingTool() {
        let session = EngineSession.preview
        session.setScratchToolActive(true)
        session.appendScratchInProgressPoint(CGPoint(x: 0.2, y: 0.2))

        session.handleScratchEscape()
        #expect(session.isScratchToolActive)
        #expect(session.scratchInProgressPoints.isEmpty)

        session.handleScratchEscape()
        #expect(!session.isScratchToolActive)
    }

    @Test @MainActor func finishScratchInProgressWithNoPointsIsNoOp() async {
        let session = EngineSession.preview
        session.setScratchToolActive(true)

        await session.finishScratchInProgress()
        #expect(session.scratchInProgressPoints.isEmpty)
        #expect(!session.currentEdit.hasHealStrokes)
    }
}
