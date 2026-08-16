//
//  ImportDropResolverTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct ImportDropResolverTests {
    @Test func emptyDropIsUnsupported() {
        if case .unsupported = ImportDropResolver.action(for: []) {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unsupported action")
        }
    }

    @Test func singleDirectoryIsFolderImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("negSwift-drop-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let action = ImportDropResolver.action(for: [folder])
        guard case let .folder(url) = action else {
            Issue.record("Expected folder action")
            return
        }
        #expect(url.path == folder.standardizedFileURL.path)
    }

    @Test func singleFileIsSingleImport() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("negSwift-drop.tif")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let action = ImportDropResolver.action(for: [file])
        guard case let .singleFile(url) = action else {
            Issue.record("Expected singleFile action")
            return
        }
        #expect(url.path == file.standardizedFileURL.path)
    }

    @Test func multipleFilesAreBatchImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("negSwift-drop-files", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let b = dir.appendingPathComponent("b.tif")
        let a = dir.appendingPathComponent("a.tif")
        try Data().write(to: b)
        try Data().write(to: a)

        let action = ImportDropResolver.action(for: [b, a])
        guard case let .multipleFiles(urls) = action else {
            Issue.record("Expected multipleFiles action")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["a.tif", "b.tif"])
    }

    @Test func mixedFolderAndFileIsUnsupported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("negSwift-drop-mix", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("scan.tif")
        try Data().write(to: file)

        if case .unsupported = ImportDropResolver.action(for: [dir, file]) {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unsupported action")
        }
    }
}
