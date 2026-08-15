//
//  RecentPathsStore.swift
//  NegSwift
//

import Foundation

enum RecentPathKind {
    case importFolder
    case openFileDirectory
    case exportFolder
}

/// Last-used directories for import, open-file, and export pickers (kept separate).
enum RecentPathsStore {
    private enum Key {
        static let importFolder = "negSwift.recent.importFolder"
        static let openFileDirectory = "negSwift.recent.openFileDirectory"
        static let exportFolderPath = "negSwift.recent.exportFolder"
        static let exportFolderBookmark = "negSwift.recent.exportFolderBookmark"
    }

    static func directoryURL(for kind: RecentPathKind) -> URL? {
        switch kind {
        case .importFolder:
            return existingDirectory(defaults.string(forKey: Key.importFolder))
        case .openFileDirectory:
            return existingDirectory(defaults.string(forKey: Key.openFileDirectory))
        case .exportFolder:
            if let data = defaults.data(forKey: Key.exportFolderBookmark),
               let url = resolveBookmark(data) {
                return url
            }
            return existingDirectory(defaults.string(forKey: Key.exportFolderPath))
        }
    }

    static func quickExportDestinationURL() -> URL? {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           existingDirectory(downloads.path) != nil
        {
            return downloads
        }
        return directoryURL(for: .exportFolder)
    }

    static func remember(_ url: URL, for kind: RecentPathKind) {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        switch kind {
        case .importFolder:
            defaults.set(directory.path, forKey: Key.importFolder)
        case .openFileDirectory:
            defaults.set(directory.path, forKey: Key.openFileDirectory)
        case .exportFolder:
            defaults.set(directory.path, forKey: Key.exportFolderPath)
            if let bookmark = try? directory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(bookmark, forKey: Key.exportFolderBookmark)
            }
        }
    }

    private static let defaults = UserDefaults.standard

    private static func existingDirectory(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
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
            remember(url, for: .exportFolder)
        }
        return url
    }
}
