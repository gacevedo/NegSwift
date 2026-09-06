import Foundation

/// Store-only heal IPC (S7). Viewport→source mapping and inpaint are S10a.
public enum HealStore {
    public static func appendStroke(
        path: String,
        points: [[Double]],
        brushSize: Double?,
        configOverrides: [String: Any]?
    ) throws -> [String: Any] {
        guard !points.isEmpty else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.points must be a non-empty array")
        }
        let flat = try mergedFlat(path: path, overrides: configOverrides)
        let size = brushSize ?? ConfigJSON.doubleValue(flat["manual_dust_size"]) ?? 6
        var strokes = existingStrokes(flat["manual_heal_strokes"])
        strokes.append([points, size, 0.0, 0.0])
        return [
            "manual_heal_strokes": strokes,
            "stroke_index": strokes.count - 1,
        ]
    }

    public static func undoLast(path: String, configOverrides: [String: Any]?) throws -> [String: Any] {
        let flat = try mergedFlat(path: path, overrides: configOverrides)
        var strokes = existingStrokes(flat["manual_heal_strokes"])
        var spots = existingSpots(flat["manual_dust_spots"])
        var removed: Any = NSNull()
        if !strokes.isEmpty {
            strokes.removeLast()
            removed = "stroke"
        } else if !spots.isEmpty {
            spots.removeLast()
            removed = "spot"
        }
        return [
            "manual_heal_strokes": strokes,
            "manual_dust_spots": spots,
            "removed": removed,
        ]
    }

    private static func mergedFlat(path: String, overrides: [String: Any]?) throws -> [String: Any] {
        var flat = try SidecarStore.baseFlat(forScanPath: path)
        if let overrides {
            flat = ConfigJSON.merge(flat, overrides)
        }
        return flat
    }

    private static func existingStrokes(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func existingSpots(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }
}
