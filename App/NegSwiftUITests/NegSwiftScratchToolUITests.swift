//
//  NegSwiftScratchToolUITests.swift
//  NegSwiftUITests
//

import CoreGraphics
import XCTest

final class NegSwiftScratchToolUITests: NegSwiftUITestCase {

    /// XCUITest cannot reliably click through the NSView scratch overlay; seed points via launch hook.
    private let twoPointSeed = [
        CGPoint(x: 0.35, y: 0.5),
        CGPoint(x: 0.65, y: 0.5),
    ]

    func testScratchToolToggleShowsControls() throws {
        relaunch(importPath: Self.fixtureScanURL.path)
        try waitForEngineReady()
        try waitForImportComplete()

        try setScratchToolActive(true)
        XCTAssertTrue(scratchToolToggle().exists)

        try setScratchToolActive(false)
        XCTAssertTrue(
            app.staticTexts["Turn on Scratch Tool, then click along scratches or hairs on the preview."]
                .waitForExistence(timeout: 5)
        )
    }

    func testScratchToolShiftShortcutToggles() throws {
        relaunch(importPath: Self.fixtureScanURL.path)
        try waitForEngineReady()
        try waitForImportComplete()

        app.typeKey("s", modifierFlags: [.shift])
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.scratchBrushSize)
                .firstMatch
                .waitForExistence(timeout: 10)
        )

        app.typeKey("s", modifierFlags: [.shift])
        XCTAssertTrue(
            app.staticTexts["Turn on Scratch Tool, then click along scratches or hairs on the preview."]
                .waitForExistence(timeout: 10)
        )
    }

    func testScratchPolylineFinishViaEnter() throws {
        relaunch(importPath: Self.fixtureScanURL.path, scratchSeedPoints: twoPointSeed)
        try waitForEngineReady()
        try waitForImportComplete()

        try setScratchToolActive(true)
        try waitForScratchPointCount(2)

        let canvas = try previewCanvas()
        canvas.click()
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        try waitForScratchUndoHeal()
    }

    func testScratchPolylineFinishViaSidebarButton() throws {
        relaunch(importPath: Self.fixtureScanURL.path, scratchSeedPoints: twoPointSeed)
        try waitForEngineReady()
        try waitForImportComplete()

        try setScratchToolActive(true)
        try waitForScratchPointCount(2)

        app.buttons[AccessibilityID.scratchFinish].click()
        try waitForScratchUndoHeal()
    }

    func testScratchClearRemovesInProgressPoints() throws {
        relaunch(importPath: Self.fixtureScanURL.path, scratchSeedPoints: [CGPoint(x: 0.5, y: 0.5)])
        try waitForEngineReady()
        try waitForImportComplete()

        try setScratchToolActive(true)
        try waitForScratchPointCount(1)

        app.buttons[AccessibilityID.scratchClear].click()
        XCTAssertFalse(app.staticTexts[AccessibilityID.scratchPointCount].exists)
    }

    func testScratchToolRestoresCursorOverSidebarAtMaxZoom() throws {
        relaunch(importPath: Self.fixtureScanURL.path, canvasZoomToMax: true)
        try waitForEngineReady()
        try waitForImportComplete()
        try waitForCanvasZoomLabel("400%")

        try setScratchToolActive(true)

        let canvas = try previewCanvas()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        try waitForScratchSystemCursor(hidden: true)

        let brushSize = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.scratchBrushSize)
            .firstMatch
        XCTAssertTrue(brushSize.waitForExistence(timeout: 5))
        brushSize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        try waitForScratchSystemCursor(hidden: false)
    }
}
