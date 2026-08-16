//
//  AppPreferences.swift
//  NegSwift
//

import Foundation
import Observation

enum PreviewQuality: Int, CaseIterable, Identifiable, Sendable {
    case fast = 1200
    case standard = 1600
    case high = 2400

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fast: "Fast (1200 px)"
        case .standard: "Standard (1600 px)"
        case .high: "High (2400 px)"
        }
    }

    var longEdgePx: Int { rawValue }
}

/// Canvas preview parameters derived from app preferences.
struct PreviewRenderSettings: Equatable, Sendable {
    let longEdgePx: Int
    let preferGPU: Bool

    init(preferences: AppPreferences) {
        longEdgePx = preferences.previewQuality.longEdgePx
        preferGPU = preferences.preferGPU
    }
}

enum NegPyUserDataLocation: String, CaseIterable, Identifiable, Sendable {
    case negSwift
    case negPyDesktop
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .negSwift: "NegSwift"
        case .negPyDesktop: "NegPy desktop (shared)"
        case .custom: "Custom folder"
        }
    }
}

enum AppPreferencesStorage {
    private enum Key {
        static let previewQuality = "negSwift.preferences.previewQuality"
        static let preferGPU = "negSwift.preferences.preferGPU"
        static let autodetectProcessMode = "negSwift.preferences.autodetectProcessMode"
        static let userDataLocation = "negSwift.preferences.userDataLocation"
        static let customUserDataPath = "negSwift.preferences.customUserDataPath"
    }

    private static var defaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["NEGSWIFT_UI_TEST_DEFAULTS_SUITE"],
           !suite.isEmpty,
           let suiteDefaults = UserDefaults(suiteName: suite)
        {
            return suiteDefaults
        }
        return UserDefaults.standard
    }

    /// One-time migration from pre-merge `negSwift.prefs.*` keys (string quality, `useGPU`).
    static func migrateLegacyPreferencesIfNeeded() {
        let legacyQualityKey = "negSwift.prefs.previewQuality"
        if defaults.object(forKey: Key.previewQuality) == nil,
           let legacy = defaults.string(forKey: legacyQualityKey)
        {
            switch legacy {
            case "fast":
                setPreviewQuality(.fast)
            case "high":
                setPreviewQuality(.high)
            default:
                setPreviewQuality(.standard)
            }
            defaults.removeObject(forKey: legacyQualityKey)
        }

        let legacyGPUKey = "negSwift.prefs.useGPU"
        if defaults.object(forKey: Key.preferGPU) == nil,
           defaults.object(forKey: legacyGPUKey) != nil
        {
            setPreferGPU(defaults.bool(forKey: legacyGPUKey))
            defaults.removeObject(forKey: legacyGPUKey)
        }

        let legacyLocationKey = "negSwift.prefs.dataLocation"
        if defaults.object(forKey: Key.userDataLocation) == nil,
           let legacy = defaults.string(forKey: legacyLocationKey)
        {
            switch legacy {
            case "negPyDesktop":
                setUserDataLocation(.negPyDesktop)
            case "custom":
                setUserDataLocation(.custom)
            default:
                setUserDataLocation(.negSwift)
            }
            defaults.removeObject(forKey: legacyLocationKey)
        }

        let legacyCustomPathKey = "negSwift.prefs.customDataPath"
        if defaults.string(forKey: Key.customUserDataPath) == nil,
           let legacyPath = defaults.string(forKey: legacyCustomPathKey),
           !legacyPath.isEmpty
        {
            setCustomUserDataPath(legacyPath)
            defaults.removeObject(forKey: legacyCustomPathKey)
        }
    }

    static func previewQuality() -> PreviewQuality {
        let raw = defaults.integer(forKey: Key.previewQuality)
        return PreviewQuality(rawValue: raw) ?? .standard
    }

    static func setPreviewQuality(_ value: PreviewQuality) {
        defaults.set(value.rawValue, forKey: Key.previewQuality)
    }

    static func preferGPU() -> Bool {
        if defaults.object(forKey: Key.preferGPU) == nil {
            return true
        }
        return defaults.bool(forKey: Key.preferGPU)
    }

    static func setPreferGPU(_ value: Bool) {
        defaults.set(value, forKey: Key.preferGPU)
    }

    static func autodetectProcessMode() -> Bool {
        if defaults.object(forKey: Key.autodetectProcessMode) == nil {
            return true
        }
        return defaults.bool(forKey: Key.autodetectProcessMode)
    }

    static func setAutodetectProcessMode(_ value: Bool) {
        defaults.set(value, forKey: Key.autodetectProcessMode)
    }

    static func userDataLocation() -> NegPyUserDataLocation {
        guard let raw = defaults.string(forKey: Key.userDataLocation),
              let location = NegPyUserDataLocation(rawValue: raw)
        else {
            return .negSwift
        }
        return location
    }

    static func setUserDataLocation(_ value: NegPyUserDataLocation) {
        defaults.set(value.rawValue, forKey: Key.userDataLocation)
    }

    static func customUserDataPath() -> String? {
        let path = defaults.string(forKey: Key.customUserDataPath)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    static func setCustomUserDataPath(_ value: String?) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: Key.customUserDataPath)
        } else {
            defaults.removeObject(forKey: Key.customUserDataPath)
        }
    }

    static func defaultNegSwiftUserDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NegSwift", isDirectory: true)
    }

    static func negPyDesktopUserDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/NegPy", isDirectory: true)
    }

    static func resolvedNegPyUserDirectoryURL() -> URL {
        resolvedNegPyUserDirectoryURL(
            location: userDataLocation(),
            customPath: customUserDataPath()
        )
    }

    static func resolvedNegPyUserDirectoryURL(
        location: NegPyUserDataLocation,
        customPath: String?
    ) -> URL {
        switch location {
        case .negSwift:
            return defaultNegSwiftUserDirectory()
        case .negPyDesktop:
            return negPyDesktopUserDirectory()
        case .custom:
            if let path = customPath {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultNegSwiftUserDirectory()
        }
    }
}

