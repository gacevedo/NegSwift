//
//  FrameEditState.swift
//  NegSwift
//

import Foundation

/// M6 editing controls — flat WorkspaceConfig keys the lite shell exposes.
struct FrameEditState: Equatable, Codable, Sendable {
    var density: Double = 1.0
    var grade: Double = 100.0
    var saturation: Double = 1.0
    var wbCyan: Double = 0
    var wbMagenta: Double = 0
    var wbYellow: Double = 0
    var autoExposure: Bool = true
    var autoNormalizeContrast: Bool = true

    enum CodingKeys: String, CodingKey {
        case density
        case grade
        case saturation
        case wbCyan = "wb_cyan"
        case wbMagenta = "wb_magenta"
        case wbYellow = "wb_yellow"
        case autoExposure = "auto_exposure"
        case autoNormalizeContrast = "auto_normalize_contrast"
    }

    init() {}

    init(
        density: Double = 1.0,
        grade: Double = 100.0,
        saturation: Double = 1.0,
        wbCyan: Double = 0,
        wbMagenta: Double = 0,
        wbYellow: Double = 0,
        autoExposure: Bool = true,
        autoNormalizeContrast: Bool = true
    ) {
        self.density = density
        self.grade = grade
        self.saturation = saturation
        self.wbCyan = wbCyan
        self.wbMagenta = wbMagenta
        self.wbYellow = wbYellow
        self.autoExposure = autoExposure
        self.autoNormalizeContrast = autoNormalizeContrast
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 1.0
        grade = try container.decodeIfPresent(Double.self, forKey: .grade) ?? 100.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
        wbCyan = try container.decodeIfPresent(Double.self, forKey: .wbCyan) ?? 0
        wbMagenta = try container.decodeIfPresent(Double.self, forKey: .wbMagenta) ?? 0
        wbYellow = try container.decodeIfPresent(Double.self, forKey: .wbYellow) ?? 0
        autoExposure = try container.decodeIfPresent(Bool.self, forKey: .autoExposure) ?? true
        autoNormalizeContrast = try container.decodeIfPresent(Bool.self, forKey: .autoNormalizeContrast) ?? true
    }

    /// Merge keys from a full flat config dict returned by `load_config`.
    static func fromFlatConfig(_ config: [String: Any]) -> FrameEditState {
        FrameEditState(
            density: double(config["density"], default: 1.0),
            grade: double(config["grade"], default: 100.0),
            saturation: double(config["saturation"], default: 1.0),
            wbCyan: double(config["wb_cyan"], default: 0),
            wbMagenta: double(config["wb_magenta"], default: 0),
            wbYellow: double(config["wb_yellow"], default: 0),
            autoExposure: bool(config["auto_exposure"], default: true),
            autoNormalizeContrast: bool(config["auto_normalize_contrast"], default: true)
        )
    }

    private static func double(_ value: Any?, default defaultValue: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return defaultValue
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
}
