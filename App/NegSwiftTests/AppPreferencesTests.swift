//
//  AppPreferencesTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct AppPreferencesTests {
    @Test func previewQualityFallbackWhenUnset() {
        #expect(PreviewQuality(rawValue: 0) == nil)
        #expect(PreviewQuality(rawValue: 0) ?? .standard == .standard)
    }

    @Test func previewQualityStorageRoundTrip() {
        let key = "negSwift.preferences.previewQuality"
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        AppPreferencesStorage.setPreviewQuality(.fast)
        #expect(AppPreferencesStorage.previewQuality() == .fast)
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
        let prefs = AppPreferences()
        prefs.previewQuality = .high
        prefs.preferGPU = false
        let settings = PreviewRenderSettings(preferences: prefs)
        #expect(settings.longEdgePx == 2400)
        #expect(settings.preferGPU == false)
    }

    @Test @MainActor func previewQualityChangeNotifiesListener() {
        let prefs = AppPreferences()
        var notifications = 0
        prefs.onPreviewSettingsChanged = { notifications += 1 }
        prefs.previewQuality = .high
        prefs.preferGPU = !prefs.preferGPU
        #expect(notifications >= 1)
    }
}
