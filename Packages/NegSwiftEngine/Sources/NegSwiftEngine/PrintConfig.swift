import Foundation

public struct NormalizedCropRect: Sendable, Equatable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public var tuple: (Double, Double, Double, Double) { (x1, y1, x2, y2) }
}

/// S4 print-curve settings. Zone density/grade and CMY are S4b.
public struct PrintConfig: Sendable, Equatable {
    public var density: Float
    public var grade: Float
    public var castRemovalStrength: Float
    public var paperBlack: Bool
    public var paperDmin: Bool
    public var autoExposure: Bool
    public var autoNormalizeContrast: Bool
    public var toe: Float
    public var shoulder: Float
    public var toeWidth: Float
    public var shoulderWidth: Float
    public var shadowDensity: Float
    public var highlightDensity: Float
    public var shadowGrade: Float
    public var highlightGrade: Float
    public var wbCyan: Float
    public var wbMagenta: Float
    public var wbYellow: Float
    public var analysisBuffer: Float
    /// NegSwift `auto_density_uses_crop` — remap crop → `analysis_rect` when true.
    public var autoDensityUsesCrop: Bool
    /// Wire `analysis_rect` after remap (or a direct NegPy override).
    public var analysisRect: NormalizedCropRect?
    /// Stored crop in post-orientation space. Meters on the full frame; pixels crop when ``applyPixelCrop``.
    public var cropRect: NormalizedCropRect?
    public var cropFromAuto: Bool
    public var autoCropEnabled: Bool
    /// False for crop-tool preview (`crop_preview_full`); output stays full-bleed.
    public var applyPixelCrop: Bool
    public var rotation: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    /// NegPy `fine_rotation` degrees (cv2/warp, positive CCW). Canvas size stays fixed.
    public var fineRotation: Float
    /// Lab chroma scale. `1` is a no-op; skin protection still runs when > 0.
    public var saturation: Float
    /// Soft chroma ceiling on skin-hued pixels. NegPy default `0.5`.
    public var skinProtection: Float
    /// L* USM amount. NegPy default `0.25`; `0` bypasses Lab sharpen.
    public var sharpen: Float
    /// USM radius in output pixels (NegPy `sharpen_radius`, default 1).
    public var sharpenRadius: Float
    /// Optional edge mask (NegPy `sharpen_masking`, default 0).
    public var sharpenMasking: Float

    public init(
        density: Float = 1,
        grade: Float = 115,
        castRemovalStrength: Float = 0.5,
        paperBlack: Bool = false,
        paperDmin: Bool = false,
        autoExposure: Bool = false,
        autoNormalizeContrast: Bool = false,
        toe: Float = 0,
        shoulder: Float = 0,
        toeWidth: Float = 2.5,
        shoulderWidth: Float = 2.5,
        shadowDensity: Float = 0,
        highlightDensity: Float = 0,
        shadowGrade: Float = 0,
        highlightGrade: Float = 0,
        wbCyan: Float = 0,
        wbMagenta: Float = 0,
        wbYellow: Float = 0,
        analysisBuffer: Float = LogNormalization.defaultAnalysisBuffer,
        autoDensityUsesCrop: Bool = true,
        analysisRect: NormalizedCropRect? = nil,
        cropRect: NormalizedCropRect? = nil,
        cropFromAuto: Bool = false,
        autoCropEnabled: Bool = false,
        applyPixelCrop: Bool = true,
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        fineRotation: Float = 0,
        saturation: Float = 1,
        skinProtection: Float = 0,
        sharpen: Float = 0,
        sharpenRadius: Float = 1,
        sharpenMasking: Float = 0
    ) {
        self.density = density
        self.grade = grade
        self.castRemovalStrength = castRemovalStrength
        self.paperBlack = paperBlack
        self.paperDmin = paperDmin
        self.autoExposure = autoExposure
        self.autoNormalizeContrast = autoNormalizeContrast
        self.toe = toe
        self.shoulder = shoulder
        self.toeWidth = toeWidth
        self.shoulderWidth = shoulderWidth
        self.shadowDensity = shadowDensity
        self.highlightDensity = highlightDensity
        self.shadowGrade = shadowGrade
        self.highlightGrade = highlightGrade
        self.wbCyan = wbCyan
        self.wbMagenta = wbMagenta
        self.wbYellow = wbYellow
        self.analysisBuffer = analysisBuffer
        self.autoDensityUsesCrop = autoDensityUsesCrop
        self.analysisRect = analysisRect
        self.cropRect = cropRect
        self.cropFromAuto = cropFromAuto
        self.autoCropEnabled = autoCropEnabled
        self.applyPixelCrop = applyPixelCrop
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.fineRotation = fineRotation
        self.saturation = saturation
        self.skinProtection = skinProtection
        self.sharpen = sharpen
        self.sharpenRadius = sharpenRadius
        self.sharpenMasking = sharpenMasking
    }

