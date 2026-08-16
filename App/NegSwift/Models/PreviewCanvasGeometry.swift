//
//  PreviewCanvasGeometry.swift
//  NegSwift
//

import CoreGraphics
import Foundation

enum PreviewCanvasGeometry {
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        guard imageAspect > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let width = container.width
            let height = width / imageAspect
            return CGRect(x: 0, y: (container.height - height) / 2, width: width, height: height)
        }
        let height = container.height
        let width = height * imageAspect
        return CGRect(x: (container.width - width) / 2, y: 0, width: width, height: height)
    }

    /// Scroll content offset so ``clickInViewport`` stays fixed after switching to 1:1.
    static func oneToOneScrollOffset(
        clickInViewport: CGPoint?,
        viewportSize: CGSize,
        pixelSize: CGSize
    ) -> CGPoint {
        let maxX = max(0, pixelSize.width - viewportSize.width)
        let maxY = max(0, pixelSize.height - viewportSize.height)

        guard let clickInViewport, viewportSize.width > 0, viewportSize.height > 0 else {
            return CGPoint(x: maxX / 2, y: maxY / 2)
        }

        let imageRect = aspectFitRect(imageSize: pixelSize, in: viewportSize)
        let normalizedX = (clickInViewport.x - imageRect.minX) / max(imageRect.width, 1)
        let normalizedY = (clickInViewport.y - imageRect.minY) / max(imageRect.height, 1)
        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)

        let pixelX = clampedX * pixelSize.width
        let pixelY = clampedY * pixelSize.height
        let offsetX = min(max(pixelX - clickInViewport.x, 0), maxX)
        let offsetY = min(max(pixelY - clickInViewport.y, 0), maxY)
        return CGPoint(x: offsetX, y: offsetY)
    }
}
