//
//  EngineLocatorTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct EngineLocatorTests {
    @Test func bundledRelativePathIsStable() {
        #expect(EngineLocator.bundledRelativePath == "engine/negswift-engine")
    }

    @Test func workingDirectoryForVenvBin() {
        let exe = URL(fileURLWithPath: "/proj/Engine/.venv/bin/negswift-engine")
        let cwd = EngineProcess.workingDirectory(for: exe)
        #expect(cwd.path.hasSuffix(".venv"))
    }

    @Test func workingDirectoryForBundledEngine() {
        let exe = URL(fileURLWithPath: "/App.app/Contents/Resources/engine/negswift-engine")
        let cwd = EngineProcess.workingDirectory(for: exe)
        #expect(cwd.path.hasSuffix("engine"))
    }

    @Test func negpyUserDirectoryUnderApplicationSupport() {
        let dir = EngineProcess.negpyUserDirectory()
        #expect(dir.path.contains("Application Support"))
        #expect(dir.lastPathComponent == "NegSwift")
    }
}