    /// Pinned S4a/S4b base (autos off, Neutral paper, BPC on, cast 0.5, sliders at 0).
    public static let s4aPin = PrintConfig()

    /// S4b MAE: zone density/grade offset, CMY still 0.
    public static let s4bZoneOffset = PrintConfig(
        shadowDensity: -0.4,
        highlightDensity: 0.25,
        shadowGrade: -25,
        highlightGrade: 20
    )

    /// S4b MAE: global CMY offset, zone still 0.
    public static let s4bCMYOffset = PrintConfig(
        wbCyan: 0.3,
        wbMagenta: -0.2,
        wbYellow: 0.5
    )

    /// S5 pin: autos on, Lab still off, identity geometry.
    public static let s5Pin = PrintConfig(
        autoExposure: true,
        autoNormalizeContrast: true
    )

    /// S8 pin: app defaults — autos on + Lab (sat 1, skin 0.5, sharpen 0.25 USM).
    public static let s8Pin = PrintConfig(
        autoExposure: true,
        autoNormalizeContrast: true,
        saturation: PhotoLab.defaultSaturation,
        skinProtection: PhotoLab.defaultSkinProtection,
        sharpen: PhotoLab.defaultSharpen
    )

    public var bpc: Bool { !paperBlack }
    public var dMin: Double { paperDmin ? ExposureConstants.dMin : 0 }

    /// Merge NegPy-flat keys (`shadow_density`, `wb_cyan`, …) onto this pin.
    public func merging(_ overrides: [String: Any]) -> PrintConfig {
        var copy = self
        if let v = Self.floatValue(overrides["density"]) { copy.density = v }
        if let v = Self.floatValue(overrides["grade"]) { copy.grade = v }
        if let v = Self.floatValue(overrides["cast_removal_strength"]) { copy.castRemovalStrength = v }
        if let v = Self.boolValue(overrides["paper_black"]) { copy.paperBlack = v }
        if let v = Self.boolValue(overrides["paper_dmin"]) { copy.paperDmin = v }
        if let v = Self.boolValue(overrides["auto_exposure"]) { copy.autoExposure = v }
        if let v = Self.boolValue(overrides["auto_normalize_contrast"]) { copy.autoNormalizeContrast = v }
        if let v = Self.floatValue(overrides["toe"]) { copy.toe = v }
        if let v = Self.floatValue(overrides["shoulder"]) { copy.shoulder = v }
        if let v = Self.floatValue(overrides["toe_width"]) { copy.toeWidth = v }
        if let v = Self.floatValue(overrides["shoulder_width"]) { copy.shoulderWidth = v }
        if let v = Self.floatValue(overrides["shadow_density"]) { copy.shadowDensity = v }
        if let v = Self.floatValue(overrides["highlight_density"]) { copy.highlightDensity = v }
        if let v = Self.floatValue(overrides["shadow_grade"]) { copy.shadowGrade = v }
        if let v = Self.floatValue(overrides["highlight_grade"]) { copy.highlightGrade = v }
        if let v = Self.floatValue(overrides["wb_cyan"]) { copy.wbCyan = v }
        if let v = Self.floatValue(overrides["wb_magenta"]) { copy.wbMagenta = v }
        if let v = Self.floatValue(overrides["wb_yellow"]) { copy.wbYellow = v }
        if let v = Self.floatValue(overrides["analysis_buffer"]) { copy.analysisBuffer = v }
        if let v = Self.boolValue(overrides["auto_density_uses_crop"]) { copy.autoDensityUsesCrop = v }
        if let v = MeteringRemap.asRect(overrides["analysis_rect"]) { copy.analysisRect = v }
        if let v = MeteringRemap.asRect(overrides["crop_rect"]) ?? MeteringRemap.asRect(overrides["manual_crop_rect"]) {
            copy.cropRect = v
        }
        if let v = Self.boolValue(overrides["crop_from_auto"]) { copy.cropFromAuto = v }
        if let v = Self.boolValue(overrides["auto_crop_enabled"]) { copy.autoCropEnabled = v }
        if let v = Self.intValue(overrides["rotation"]) { copy.rotation = v }
        if let v = Self.boolValue(overrides["flip_horizontal"]) { copy.flipHorizontal = v }
        if let v = Self.boolValue(overrides["flip_vertical"]) { copy.flipVertical = v }
        if let v = Self.floatValue(overrides["fine_rotation"]) { copy.fineRotation = v }
        if let v = Self.floatValue(overrides["saturation"]) { copy.saturation = v }
        if let v = Self.floatValue(overrides["skin_protection"]) { copy.skinProtection = v }
        if let v = Self.floatValue(overrides["sharpen"]) { copy.sharpen = v }
        if let v = Self.floatValue(overrides["sharpen_radius"]) { copy.sharpenRadius = v }
        if let v = Self.floatValue(overrides["sharpen_masking"]) { copy.sharpenMasking = v }
        if let v = Self.boolValue(overrides["crop_preview_full"]) { copy.applyPixelCrop = !v }
        return copy.applyingMeteringRemap(from: overrides)
    }

