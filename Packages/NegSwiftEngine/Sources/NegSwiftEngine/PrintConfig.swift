import Foundation

public struct NormalizedCropRect: Sendable, Equatable {
    public var x1: Float
    public var y1: Float
    public var x2: Float
    public var y2: Float

    public init(x1: Float, y1: Float, x2: Float, y2: Float) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public var tuple: (Float, Float, Float, Float) { (x1, y1, x2, y2) }
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
    /// Stored crop in post-orientation space. Nil is full frame.
    public var cropRect: NormalizedCropRect?
    public var rotation: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool

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
        cropRect: NormalizedCropRect? = nil,
        rotation: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
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
        self.cropRect = cropRect
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
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
        if let v = Self.intValue(overrides["rotation"]) { copy.rotation = v }
        if let v = Self.boolValue(overrides["flip_horizontal"]) { copy.flipHorizontal = v }
        if let v = Self.boolValue(overrides["flip_vertical"]) { copy.flipVertical = v }
        return copy
    }

    private static func floatValue(_ value: Any?) -> Float? {
        switch value {
        case let f as Float: f
        case let d as Double: Float(d)
        case let i as Int: Float(i)
        case let n as NSNumber: n.floatValue
        case let s as String: Float(s)
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

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: b
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
