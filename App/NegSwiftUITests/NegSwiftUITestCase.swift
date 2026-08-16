//
//  NegSwiftUITestCase.swift
//  NegSwiftUITests
//

import XCTest

/// Shared launch configuration for functional UI tests.
///
/// Requires `cd Engine && uv sync` so `NEGSWIFT_ENGINE` resolves to the venv binary.
/// Quit any manually launched NegSwift instance before running UI tests — XCTest spawns its own copy.
class NegSwiftUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        configureLaunchEnvironment()
        app.launchArguments.append(UITestLaunch.launchArgument)
        app.launch()
    }

    func configureLaunchEnvironment() {
        app.launchEnvironment["NEGSWIFT_ENGINE"] = Self.engineExecutablePath
        app.launchEnvironment["NEGSWIFT_UI_TEST_DEFAULTS_SUITE"] = "uitest.\(UUID().uuidString)"
    }

    func relaunch(importPath: String? = nil, dropPaths: [String] = [], exportDir: String? = nil) {
        app.terminate()
        configureLaunchEnvironment()
        if let importPath {
            app.launchEnvironment["NEGSWIFT_UI_TEST_IMPORT"] = importPath
        }
        if !dropPaths.isEmpty {
            app.launchEnvironment["NEGSWIFT_UI_TEST_DROP_PATHS"] = dropPaths.joined(separator: ",")
        }
        if let exportDir {
            app.launchEnvironment["NEGSWIFT_UI_TEST_EXPORT_DIR"] = exportDir
        }
        app.launchArguments.append(UITestLaunch.launchArgument)
        app.launch()
    }

    func waitForEngineReady(timeout: TimeInterval = 90) throws {
        let openFolder = app.buttons[AccessibilityID.openFolder]
        XCTAssertTrue(openFolder.waitForExistence(timeout: timeout), "Open Folder control missing")
        try waitUntilEnabled(openFolder, timeout: timeout, message: "Engine did not become ready")
    }

    func waitForImportComplete(timeout: TimeInterval = 120) throws {
        let quickExport = app.buttons[AccessibilityID.quickExport]
        XCTAssertTrue(quickExport.waitForExistence(timeout: timeout), "Quick Export control missing")
        try waitUntilEnabled(quickExport, timeout: timeout, message: "Import or preview did not finish")
    }

    func waitForPreviewError(timeout: TimeInterval = 30) throws {
        let error = app.staticTexts[AccessibilityID.previewError]
        XCTAssertTrue(error.waitForExistence(timeout: timeout), "Expected preview error message")
    }

    func openSettings() throws {
        let appMenu = app.menuBars.menuBarItems["NegSwift"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5), "App menu missing")
        appMenu.click()
        let settingsItem = app.menuBars.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5), "Settings menu item missing")
        settingsItem.click()

        let settings = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settings)
            .firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings window did not open")
    }

    static var engineExecutablePath: String {
        let candidates = [
            repoRoot.appendingPathComponent("Engine/.venv/bin/negswift-engine"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Engine/.venv/bin/negswift-engine"),
        ]
        for url in candidates {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url.path
            }
        }
        preconditionFailure("negswift-engine not found — run: cd Engine && uv sync")
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NegSwiftUITests
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // repo root
    }

    static var fixtureScanURL: URL {
        let repoFixture = repoRoot.appendingPathComponent("App/NegSwiftUITests/Fixtures/sample.tif")
        if FileManager.default.fileExists(atPath: repoFixture.path) {
            return repoFixture
        }
        if let bundled = Bundle(for: NegSwiftUITestCase.self).url(
            forResource: "sample",
            withExtension: "tif",
            subdirectory: "Fixtures"
        ), FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        preconditionFailure("Fixtures/sample.tif missing — expected at \(repoFixture.path)")
    }

    static func makeTemporaryExportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NegSwiftUITests-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeTemporaryFolder(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NegSwiftUITests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntilEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval,
        message: String
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isEnabled {
                return
            }
            usleep(200_000)
        }
        XCTFail(message)
    }
}

enum UITestLaunch {
    static let launchArgument = "-UITesting"
}

enum AccessibilityID {
    static let openFolder = "negSwift.openFolder"
    static let openFile = "negSwift.openFile"
    static let quickExport = "negSwift.quickExport"
    static let exportSheet = "negSwift.exportSheet"
    static let previewError = "negSwift.previewError"
    static let settings = "negSwift.settings"
    static let prefsPreviewQuality = "negSwift.prefs.previewQuality"
    static let prefsUseGPU = "negSwift.prefs.useGPU"
    static let prefsDataLocation = "negSwift.prefs.dataLocation"
}
