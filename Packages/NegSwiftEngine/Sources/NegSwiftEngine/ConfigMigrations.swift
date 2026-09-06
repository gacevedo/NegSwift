import Foundation

/// Port of NegPy `negpy/domain/migrations.py`.
public enum ConfigMigrations: Sendable {
    public static let shippedCastStrength: Double = 0.5

    public static let keyRenames: [String: String] = [
        "export_border_size": "border_size",
        "export_border_color": "border_color",
        "auto_shadow_neutral": "cast_removal_strength",
        "cast_removal": "cast_removal_strength",
        "drange_clip": "luma_range_clip",
        "density_saturation": "dye_separation",
        "density_saturation_trim_red": "dye_separation_trim_red",
        "density_saturation_trim_green": "dye_separation_trim_green",
        "density_saturation_trim_blue": "dye_separation_trim_blue",
        "use_colour_average": "use_color_average",
        "mask_blur": "mask_spacer",
        "manual_crop_rect": "crop_rect",
        "auto_crop_enabled": "crop_from_auto",
        "k1": "distortion_k1",
    ]

    public static let droppedKeys: Set<String> = [
        "flare",
        "ir_inpaint_radius",
        "auto_cast_removal",
        "DEFAULT_MATRIX",
        "surround",
        "density_chroma_damping",
        "density_divergence_damping",
        "chroma_damping",
        "density_saturation_damping",
        "density_damping_spatial",
        "vibrance",
        "reference_path",
        "lith_enabled",
        "gear_preset_id",
    ]

    public static let retiredExportFormats: [String: String] = [
        "DNG": "TIFF",
    ]

    public static let legacyProcessModes: [String: String] = [
        "C41": "Color Negative",
        "B&W": "B&W Negative",
        "E-6": "Transparency",
    ]

    public static func migrateExportFmt(_ fmt: String) -> String {
        retiredExportFormats[fmt] ?? fmt
    }

    /// Rewrite a flat config in place (same order as NegPy `migrate_flat_config`).
    @discardableResult
    public static func migrateFlatConfig(_ data: inout [String: Any]) -> [String: Any] {
        let dyeSeparation = ConfigJSON.doubleValue(data["dye_separation"]) ?? 1.0
        if data["density_saturation"] != nil || dyeSeparation < 0.25 {
            data.removeValue(forKey: "dye_separation")
        }
        data.removeValue(forKey: "density_vibrance")

        for (oldKey, newKey) in keyRenames {
            if let value = data.removeValue(forKey: oldKey) {
                data[newKey] = value
            }
        }

        if let trueBlack = data.removeValue(forKey: "true_black") {
            data["paper_black"] = !(ConfigJSON.boolValue(trueBlack) ?? false)
        }

        if let legacy = data.removeValue(forKey: "use_roll_average") {
            let flag = ConfigJSON.boolValue(legacy) ?? false
            if data["use_luma_average"] == nil { data["use_luma_average"] = flag }
            if data["use_color_average"] == nil { data["use_color_average"] = flag }
        }

        if data["color_separation"] != nil, data["crosstalk_strength"] == nil {
            let raw = ConfigJSON.doubleValue(data.removeValue(forKey: "color_separation")) ?? 1
            data["crosstalk_strength"] = min(max(raw - 1, 0), 1)
        }
        data.removeValue(forKey: "color_separation")

        if ConfigJSON.stringValue(data["crosstalk_profile"]) == "Default" {
            data["crosstalk_profile"] = "Generic C41"
        }

        if data["vignette_strength"] != nil, data["vignette_stops"] == nil {
            let strength = ConfigJSON.doubleValue(data.removeValue(forKey: "vignette_strength")) ?? 0
            data["vignette_stops"] = -2.0 * strength
        }
        data.removeValue(forKey: "vignette_strength")

        if let enabled = data.removeValue(forKey: "carrier_enabled"),
           !(ConfigJSON.boolValue(enabled) ?? true)
        {
            data["carrier_width"] = 0.0
        }

        if data["use_original_res"] != nil, data["export_resolution_mode"] == nil {
            let original = ConfigJSON.boolValue(data.removeValue(forKey: "use_original_res")) ?? false
            data["export_resolution_mode"] = original ? "original" : "print"
        } else {
            data.removeValue(forKey: "use_original_res")
        }

        if data["same_as_source"] != nil, data["output_mode"] == nil {
            let same = ConfigJSON.boolValue(data.removeValue(forKey: "same_as_source")) ?? false
            data["output_mode"] = same ? "same_as_source" : "absolute"
        } else {
            data.removeValue(forKey: "same_as_source")
        }

        if let camera = ConfigJSON.stringValue(data["camera_override"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !camera.isEmpty,
           ConfigJSON.stringValue(data["camera_model"])?.isEmpty ?? true
        {
            data.removeValue(forKey: "camera_override")
            if ConfigJSON.stringValue(data["camera_make"])?.isEmpty ?? true {
                let parts = camera.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    data["camera_make"] = String(parts[0])
                    data["camera_model"] = String(parts[1])
                } else {
                    data["camera_model"] = camera
                }
            } else {
                data["camera_model"] = camera
            }
        } else {
            data.removeValue(forKey: "camera_override")
        }

        if let lens = ConfigJSON.stringValue(data["lens_override"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lens.isEmpty,
           ConfigJSON.stringValue(data["lens_model"])?.isEmpty ?? true
        {
            data.removeValue(forKey: "lens_override")
            data["lens_model"] = lens
        } else {
            data.removeValue(forKey: "lens_override")
        }

        if data["lith_enabled"] != nil, data["alt_process"] == nil {
            let lith = ConfigJSON.boolValue(data["lith_enabled"]) ?? false
            data["alt_process"] = lith ? "lith" : "none"
        }

        if let fmt = ConfigJSON.stringValue(data["export_fmt"]) {
            data["export_fmt"] = migrateExportFmt(fmt)
        }

        let mode = ConfigJSON.stringValue(data["process_mode"]) ?? ""
        if mode == "Transparency" || mode == "E-6" {
            let strength = ConfigJSON.doubleValue(data["cast_removal_strength"]) ?? shippedCastStrength
            if abs(strength - shippedCastStrength) < 1e-9 {
                data["cast_removal_strength"] = 0.0
            }
        }

        for key in droppedKeys {
            data.removeValue(forKey: key)
        }
        return data
    }

    /// Coercions that NegPy runs in dataclass `__post_init__` on every construction.
    public static func applyConstructionCoercions(_ data: inout [String: Any]) {
        if let raw = ConfigJSON.stringValue(data["process_mode"]) {
            if let mode = FilmProcessMode(rawValue: raw) {
                data["process_mode"] = mode.rawValue
            } else {
                data["process_mode"] = legacyProcessModes[raw] ?? FilmProcessMode.colorNegative.rawValue
            }
        }
        if let grade = ConfigJSON.doubleValue(data["grade"]), grade <= 5 {
            data["grade"] = 150.0 - 20.0 * grade
        }
        if let cast = data["cast_removal_strength"], ConfigJSON.isJSONBool(cast) {
            data["cast_removal_strength"] = (ConfigJSON.boolValue(cast) ?? false) ? 1.0 : 0.0
        }
    }
}
