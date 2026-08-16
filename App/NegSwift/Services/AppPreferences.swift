//
//  AppPreferences.swift
//  NegSwift
//

import Foundation

/// UserDefaults-backed app settings (preview quality, GPU, NegPy data folder).
enum AppPreferences {
    enum Key {
        static let previewQuality = "negSwift.prefs.previewQuality"
        static let useGPU = "negSwift.prefs.useGPU"
        static let dataLocation = "negSwift.prefs.dataLocation"
        static let customDataPath = "negSwift.prefs.customDataPath"
        static let customDataBookmark = "negSwift.prefs.customDataBookmark"
    }

    enum PreviewQuality: String, CaseIterable, Identifiable, Sendable {
        case fast
        case standard
        case high

        var id: String { rawValue }

        var longEdgePx: Int {
            switch self {
            case .fast: 1200
            case .standard: 1600
            case .high: 2400
            }
        }

        var label: String {
            switch self {
            case .fast: "Fast (1200 px)"
            case .standard: "Standard (1600 px)"
            case .high: "High (2400 px)"
            }
        }
    }

    enum DataLocation: String, CaseIterable, Identifiable, Sendable {
        case negSwift
        case negPyDesktop
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .negSwift: "NegSwift (isolated)"
            case .negPyDesktop: "NegPy desktop (shared)"
            case .custom: "Custom folder"
            }
        }
    }

    static func registerDefaults() {
        userDefaults.register(defaults: [
            Key.previewQuality: PreviewQuality.standard.rawValue,
            Key.useGPU: true,
            Key.dataLocation: DataLocation.negSwift.rawValue,
        ])
    }

    /// UserDefaults backing store for preferences (standard, or an isolated suite in UI tests).
    static var userDefaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["NEGSWIFT_UI_TEST_DEFAULTS_SUITE"],
           !suite.isEmpty,
           let suiteDefaults = UserDefaults(suiteName: suite)
        {
            return suiteDefaults
        }
        return UserDefaults.standard
    }

    static var previewQuality: PreviewQuality {
        get {
            let raw = userDefaults.string(forKey: Key.previewQuality) ?? PreviewQuality.standard.rawValue
            return PreviewQuality(rawValue: raw) ?? .standard
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.previewQuality)
        }
    }

    static var previewLongEdgePx: Int {
        previewQuality.longEdgePx
    }

    static var useGPU: Bool {
        get {
            guard userDefaults.object(forKey: Key.useGPU) != nil else { return true }
            return userDefaults.bool(forKey: Key.useGPU)
        }
        set { userDefaults.set(newValue, forKey: Key.useGPU) }
    }

    static var dataLocation: DataLocation {
        get {
            let raw = userDefaults.string(forKey: Key.dataLocation) ?? DataLocation.negSwift.rawValue
            return DataLocation(rawValue: raw) ?? .negSwift
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.dataLocation)
        }
    }

    static var negpyUserDirectoryURL: URL {
        switch dataLocation {
        case .negSwift:
            return negSwiftDefaultDataDirectory()
        case .negPyDesktop:
            return negPyDesktopDataDirectory()
        case .custom:
            if let url = resolveCustomDataDirectory() {
                return url
            }
            return negSwiftDefaultDataDirectory()
        }
    }

    static var negpyUserDirectoryPath: String {
        negpyUserDirectoryURL.path
    }

    static var customDataDirectoryPath: String? {
        userDefaults.string(forKey: Key.customDataPath)
    }

    static func setCustomDataDirectory(_ url: URL) {
        userDefaults.set(url.path, forKey: Key.customDataPath)
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            userDefaults.set(bookmark, forKey: Key.customDataBookmark)
        }
    }

    static func negSwiftDefaultDataDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NegSwift", isDirectory: true)
    }

    static func negPyDesktopDataDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("NegPy", isDirectory: true)
    }

    private static func resolveCustomDataDirectory() -> URL? {
        if let data = userDefaults.data(forKey: Key.customDataBookmark),
           let url = resolveBookmark(data) {
            return url
        }
        if let path = userDefaults.string(forKey: Key.customDataPath) {
            return existingDirectory(path)
        }
        return nil
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale {
            setCustomDataDirectory(url)
        }
        return existingDirectory(url.path) ?? url
    }

    private static func existingDirectory(_ path: String) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
