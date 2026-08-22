//
//  PreviewCanvasZoom.swift
//  NegSwift
//

import CoreGraphics
import Foundation

/// Canvas zoom relative to aspect-fit scale (`magnification` 1.0 = fit).
struct PreviewCanvasZoom: Equatable {
    /// Maximum display scale (400% of native pixels), matching NegPy desktop.
    static let maxDisplayScale: CGFloat = 4.0

    var magnification: CGFloat = 1.0

    static let fit = PreviewCanvasZoom(magnification: 1.0)

    func fitScale(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        PreviewCanvasGeometry.fitScale(imageSize: imageSize, in: viewport)
    }

    func displayScale(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        fitScale(imageSize: imageSize, viewport: viewport) * magnification
    }

    func contentSize(imageSize: CGSize, viewport: CGSize) -> CGSize {
        let scale = displayScale(imageSize: imageSize, viewport: viewport)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func isAtFit(epsilon: CGFloat = 0.001) -> Bool {
        magnification <= 1.0 + epsilon
    }

    func isAtOneToOne(imageSize: CGSize, viewport: CGSize, epsilon: CGFloat = 0.02) -> Bool {
        abs(magnification - oneToOneMagnification(imageSize: imageSize, viewport: viewport)) < epsilon
    }

    func oneToOneMagnification(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        let fit = fitScale(imageSize: imageSize, viewport: viewport)
        guard fit > 0 else { return 1.0 }
        return 1.0 / fit
    }

    func maxMagnification(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        let fit = fitScale(imageSize: imageSize, viewport: viewport)
        guard fit > 0 else { return 1.0 }
        return max(1.0, Self.maxDisplayScale / fit)
    }

    func clampedMagnification(
        _ value: CGFloat,
        imageSize: CGSize,
        viewport: CGSize
    ) -> CGFloat {
        min(max(value, 1.0), maxMagnification(imageSize: imageSize, viewport: viewport))
    }

    mutating func setFit() {
        magnification = 1.0
    }

    mutating func setOneToOne(imageSize: CGSize, viewport: CGSize) {
        magnification = oneToOneMagnification(imageSize: imageSize, viewport: viewport)
    }

    mutating func toggle(imageSize: CGSize, viewport: CGSize) {
        if isAtFit() {
            setOneToOne(imageSize: imageSize, viewport: viewport)
        } else {
            setFit()
        }
    }

    func label(imageSize: CGSize, viewport: CGSize) -> String {
        if isAtFit() {
            return "Fit"
        }
        let scale = displayScale(imageSize: imageSize, viewport: viewport)
        if abs(scale - 1.0) < 0.02 {
            return "100%"
        }
        return "\(Int(round(scale * 100)))%"
    }
}
