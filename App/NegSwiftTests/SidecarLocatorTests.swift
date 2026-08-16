//
//  SidecarLocatorTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct SidecarLocatorTests {
    @Test func sidecarURLMatchesNegPyConvention() {
        let url = SidecarLocator.url(forScanPath: "/rolls/scan_001.tif")
        #expect(url.path == "/rolls/scan_001.negpy")
    }

    @Test func existsReflectsFileOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negSwift-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let scanPath = folder.appendingPathComponent("frame.tif").path
        #expect(!SidecarLocator.exists(forScanPath: scanPath))

        let sidecar = SidecarLocator.url(forScanPath: scanPath)
        try "{}".write(to: sidecar, atomically: true, encoding: .utf8)
        #expect(SidecarLocator.exists(forScanPath: scanPath))
    }
}
