//
//  FrameEditState.swift
//  NegSwift
//

import Foundation

enum ProcessMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case c41 = "Color Negative"
    case bw = "B&W Negative"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .c41: "C-41"
        case .bw: "B&W"
        }
    }

    static func fromFlatValue(_ value: Any?) -> ProcessMode {
        guard let raw = value as? String else { return .c41 }
        if let mode = ProcessMode(rawValue: raw) { return mode }
        switch raw {
        case "C41": return .c41
        case "B&W": return .bw
        default: return .c41
        }
    }
}

/// Lite-shell edit state — flat ``WorkspaceConfig`` keys exposed in NegSwift.
struct FrameEditState: Equatable, Codable, Sendable {
    var processMode: ProcessMode = .c41
    var density: Double = 1.0
    var grade: Double = 100.0
    var saturation: Double = 1.0
    var wbCyan: Double = 0
    var wbMagenta: Double = 0
    var wbYellow: Double = 0
    var autoExposure: Bool = true
    var autoNormalizeContrast: Bool = true
    /// Symmetric border inset (0–0.25) for Auto Density metering (`analysis_buffer`).
    var analysisBuffer: Double = EditControlDefaults.analysisBuffer
    /// When set and a crop exists, Auto Density meters inside ``manualCropRect`` (NegPy ``active_roi``).
    var autoDensityUsesCrop: Bool = true
    /// NegPy ``auto_crop_enabled`` — detect and crop film borders when no manual crop is set.
    var autoCropEnabled: Bool = true
    /// NegPy ``dust_remove`` — optical (visible-scan) dust detection and repair.
    var dustRemove: Bool = false
    /// NegPy ``dust_threshold`` — local-contrast sensitivity (lower catches more specks).
    var dustThreshold: Double = EditControlDefaults.dustThreshold
    /// NegPy ``dust_size`` — maximum dust spot radius in pixels (3–8).
    var dustSize: Int = EditControlDefaults.dustSize
    var rotation: Int = 0
    var fineRotation: Double = 0
    var autocropRatio: String = "3:2"
    var manualCropRect: NormalizedRect?

    var hasCrop: Bool { manualCropRect != nil }

    enum CodingKeys: String, CodingKey {
        case processMode = "process_mode"
        case density
        case grade
        case saturation
        case wbCyan = "wb_cyan"
        case wbMagenta = "wb_magenta"
        case wbYellow = "wb_yellow"
        case autoExposure = "auto_exposure"
        case autoNormalizeContrast = "auto_normalize_contrast"
        case analysisBuffer = "analysis_buffer"
        case autoDensityUsesCrop = "auto_density_uses_crop"
        case autoCropEnabled = "auto_crop_enabled"
        case dustRemove = "dust_remove"
        case dustThreshold = "dust_threshold"
        case dustSize = "dust_size"
        case rotation
        case fineRotation = "fine_rotation"
        case autocropRatio = "autocrop_ratio"
        case manualCropRect = "manual_crop_rect"
    }

    init() {}

