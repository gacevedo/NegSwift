import Foundation

public enum NativeExportFormat: String, Sendable, Equatable {
    case jpeg = "JPEG"
    case tiff = "TIFF"

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        }
    }
}

/// Lite export sheet: sRGB JPEG/TIFF at original or target long-edge resolution.
public struct NativeExportSettings: Sendable, Equatable {
    public enum ResolutionMode: String, Sendable, Equatable {
        case original
        case targetPx = "target_px"
    }

    public var format: NativeExportFormat
    public var jpegQuality: Int
    public var overwrite: Bool
    /// TIFF only. JPEG is always 8-bit. NegPy default is 16.
    public var tiffBitDepth: Int
    public var resolutionMode: ResolutionMode
    public var targetLongEdgePx: Int

    public init(
        format: NativeExportFormat = .jpeg,
        jpegQuality: Int = 90,
        overwrite: Bool = false,
        tiffBitDepth: Int = 16,
        resolutionMode: ResolutionMode = .original,
        targetLongEdgePx: Int = 1080
    ) {
        self.format = format
        self.jpegQuality = min(100, max(1, jpegQuality))
        self.overwrite = overwrite
        self.tiffBitDepth = tiffBitDepth >= 16 ? 16 : 8
        self.resolutionMode = resolutionMode
        self.targetLongEdgePx = min(32768, max(1, targetLongEdgePx))
    }

    /// Parse protocol `export` object. Unknown lite formats are rejected.
    public static func parse(_ dict: [String: Any]?) throws -> NativeExportSettings {
        var settings = NativeExportSettings()
        guard let dict else { return settings }

        if let raw = ConfigJSON.stringValue(dict["export_fmt"]) ?? ConfigJSON.stringValue(dict["format"]) {
            let upper = raw.uppercased()
            if upper == "JPG" { settings.format = .jpeg }
            else if let fmt = NativeExportFormat(rawValue: upper) { settings.format = fmt }
            else {
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.export.export_fmt must be JPEG or TIFF"
                )
            }
        }
        if dict["jpeg_quality"] != nil {
            guard let value = ConfigJSON.intValue(dict["jpeg_quality"]), (1 ... 100).contains(value) else {
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.export.jpeg_quality must be an integer from 1 to 100"
                )
            }
            settings.jpegQuality = value
        }
        if dict["export_bit_depth"] != nil {
            guard let value = ConfigJSON.intValue(dict["export_bit_depth"]), value == 8 || value == 16 else {
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.export.export_bit_depth must be 8 or 16"
                )
            }
            settings.tiffBitDepth = value
        }
        if let raw = ConfigJSON.stringValue(dict["export_resolution_mode"]) {
            switch raw {
            case ResolutionMode.original.rawValue:
                settings.resolutionMode = .original
            case ResolutionMode.targetPx.rawValue:
                settings.resolutionMode = .targetPx
            default:
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.export.export_resolution_mode must be original or target_px"
                )
            }
        }
        if dict["export_target_long_edge_px"] != nil {
            guard let value = ConfigJSON.intValue(dict["export_target_long_edge_px"]),
                  (1 ... 32768).contains(value)
            else {
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.export.export_target_long_edge_px must be an integer from 1 to 32768"
                )
            }
            settings.targetLongEdgePx = value
        }
        return settings
    }
}

/// NegPy `export.py` naming: `stem.ext`, then `stem_2.ext`, `stem_3.ext`, …
public enum ExportNaming: Sendable {
    public static func outputURL(
        sourcePath: String,
        destDir: String,
        format: NativeExportFormat,
        overwrite: Bool
    ) throws -> URL {
        let dest = URL(fileURLWithPath: destDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let stem = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else {
            throw ProtocolFailure(code: "EXPORT_FAILED", message: "Could not derive export filename")
        }
        let ext = format.fileExtension
        var url = dest.appendingPathComponent("\(stem).\(ext)")
        if overwrite {
            return url
        }
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dest.appendingPathComponent("\(stem)_\(counter).\(ext)")
            counter += 1
        }
        return url
    }
}
