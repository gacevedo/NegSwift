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

/// S4a print-curve settings. Zone/CMY fields are accepted (default 0) for S4b.
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

    /// Pinned S4a config (autos off, Neutral paper, BPC on, cast 0.5).
    public static let s4aPin = PrintConfig()

    public var bpc: Bool { !paperBlack }
    public var dMin: Double { paperDmin ? ExposureConstants.dMin : 0 }
}