@Observable
@MainActor
final class AppPreferences {
    var previewQuality: PreviewQuality {
        didSet {
            guard previewQuality != oldValue else { return }
            AppPreferencesStorage.setPreviewQuality(previewQuality)
            onPreviewSettingsChanged?()
        }
    }

    var preferGPU: Bool {
        didSet {
            guard preferGPU != oldValue else { return }
            AppPreferencesStorage.setPreferGPU(preferGPU)
            onPreviewSettingsChanged?()
        }
    }

    var autodetectProcessMode: Bool {
        didSet {
            guard autodetectProcessMode != oldValue else { return }
            AppPreferencesStorage.setAutodetectProcessMode(autodetectProcessMode)
        }
    }

    var userDataLocation: NegPyUserDataLocation {
        didSet {
            guard userDataLocation != oldValue else { return }
            AppPreferencesStorage.setUserDataLocation(userDataLocation)
            if userDataLocation == .custom, customUserDataPath == nil {
                return
            }
            onUserDataLocationChanged?()
        }
    }

    var customUserDataPath: String?

    var resolvedUserDataDirectory: URL {
        AppPreferencesStorage.resolvedNegPyUserDirectoryURL()
    }

    var onPreviewSettingsChanged: (() -> Void)?
    var onUserDataLocationChanged: (() -> Void)?

    init() {
        previewQuality = AppPreferencesStorage.previewQuality()
        preferGPU = AppPreferencesStorage.preferGPU()
        autodetectProcessMode = AppPreferencesStorage.autodetectProcessMode()
        userDataLocation = AppPreferencesStorage.userDataLocation()
        customUserDataPath = AppPreferencesStorage.customUserDataPath()
    }

    func updateCustomUserDataPath(_ path: String?) {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = normalized?.isEmpty == true ? nil : normalized
        guard stored != customUserDataPath else { return }
        customUserDataPath = stored
        AppPreferencesStorage.setCustomUserDataPath(stored)
        if userDataLocation == .custom {
            onUserDataLocationChanged?()
        }
    }
}
