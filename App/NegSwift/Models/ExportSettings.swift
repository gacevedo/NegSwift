//
//  ExportSettings.swift
//  NegSwift
//

import Foundation

enum ExportFileFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG"
    case tiff = "TIFF"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: "JPEG"
        case .tiff: "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        }
    }
}

enum ExportResolutionMode: String, Sendable {
    case original
    case targetLongEdge = "target_px"
}

/// Instagram feed max long-edge sizes for supported crop ratios.
enum InstagramExportSizing {
    static let fallbackLongEdge = 1080

    static func defaultLongEdge(for edit: FrameEditState, sourceSize: CGSize? = nil) -> Int {
        let ratio = CropAspectRatio.canonical(edit.autocropRatio)
        if ratio != .free {
            return defaultLongEdge(for: ratio)
        }
        if let rect = edit.manualCropRect {
            var width = rect.width
            var height = rect.height
            if edit.rotation % 2 != 0 {
                swap(&width, &height)
            }
            return defaultLongEdge(width: width, height: height)
        }
        if let sourceSize, sourceSize.width > 0, sourceSize.height > 0 {
            var width = sourceSize.width
            var height = sourceSize.height
            if edit.rotation % 2 != 0 {
                swap(&width, &height)
            }
            return defaultLongEdge(width: width, height: height)
        }
        return fallbackLongEdge
    }

    static func defaultLongEdge(for ratio: CropAspectRatio) -> Int {
        switch ratio {
        case .r1x1: 1080
        case .r4x5: 1350
        case .r3x2: 1620
        case .r16x9: 1920
        default: fallbackLongEdge
        }
    }

    static func defaultLongEdge(width: Double, height: Double) -> Int {
        guard width > 0, height > 0 else { return fallbackLongEdge }
        let longOverShort = max(width, height) / min(width, height)
        let targets: [(CropAspectRatio, Double)] = [
            (.r1x1, 1.0),
            (.r4x5, 5.0 / 4.0),
            (.r3x2, 3.0 / 2.0),
            (.r16x9, 16.0 / 9.0),
        ]
        var best = targets[0]
        var bestDistance = abs(longOverShort - best.1)
        for candidate in targets.dropFirst() {
            let distance = abs(longOverShort - candidate.1)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return defaultLongEdge(for: best.0)
    }
}

struct ExportSettings: Sendable {
    var format: ExportFileFormat = .jpeg
    var jpegQuality: Int = 90
    var colorSpace: String = "sRGB"
    var resolutionMode: ExportResolutionMode = .original
    var targetLongEdgePx: Int = InstagramExportSizing.fallbackLongEdge

    static func quickExport(for edit: FrameEditState = FrameEditState(), sourceSize: CGSize? = nil) -> ExportSettings {
        ExportSettings(
            format: .jpeg,
            jpegQuality: 90,
            resolutionMode: .targetLongEdge,
            targetLongEdgePx: InstagramExportSizing.defaultLongEdge(for: edit, sourceSize: sourceSize)
        )
    }

    var progressStatusText: String {
        switch (format, resolutionMode) {
        case (.jpeg, .original):
            "Exporting JPEG at full size (quality \(jpegQuality))…"
        case (.jpeg, .targetLongEdge):
            "Exporting JPEG at \(targetLongEdgePx) px long edge (quality \(jpegQuality))…"
        case (.tiff, .original):
            "Exporting TIFF at full size…"
        case (.tiff, .targetLongEdge):
            "Exporting TIFF at \(targetLongEdgePx) px long edge…"
        }
    }

    func flatExportDict() -> [String: Any] {
        var dict: [String: Any] = [
            "export_fmt": format.rawValue,
            "export_color_space": colorSpace,
            "export_resolution_mode": resolutionMode.rawValue,
            "jpeg_quality": jpegQuality,
        ]
        if resolutionMode == .targetLongEdge {
            dict["export_target_long_edge_px"] = targetLongEdgePx
        }
        return dict
    }
}

struct ExportResult: Codable, Sendable {
    let outputPath: String
    let width: Int
    let height: Int
    let format: String?

    enum CodingKeys: String, CodingKey {
        case outputPath = "output_path"
        case width
        case height
        case format
    }
}
