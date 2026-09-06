import Foundation

/// Heal IPC: viewport→source mapping via `uv_grid`, then store the stroke.
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
        let mapped = try mapViewportPoints(path: path, points: points, flat: flat)
        var strokes = existingStrokes(flat["manual_heal_strokes"])
        strokes.append([mapped, size, 0.0, 0.0])
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

    public static func mapViewportPoints(
        path: String,
        points: [[Double]],
        flat: [String: Any]
    ) throws -> [[Double]] {
        let dims = try sourceDimensions(path)
        let config = PrintConfig.s8Pin.merging(flat)
        let grid = CoordinateMapping.createUVGrid(
            sourceWidth: dims.width,
            sourceHeight: dims.height,
            rotation: config.rotation,
            fineRotation: config.fineRotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            cropRect: config.cropRect,
            applyCrop: config.applyPixelCrop
        )
        return points.map { pair in
            let mapped = CoordinateMapping.mapClickToRaw(nx: pair[0], ny: pair[1], grid: grid)
            return [mapped.0, mapped.1]
        }
    }

    private static func sourceDimensions(_ path: String) throws -> (width: Int, height: Int) {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw ProtocolFailure(code: "NOT_FOUND", message: "Scan not found: \(path)")
        }
        if let dims = ImageCoding.probeDimensions(at: url) {
            return dims
        }
        throw ProtocolFailure(code: "LOAD_FAILED", message: "Could not read scan dimensions")
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