    init(
        processMode: ProcessMode = .c41,
        density: Double = 1.0,
        grade: Double = 100.0,
        saturation: Double = 1.0,
        wbCyan: Double = 0,
        wbMagenta: Double = 0,
        wbYellow: Double = 0,
        autoExposure: Bool = true,
        autoNormalizeContrast: Bool = true,
        analysisBuffer: Double = EditControlDefaults.analysisBuffer,
        autoDensityUsesCrop: Bool = true,
        autoCropEnabled: Bool = true,
        dustRemove: Bool = false,
        dustThreshold: Double = EditControlDefaults.dustThreshold,
        dustSize: Int = EditControlDefaults.dustSize,
        rotation: Int = 0,
        fineRotation: Double = 0,
        autocropRatio: String = "3:2",
        manualCropRect: NormalizedRect? = nil
    ) {
        self.processMode = processMode
        self.density = density
        self.grade = grade
        self.saturation = saturation
        self.wbCyan = wbCyan
        self.wbMagenta = wbMagenta
        self.wbYellow = wbYellow
        self.autoExposure = autoExposure
        self.autoNormalizeContrast = autoNormalizeContrast
        self.analysisBuffer = analysisBuffer
        self.autoDensityUsesCrop = autoDensityUsesCrop
        self.autoCropEnabled = autoCropEnabled
        self.dustRemove = dustRemove
        self.dustThreshold = dustThreshold
        self.dustSize = dustSize
        self.rotation = rotation
        self.fineRotation = fineRotation
        self.autocropRatio = autocropRatio
        self.manualCropRect = manualCropRect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processMode = try container.decodeIfPresent(ProcessMode.self, forKey: .processMode) ?? .c41
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 1.0
        grade = try container.decodeIfPresent(Double.self, forKey: .grade) ?? 100.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
        wbCyan = try container.decodeIfPresent(Double.self, forKey: .wbCyan) ?? 0
        wbMagenta = try container.decodeIfPresent(Double.self, forKey: .wbMagenta) ?? 0
        wbYellow = try container.decodeIfPresent(Double.self, forKey: .wbYellow) ?? 0
        autoExposure = try container.decodeIfPresent(Bool.self, forKey: .autoExposure) ?? true
        autoNormalizeContrast = try container.decodeIfPresent(Bool.self, forKey: .autoNormalizeContrast) ?? true
        analysisBuffer = try container.decodeIfPresent(Double.self, forKey: .analysisBuffer)
            ?? EditControlDefaults.analysisBuffer
        autoDensityUsesCrop = try container.decodeIfPresent(Bool.self, forKey: .autoDensityUsesCrop) ?? true
        autoCropEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoCropEnabled) ?? true
        dustRemove = try container.decodeIfPresent(Bool.self, forKey: .dustRemove) ?? false
        dustThreshold = try container.decodeIfPresent(Double.self, forKey: .dustThreshold)
            ?? EditControlDefaults.dustThreshold
        dustSize = try container.decodeIfPresent(Int.self, forKey: .dustSize) ?? EditControlDefaults.dustSize
        rotation = try container.decodeIfPresent(Int.self, forKey: .rotation) ?? 0
        fineRotation = try container.decodeIfPresent(Double.self, forKey: .fineRotation) ?? 0
        autocropRatio = try container.decodeIfPresent(String.self, forKey: .autocropRatio) ?? "3:2"
        if let parts = try container.decodeIfPresent([Double].self, forKey: .manualCropRect), parts.count == 4 {
            manualCropRect = NormalizedRect(x1: parts[0], y1: parts[1], x2: parts[2], y2: parts[3])
        } else {
            manualCropRect = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(processMode, forKey: .processMode)
        try container.encode(density, forKey: .density)
        try container.encode(grade, forKey: .grade)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(wbCyan, forKey: .wbCyan)
        try container.encode(wbMagenta, forKey: .wbMagenta)
        try container.encode(wbYellow, forKey: .wbYellow)
        try container.encode(autoExposure, forKey: .autoExposure)
        try container.encode(autoNormalizeContrast, forKey: .autoNormalizeContrast)
        try container.encode(analysisBuffer, forKey: .analysisBuffer)
        try container.encode(autoDensityUsesCrop, forKey: .autoDensityUsesCrop)
        try container.encode(autoCropEnabled, forKey: .autoCropEnabled)
        try container.encode(dustRemove, forKey: .dustRemove)
        try container.encode(dustThreshold, forKey: .dustThreshold)
        try container.encode(dustSize, forKey: .dustSize)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(fineRotation, forKey: .fineRotation)
        try container.encode(autocropRatio, forKey: .autocropRatio)
        if let manualCropRect {
            try container.encode(manualCropRect.arrayValue(), forKey: .manualCropRect)
        }
    }

    static func fromFlatConfig(_ config: [String: Any]) -> FrameEditState {
        FrameEditState(
            processMode: ProcessMode.fromFlatValue(config["process_mode"]),
            density: double(config["density"], default: 1.0),
            grade: double(config["grade"], default: 100.0),
            saturation: double(config["saturation"], default: 1.0),
            wbCyan: double(config["wb_cyan"], default: 0),
            wbMagenta: double(config["wb_magenta"], default: 0),
            wbYellow: double(config["wb_yellow"], default: 0),
            autoExposure: bool(config["auto_exposure"], default: true),
            autoNormalizeContrast: bool(config["auto_normalize_contrast"], default: true),
            analysisBuffer: double(config["analysis_buffer"], default: EditControlDefaults.analysisBuffer),
            autoDensityUsesCrop: bool(config["auto_density_uses_crop"], default: true),
            autoCropEnabled: bool(config["auto_crop_enabled"], default: true),
            dustRemove: bool(config["dust_remove"], default: false),
            dustThreshold: double(config["dust_threshold"], default: EditControlDefaults.dustThreshold),
            dustSize: int(config["dust_size"], default: EditControlDefaults.dustSize),
            rotation: int(config["rotation"], default: 0),
            fineRotation: double(config["fine_rotation"], default: 0),
            autocropRatio: string(config["autocrop_ratio"], default: "3:2"),
            manualCropRect: NormalizedRect.fromFlatValue(config["manual_crop_rect"])
        )
    }

    private static func double(_ value: Any?, default defaultValue: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return defaultValue
    }

    private static func int(_ value: Any?, default defaultValue: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return defaultValue
    }

    private static func string(_ value: Any?, default defaultValue: String) -> String {
        value as? String ?? defaultValue
    }

    private static func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return defaultValue
    }
}

enum EditControlRanges {
    static let density = 0.0 ... 2.0
    static let grade = 50.0 ... 180.0
    static let saturation = 0.0 ... 2.0
    static let whiteBalance = -1.0 ... 1.0
    static let analysisBuffer = 0.0 ... 0.25
    static let dustThreshold = 0.01 ... 1.0
    static let dustSize = 3.0 ... 8.0
    static let fineRotation = -45.0 ... 45.0
}

enum EditControlDefaults {
    static let density = 1.0
    static let grade = 100.0
    static let saturation = 1.0
    static let whiteBalance = 0.0
    static let analysisBuffer = 0.05
    static let dustThreshold = 0.66
    static let dustSize = 4
    static let fineRotation = 0.0
}
