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

struct ExportSettings: Sendable {
    var format: ExportFileFormat = .jpeg
    var jpegQuality: Int = 90
    var colorSpace: String = "sRGB"

    func flatExportDict() -> [String: Any] {
        [
            "export_fmt": format.rawValue,
            "export_color_space": colorSpace,
            "export_resolution_mode": "original",
            "jpeg_quality": jpegQuality,
        ]
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
