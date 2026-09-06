import Foundation

/// Full flat `WorkspaceConfig` dict + NegSwift extras. Load returns the sidecar as
/// stored (or shipped defaults). Save merges overrides, migrates, then writes a
/// complete NegPy-compatible payload. Hidden desktop keys and unknown keys stay.
public enum WorkspaceFlatConfig {
    public static let autoDensityUsesCropKey = "auto_density_uses_crop"

    nonisolated(unsafe) private static let shipped: [String: Any] = ConfigJSON.loadResource("default_workspace")
    nonisolated(unsafe) private static let schema: [String: Any] = ConfigJSON.loadResource("schema_workspace")

    public static var knownKeys: Set<String> { Set(schema.keys) }

    public static func shippedDefaults() -> [String: Any] {
        var flat = ConfigJSON.clone(shipped)
        flat[autoDensityUsesCropKey] = true
        flat["crop_from_auto"] = true
        return flat
    }

    public static func schemaDefaults() -> [String: Any] {
        ConfigJSON.clone(schema)
    }

    public static func fillNegSwiftDefaults(_ flat: inout [String: Any]) {
        if flat[autoDensityUsesCropKey] == nil {
            flat[autoDensityUsesCropKey] = true
        }
        if flat["crop_from_auto"] == nil, flat["auto_crop_enabled"] == nil {
            flat["crop_from_auto"] = true
        }
    }

    /// `from_flat_dict` + `to_dict` + extras (unknown keys + `auto_density_uses_crop`).
    public static func canonicalPayload(merging overrides: [String: Any], onto base: [String: Any]) -> [String: Any] {
        var flat = ConfigJSON.merge(base, overrides)
        var extras: [String: Any] = [:]
        if let auto = flat.removeValue(forKey: autoDensityUsesCropKey) {
            extras[autoDensityUsesCropKey] = auto
        } else {
            extras[autoDensityUsesCropKey] = true
        }
        flat["local_floors"] = [0.0, 0.0, 0.0]
        flat["local_ceils"] = [0.0, 0.0, 0.0]
        flat.removeValue(forKey: "analysis_rect")

        ConfigMigrations.migrateFlatConfig(&flat)
        ConfigMigrations.applyConstructionCoercions(&flat)

        var payload = schemaDefaults()
        for (key, value) in flat {
            if knownKeys.contains(key) {
                payload[key] = value
            } else {
                extras[key] = value
            }
        }
        return ConfigJSON.merge(payload, extras)
    }

    public static func processMode(from flat: [String: Any]) -> FilmProcessMode? {
        guard let raw = ConfigJSON.stringValue(flat["process_mode"]) else { return nil }
        if let mode = FilmProcessMode(rawValue: raw) { return mode }
        if let mapped = ConfigMigrations.legacyProcessModes[raw],
           let mode = FilmProcessMode(rawValue: mapped)
        {
            return mode
        }
        return .colorNegative
    }
}
