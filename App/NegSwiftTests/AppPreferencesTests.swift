//
//  AppPreferencesTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

@Suite struct AppPreferencesTests {
    @Test func previewQualityFallbackWhenUnset() {
        #expect(PreviewQuality(rawValue: 0) == nil)
        #expect(PreviewQuality(rawValue: 0) ?? .standard == .standard)
    }

    @Test func previewQualityStorageRoundTrip() {
        let suite = "NegSwiftTests.previewQuality.\(UUID().uuidString)"
        setenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE", suite, 1)
        defer { unsetenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE") }

        AppPreferencesStorage.setPreviewQuality(.fast)
        #expect(AppPreferencesStorage.previewQuality() == .fast)
    }

    @Test func preferGPUDefaultsToOnWhenUnset() {
        let suite = "NegSwiftTests.preferGPU.\(UUID().uuidString)"
        setenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE", suite, 1)
        defer { unsetenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE") }

        #expect(AppPreferencesStorage.preferGPU() == true)
    }

    @Test func autoCropDefaultsToOnWhenUnset() {
        let suite = "NegSwiftTests.autoCrop.\(UUID().uuidString)"
        setenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE", suite, 1)
        defer { unsetenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE") }

        #expect(AppPreferencesStorage.autoCropEnabled() == true)
    }

    @Test func resolvedNegSwiftUserDirectory() {
        let url = AppPreferencesStorage.resolvedNegPyUserDirectoryURL(
            location: .negSwift,
            customPath: nil
        )
        #expect(url.path.contains("Application Support"))
        #expect(url.lastPathComponent == "NegSwift")
    }

    @Test func resolvedNegPyDesktopUserDirectory() {
        let url = AppPreferencesStorage.resolvedNegPyUserDirectoryURL(
            location: .negPyDesktop,
            customPath: nil
        )
        #expect(url.path.hasSuffix("Documents/NegPy"))
    }

    @Test func resolvedCustomUserDirectory() {
        let url = AppPreferencesStorage.resolvedNegPyUserDirectoryURL(
            location: .custom,
            customPath: "/tmp/negswift-custom-data"
        )
        #expect(url.path == "/tmp/negswift-custom-data")
    }

    @Test func previewQualityLongEdgeValues() {
        #expect(PreviewQuality.fast.longEdgePx == 1200)
        #expect(PreviewQuality.standard.longEdgePx == 1600)
        #expect(PreviewQuality.high.longEdgePx == 2400)
    }

    @Test @MainActor func previewRenderSettingsFollowPreferences() {
        let suite = "NegSwiftTests.previewRender.\(UUID().uuidString)"
        setenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE", suite, 1)
        defer { unsetenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE") }

        let prefs = AppPreferences()
        prefs.previewQuality = .high
        prefs.preferGPU = false
        let settings = PreviewRenderSettings(preferences: prefs)
        #expect(settings.longEdgePx == 2400)
        #expect(settings.preferGPU == false)
    }

    @Test @MainActor func previewQualityChangeNotifiesListener() {
        let suite = "NegSwiftTests.notify.\(UUID().uuidString)"
        setenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE", suite, 1)
        defer { unsetenv("NEGSWIFT_UI_TEST_DEFAULTS_SUITE") }

        let prefs = AppPreferences()
        var notifications = 0
        prefs.onPreviewSettingsChanged = { notifications += 1 }
        prefs.previewQuality = .high
        prefs.preferGPU = !prefs.preferGPU
        #expect(notifications >= 1)
    }
}
