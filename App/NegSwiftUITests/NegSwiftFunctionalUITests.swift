//
//  NegSwiftFunctionalUITests.swift
//  NegSwiftUITests
//

import XCTest

final class NegSwiftFunctionalUITests: NegSwiftUITestCase {

    func testEngineBecomesReady() throws {
        try waitForEngineReady()
    }

    func testImportScanViaLaunchHook() throws {
        relaunch(importPath: Self.fixtureScanURL.path)
        try waitForEngineReady()
        try waitForImportComplete()
    }

    func testQuickExportWritesJPEG() throws {
        let exportDir = try Self.makeTemporaryExportDirectory()
        relaunch(importPath: Self.fixtureScanURL.path, exportDir: exportDir.path)
        try waitForEngineReady()
        try waitForImportComplete()

        app.buttons[AccessibilityID.quickExport].click()
        try waitForExportFile(in: exportDir, extension: "jpg", timeout: 120)
    }

    func testBatchExportAllWritesMultipleJPEGs() throws {
        let scanFolder = try Self.makeTemporaryScanFolder(fileCount: 3)
        let exportDir = try Self.makeTemporaryExportDirectory()
        relaunch(
            importDirectory: scanFolder.path,
            exportDir: exportDir.path,
            batchExportAll: true
        )
        try waitForEngineReady()
        try waitForImportComplete()
        try waitForExportFileCount(in: exportDir, count: 3, extension: "jpg", timeout: 180)
    }

    func testExportSheetOpens() throws {
        relaunch(importPath: Self.fixtureScanURL.path)
        try waitForEngineReady()
        try waitForImportComplete()

        app.buttons[AccessibilityID.exportSheet].click()
        let exportTitle = app.staticTexts["Export"]
        XCTAssertTrue(exportTitle.waitForExistence(timeout: 5))
    }

    func testPreferencesOpenAndShowControls() throws {
        try waitForEngineReady()
        try openSettings()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.prefsPreviewQuality)
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.prefsUseGPU)
                .firstMatch
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.prefsDataLocation)
                .firstMatch
                .exists
        )
    }

    func testDropSingleFileViaLaunchHook() throws {
        relaunch(dropPaths: [Self.fixtureScanURL.path])
        try waitForEngineReady()
        try waitForImportComplete()
    }

    func testDropMixedFolderAndFileShowsError() throws {
        let folder = try Self.makeTemporaryFolder(name: "folder")
        let looseFile = folder.deletingLastPathComponent()
            .appendingPathComponent("NegSwiftUITests-loose-\(UUID().uuidString).tif")
        try FileManager.default.copyItem(at: Self.fixtureScanURL, to: looseFile)
        defer { try? FileManager.default.removeItem(at: looseFile) }

        relaunch(dropPaths: [folder.path, looseFile.path])
        try waitForEngineReady()
        try waitForPreviewError()
    }

    private func waitForExportFile(
        in directory: URL,
        extension ext: String,
        timeout: TimeInterval
    ) throws {
        try waitForExportFileCount(in: directory, count: 1, extension: ext, timeout: timeout)
    }

    private func waitForExportFileCount(
        in directory: URL,
        count: Int,
        extension ext: String,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let matches = files.filter { $0.pathExtension.lowercased() == ext }
                if matches.count >= count {
                    return
                }
            }
            usleep(500_000)
        }
        XCTFail("Expected \(count) .\(ext) export(s) in \(directory.path)")
    }
}
