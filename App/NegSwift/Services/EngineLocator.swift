//
//  EngineLocator.swift
//  NegSwift
//

import Foundation

enum EngineLocator {
    /// Resolved path to `negswift-engine` for the current build.
    static func executableURL() throws -> URL {
        for candidate in candidatePaths() {
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        if let configured = configuredPaths().first {
            throw EngineLocatorError.notExecutable(configured)
        }
        throw EngineLocatorError.notConfigured
    }

    private static func configuredPaths() -> [String] {
        var paths: [String] = []
        if let env = ProcessInfo.processInfo.environment["NEGSWIFT_ENGINE"], !env.isEmpty {
            paths.append(env)
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "NegSwiftEnginePath") as? String, !plist.isEmpty {
            paths.append(plist)
        }
        return paths
    }

    private static func candidatePaths() -> [String] {
        configuredPaths()
            .filter { !$0.contains("$(") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }
}

enum EngineLocatorError: LocalizedError {
    case notConfigured
    case notExecutable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            """
            negswift-engine path not configured. Run `cd Engine && uv sync`, rebuild the app, \
            or set NEGSWIFT_ENGINE in the Xcode scheme. SwiftUI Previews skip the engine — use ⌘R to run.
            """
        case let .notExecutable(path):
            "negswift-engine not found or not executable at \(path). Run `cd Engine && uv sync`."
        }
    }
}

enum ProcessInfoPreview {
    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
