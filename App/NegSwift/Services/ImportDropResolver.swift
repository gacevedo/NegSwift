//
//  ImportDropResolver.swift
//  NegSwift
//

import Foundation

enum ImportDropResolver {
    enum Action: Equatable {
        case folder(URL)
        case singleFile(URL)
        case multipleFiles([URL])
        case unsupported(String)
    }

    static func action(for urls: [URL]) -> Action {
        let normalized = urls.map { $0.standardizedFileURL }
        guard !normalized.isEmpty else {
            return .unsupported("Nothing to import.")
        }

        var directories: [URL] = []
        var files: [URL] = []
        for url in normalized {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                directories.append(url)
            } else {
                files.append(url)
            }
        }

        if directories.isEmpty, files.isEmpty {
            return .unsupported("Dropped items could not be read.")
        }

        if directories.count == 1, files.isEmpty {
            return .folder(directories[0])
        }

        if directories.count > 1 {
            return .unsupported("Drop one folder at a time.")
        }

        if !directories.isEmpty, !files.isEmpty {
            return .unsupported("Drop either one folder or scan files, not both.")
        }

        if files.count == 1, let file = files.first {
            return .singleFile(file)
        }

        let sorted = files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        return .multipleFiles(sorted)
    }
}
