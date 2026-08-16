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

    /// Normalized scratch points for UI tests (`0.35,0.5|0.65,0.5`).
    static var scratchSeedPoints: [CGPoint]? {
        guard let raw = nonEmptyEnvironment("NEGSWIFT_UI_TEST_SCRATCH_SEED_POINTS") else { return nil }
        return parseScratchSeedPoints(raw)
    }

    static func parseScratchSeedPoints(_ raw: String) -> [CGPoint]? {
        var points: [CGPoint] = []
        for pair in raw.split(separator: "|") {
            let parts = pair.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1].trimmingCharacters(in: .whitespaces))
            else { return nil }
            points.append(CGPoint(x: x, y: y))
        }
        return points.isEmpty ? nil : points
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
