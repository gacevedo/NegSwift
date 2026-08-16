//
//  NegSwiftUITestsLaunchTests.swift
//  NegSwiftUITests
//

import XCTest

final class NegSwiftUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        if FileManager.default.isExecutableFile(atPath: NegSwiftUITestCase.engineExecutablePath) {
            app.launchEnvironment["NEGSWIFT_ENGINE"] = NegSwiftUITestCase.engineExecutablePath
        }
        app.launchArguments.append(UITestLaunch.launchArgument)
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
