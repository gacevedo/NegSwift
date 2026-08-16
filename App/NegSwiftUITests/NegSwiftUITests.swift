//
//  NegSwiftUITests.swift
//  NegSwiftUITests
//

import XCTest

final class NegSwiftUITests: NegSwiftUITestCase {

    @MainActor
    func testLaunchShowsMainWindow() throws {
        try waitForEngineReady()
        XCTAssertTrue(app.buttons[AccessibilityID.openFolder].exists)
        XCTAssertTrue(app.buttons[AccessibilityID.openFile].exists)
    }
}
