//
//  ExportDimensionEstimate.swift
//  NegSwift
//

import CoreGraphics
import Foundation

/// Preview export pixel size from source dimensions + lite geometry (no fine-rot bbox).
enum ExportDimensionEstimate {
    static func exportLongEdgePx(
        sourceSize: CGSize,
        edit: FrameEditState,
        settings: ExportSettings
    ) -> Int {
        let cropped = croppedPixelSize(
            oriented: orientedPixelSize(source: sourceSize, edit: edit),
            edit: edit
        )
        let fullLong = max(
            Int(cropped.width.rounded(.toNearestOrAwayFromZero)),
            Int(cropped.height.rounded(.toNearestOrAwayFromZero))
        )
        let clampedFull = max(1, fullLong)
        switch settings.resolutionMode {
        case .original:
            return clampedFull
        case .targetLongEdge:
            return max(1, min(settings.targetLongEdgePx, clampedFull))
        }
    }

    static func orientedPixelSize(source: CGSize, edit: FrameEditState) -> CGSize {
        var width = source.width
        var height = source.height
        if edit.rotation % 2 != 0 {
            swap(&width, &height)
        }
        return CGSize(width: width, height: height)
    }

    static func croppedPixelSize(oriented: CGSize, edit: FrameEditState) -> CGSize {
        guard let crop = edit.manualCropRect else { return oriented }
        return CGSize(
            width: max(1, oriented.width * crop.width),
            height: max(1, oriented.height * crop.height)
        )
    }
}
