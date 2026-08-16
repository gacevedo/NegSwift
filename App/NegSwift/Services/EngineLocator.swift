//
//  EngineLocator.swift
//  NegSwift
//

import Foundation

enum EngineLocator {
    static let bundledRelativePath = "engine/negswift-engine"

    /// Resolved path to `negswift-engine` for the current build.
    static func executableURL(bundle: Bundle = .main) throws -> URL {
        for candidate in candidateURLs(bundle: bundle) {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        if let configured = configuredURLs(bundle: bundle).first {
            throw EngineLocatorError.notExecutable(configured.path)
        }
        throw EngineLocatorError.notConfigured
    }

    /// Search order: `NEGSWIFT_ENGINE` env → bundled Resources → Info.plist dev path.
    static func candidateURLs(bundle: Bundle = .main) -> [URL] {
        configuredURLs(bundle: bundle)
            .filter { !$0.path.contains("$(") }
            .map { $0.standardizedFileURL }
    }

    static func bundledEngineURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent(bundledRelativePath)
    }

    private static func configuredURLs(bundle: Bundle = .main) -> [URL] {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["NEGSWIFT_ENGINE"], !env.isEmpty {
            urls.append(URL(fileURLWithPath: env))
        }
        if let bundled = bundledEngineURL(bundle: bundle) {
            urls.append(bundled)
        }
        if let plist = bundle.object(forInfoDictionaryKey: "NegSwiftEnginePath") as? String, !plist.isEmpty {
            urls.append(URL(fileURLWithPath: plist))
        }
        return urls
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
