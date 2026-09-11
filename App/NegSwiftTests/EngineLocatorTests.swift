//
//  EngineLocatorTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct EngineLocatorTests {
#if NEGSWIFT_ENGINE_PYTHON
    @Test func workingDirectoryForVenvBin() {
        let exe = URL(fileURLWithPath: "/proj/Engine/.venv/bin/negswift-engine")
        let cwd = EngineProcess.workingDirectory(for: exe)
        #expect(cwd.path.hasSuffix(".venv"))
    }
#endif

    @Test func negpyUserDirectoryUnderApplicationSupport() {
        let dir = AppPreferencesStorage.resolvedNegPyUserDirectoryURL(
            location: .negSwift,
            customPath: nil
        )
        #expect(dir.path.contains("Application Support"))
        #expect(dir.lastPathComponent == "NegSwift")
    }
}
