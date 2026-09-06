import Foundation

public enum SidecarStoreError: Error, LocalizedError, Sendable {
    case notADirectory(URL)
    case writeFailed(URL)
    case invalidJSON(URL)

    public var errorDescription: String? {
        switch self {
        case let .notADirectory(url):
            "Cannot write sidecar beside \(url.path)"
        case let .writeFailed(url):
            "Could not write sidecar \(url.path)"
        case let .invalidJSON(url):
            "Sidecar is not a JSON object: \(url.path)"
        }
    }
}

/// `.negpy` beside the scan: ``<basename>.negpy``.
public enum SidecarStore {
    public static func url(forScanPath path: String) -> URL {
        let scan = URL(fileURLWithPath: path)
        let base = scan.deletingPathExtension().lastPathComponent
        return scan.deletingLastPathComponent().appendingPathComponent("\(base).negpy")
    }

    public static func exists(forScanPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forScanPath: path).path)
    }

    public static func readRaw(forScanPath path: String) throws -> [String: Any]? {
        let sidecar = url(forScanPath: path)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return nil }
        let data = try Data(contentsOf: sidecar)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw SidecarStoreError.invalidJSON(sidecar)
        }
        return dict
    }

    public static func writeRaw(forScanPath path: String, payload: [String: Any]) throws -> String {
        let sidecar = url(forScanPath: path)
        let directory = sidecar.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ConfigJSON.jsonData(payload, pretty: true)
        let tmp = directory.appendingPathComponent("\(sidecar.lastPathComponent).\(UUID().uuidString).part")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                _ = try FileManager.default.replaceItemAt(sidecar, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: sidecar)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw SidecarStoreError.writeFailed(sidecar)
        }
        return sidecar.path
    }

    public static func delete(forScanPath path: String) throws -> Bool {
        let sidecar = url(forScanPath: path)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return false }
        try FileManager.default.removeItem(at: sidecar)
        return true
    }

    public static func baseFlat(forScanPath path: String) throws -> [String: Any] {
        if let raw = try readRaw(forScanPath: path) {
            return raw
        }
        return WorkspaceFlatConfig.shippedDefaults()
    }

    public static func load(path: String) throws -> (config: [String: Any], hasSidecar: Bool) {
        if var raw = try readRaw(forScanPath: path) {
            WorkspaceFlatConfig.fillNegSwiftDefaults(&raw)
            return (raw, true)
        }
        return (WorkspaceFlatConfig.shippedDefaults(), false)
    }

    public static func save(path: String, overrides: [String: Any]?) throws -> String {
        let base = try baseFlat(forScanPath: path)
        let payload = WorkspaceFlatConfig.canonicalPayload(merging: overrides ?? [:], onto: base)
        return try writeRaw(forScanPath: path, payload: payload)
    }

    public static func reset(path: String) throws -> Bool {
        try delete(forScanPath: path)
    }
}