    /// Meter region after `metering.py` remap. Pixel crop is applied after print.
    public func resolvedAnalysisRegion() -> AnalysisRegion {
        if let analysisRect {
            return AnalysisRegion(buffer: 0, rect: analysisRect)
        }
        if let cropRect, cropFromAuto {
            return AnalysisRegion(buffer: analysisBuffer, rect: cropRect)
        }
        return AnalysisRegion(buffer: analysisBuffer, rect: nil)
    }

    /// Apply `negpy_flat_for_pipeline` when crop / toggle keys are present; keep a
    /// direct `analysis_rect` when those keys are absent (MAE / NegPy wire override).
    public func applyingMeteringRemap(from overrides: [String: Any]? = nil) -> PrintConfig {
        var copy = self
        let keys = overrides ?? [:]
        let hasCropKeys = keys["crop_rect"] != nil || keys["manual_crop_rect"] != nil
            || cropRect != nil
        let hasToggle = keys["auto_density_uses_crop"] != nil
        if keys["analysis_rect"] != nil, keys["crop_rect"] == nil, keys["manual_crop_rect"] == nil {
            return copy
        }
        if !hasCropKeys, !hasToggle {
            return copy
        }
        var flat: [String: Any] = [
            "auto_density_uses_crop": autoDensityUsesCrop,
            "analysis_buffer": analysisBuffer,
            "crop_from_auto": cropFromAuto,
            "auto_crop_enabled": autoCropEnabled,
        ]
        if let cropRect {
            if cropFromAuto {
                flat["crop_rect"] = cropRect.arrayValue
            } else {
                flat["manual_crop_rect"] = cropRect.arrayValue
            }
        }
        copy.analysisRect = MeteringRemap.pipelineAnalysisRect(flat)
        return copy
    }

    static func floatValue(_ value: Any?) -> Float? {
        doubleValue(value).map(Float.init)
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: d
        case let f as Float: Double(f)
        case let i as Int: Double(i)
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: i
        case let d as Double: Int(d)
        case let n as NSNumber: n.intValue
        case let s as String: Int(s)
        default: nil
        }
    }

    static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: b
        case let n as NSNumber: n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "true", "1", "yes": true
            case "false", "0", "no": false
            default: nil
            }
        default: nil
        }
    }
}
