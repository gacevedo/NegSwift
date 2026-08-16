//
//  UITestSupport.swift
//  NegSwift
//

import Foundation

/// Launch hooks for UI automation (`-UITesting` + `NEGSWIFT_UI_TEST_*` env vars).
enum UITestSupport {
    static let launchArgument = "-UITesting"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var importPath: String? {
        nonEmptyEnvironment("NEGSWIFT_UI_TEST_IMPORT")
    }

    static var droppedURLPaths: [String]? {
        guard let raw = nonEmptyEnvironment("NEGSWIFT_UI_TEST_DROP_PATHS") else { return nil }
        let paths = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths
    }

    static var exportDestinationURL: URL? {
        guard let path = nonEmptyEnvironment("NEGSWIFT_UI_TEST_EXPORT_DIR") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func runAutomation(session: EngineSession) async {
        guard isActive else { return }

        if let paths = droppedURLPaths {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            await session.importDroppedURLs(urls)
            return
        }

        if let path = importPath {
            await session.importFileFromPicker(URL(fileURLWithPath: path))
        }
    }

    private static func nonEmptyEnvironment(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}
