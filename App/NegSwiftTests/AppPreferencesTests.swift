//
//  AppPreferencesTests.swift
//  NegSwiftTests
//

import Foundation
import Testing

@testable import NegSwift

@Suite struct AppPreferencesTests {
    @Test func previewQualityLongEdgeValues() {
        #expect(AppPreferences.PreviewQuality.fast.longEdgePx == 1200)
        #expect(AppPreferences.PreviewQuality.standard.longEdgePx == 1600)
        #expect(AppPreferences.PreviewQuality.high.longEdgePx == 2400)
    }

    @Test func negSwiftDefaultDataDirectoryIsUnderApplicationSupport() {
        let url = AppPreferences.negSwiftDefaultDataDirectory()
        #expect(url.lastPathComponent == "NegSwift")
        #expect(url.path.contains("Application Support"))
    }

    @Test func negPyDesktopDataDirectoryIsDocumentsNegPy() {
        let url = AppPreferences.negPyDesktopDataDirectory()
        #expect(url.lastPathComponent == "NegPy")
        #expect(url.path.contains("Documents"))
    }
}
