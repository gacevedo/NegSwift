//
//  EngineSessionAdjustmentsTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct EngineSessionAdjustmentsTests {
    @Test @MainActor func framePathsWithAdjustmentsIncludesDirtyPaths() {
        let session = EngineSession.preview
        session.setDirtyPathsForTests(["/preview/b.tif"])
        let paths = session.framePathsWithAdjustments()
        #expect(paths == ["/preview/b.tif"])
    }

    @Test @MainActor func framePathsWithAdjustmentsIncludesSidecarOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negSwift-adjust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let scanPath = folder.appendingPathComponent("frame.tif").path
        let session = EngineSession.preview
        session.setFramesForTests([
            ScanFrame(
                id: UUID(),
                url: URL(fileURLWithPath: scanPath),
                path: scanPath,
                name: "frame.tif"
            ),
        ])
        session.setDirtyPathsForTests([])

        let sidecar = SidecarLocator.url(forScanPath: scanPath)
        try "{}".write(to: sidecar, atomically: true, encoding: .utf8)

        let paths = session.framePathsWithAdjustments()
        #expect(paths == [scanPath])
    }
}
