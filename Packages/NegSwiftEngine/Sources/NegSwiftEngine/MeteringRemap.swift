import Foundation

/// NegSwift metering prefs that NegPy does not model (`Engine/negswift_engine/metering.py`).
public enum MeteringRemap: Sendable {
    public static let sidecarKeys: Set<String> = ["auto_density_uses_crop"]
    public static let fullFrameAnalysisRect = NormalizedCropRect(x1: 0, y1: 0, x2: 1, y2: 1)

    public static func asRect(_ value: Any?) -> NormalizedCropRect? {
        let nums: [Double]
        switch value {
        case let a as [Double] where a.count == 4:
            nums = a
        case let a as [Float] where a.count == 4:
            nums = a.map(Double.init)
        case let a as [Int] where a.count == 4:
            nums = a.map(Double.init)
        case let a as [NSNumber] where a.count == 4:
            nums = a.map(\.doubleValue)
        case let a as NSArray where a.count == 4:
            let parsed = a.compactMap { PrintConfig.doubleValue($0) }
            guard parsed.count == 4 else { return nil }
            nums = parsed
        default:
            return nil
        }
        return NormalizedCropRect(x1: nums[0], y1: nums[1], x2: nums[2], y2: nums[3])
    }

    public static func isFullFrameAnalysisRect(_ value: Any?) -> Bool {
        guard let rect = asRect(value) else { return false }
        return rect.isApproximatelyEqual(to: fullFrameAnalysisRect)
    }

    public static func defaultAutoDensityUsesCrop(_ flat: [String: Any]) -> Bool {
        guard let value = flat["auto_density_uses_crop"] else { return true }
        return PrintConfig.boolValue(value) ?? true
    }

    public static func sidecarExtras(_ flat: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in sidecarKeys where flat[key] != nil {
            out[key] = flat[key]
        }
        return out
    }

    public static func insetNormalizedRect(
        _ rect: NormalizedCropRect,
        buffer: Double
    ) -> NormalizedCropRect {
        if buffer <= 0 { return rect }
        let width = rect.x2 - rect.x1
        let height = rect.y2 - rect.y1
        if width <= 0 || height <= 0 { return rect }
        let safe = min(max(buffer, 0), 0.3)
        let insetX = safe * width
        let insetY = safe * height
        let nx1 = rect.x1 + insetX
        let ny1 = rect.y1 + insetY
        let nx2 = rect.x2 - insetX
        let ny2 = rect.y2 - insetY
        if nx2 - nx1 < 1e-4 || ny2 - ny1 < 1e-4 { return rect }
        return NormalizedCropRect(x1: nx1, y1: ny1, x2: nx2, y2: ny2)
    }

    public static func cropMeteringAnalysisRect(_ flat: [String: Any]) -> NormalizedCropRect? {
        guard let rect = asRect(flat["crop_rect"]) ?? asRect(flat["manual_crop_rect"]) else {
            return nil
        }
        let buffer = PrintConfig.doubleValue(flat["analysis_buffer"]) ?? 0.05
        return insetNormalizedRect(rect, buffer: buffer)
    }

    public static func hasManualCropRect(_ flat: [String: Any]) -> Bool {
        asRect(flat["crop_rect"]) != nil || asRect(flat["manual_crop_rect"]) != nil
    }

    public static func armedAutoCrop(_ flat: [String: Any]) -> Bool {
        let fromAuto = PrintConfig.boolValue(flat["crop_from_auto"]) ?? false
        if hasManualCropRect(flat) { return fromAuto }
        return fromAuto || (PrintConfig.boolValue(flat["auto_crop_enabled"]) ?? false)
    }

    public static func flatForSave(_ flat: [String: Any]) -> [String: Any] {
        var out = flat.filter { !sidecarKeys.contains($0.key) }
        out["local_floors"] = [0.0, 0.0, 0.0]
        out["local_ceils"] = [0.0, 0.0, 0.0]
        out.removeValue(forKey: "analysis_rect")
        return out
    }

    /// Map NegSwift metering prefs onto NegPy flat keys for render/export.
    public static func flatForPipeline(_ flat: [String: Any]) -> [String: Any] {
        var out = flatForSave(flat)
        out["local_floors"] = [0.0, 0.0, 0.0]
        out["local_ceils"] = [0.0, 0.0, 0.0]
        out.removeValue(forKey: "auto_crop_enabled")
        if !hasManualCropRect(out) {
            if armedAutoCrop(flat) {
                out["crop_from_auto"] = true
                if let detectKey = flat["crop_detect_key"] as? String, !detectKey.isEmpty {
                    out["crop_detect_key"] = detectKey
                }
            }
            if !defaultAutoDensityUsesCrop(flat) {
                out["analysis_rect"] = fullFrameAnalysisRect.arrayValue
            }
            return out
        }
        let cropFromAuto = PrintConfig.boolValue(flat["crop_from_auto"]) ?? false
        if cropFromAuto {
            out["crop_from_auto"] = true
            if let rect = asRect(flat["crop_rect"]) ?? asRect(flat["manual_crop_rect"]) {
                out["crop_rect"] = rect.arrayValue
                out.removeValue(forKey: "manual_crop_rect")
            }
            if let detectKey = flat["crop_detect_key"] as? String, !detectKey.isEmpty {
                out["crop_detect_key"] = detectKey
            }
        } else {
            out["crop_from_auto"] = false
        }
        if defaultAutoDensityUsesCrop(flat) {
            if !cropFromAuto, let meterRect = cropMeteringAnalysisRect(flat) {
                out["analysis_rect"] = meterRect.arrayValue
            }
        } else {
            out["analysis_rect"] = fullFrameAnalysisRect.arrayValue
        }
        return out
    }

    public static func pipelineAnalysisRect(_ flat: [String: Any]) -> NormalizedCropRect? {
        asRect(flatForPipeline(flat)["analysis_rect"])
    }
}

public extension NormalizedCropRect {
    var arrayValue: [Double] { [x1, y1, x2, y2] }

    func isApproximatelyEqual(to other: NormalizedCropRect, tolerance: Double = 1e-6) -> Bool {
        abs(x1 - other.x1) < tolerance
            && abs(y1 - other.y1) < tolerance
            && abs(x2 - other.x2) < tolerance
            && abs(y2 - other.y2) < tolerance
    }
}

/// Meter region after remap: a freehand rect disables the symmetric buffer.
public struct AnalysisRegion: Sendable, Equatable {
    public var buffer: Float
    public var rect: NormalizedCropRect?

    public init(buffer: Float, rect: NormalizedCropRect?) {
        self.buffer = buffer
        self.rect = rect
    }
}
