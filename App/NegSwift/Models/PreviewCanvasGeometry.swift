//
//  PreviewCanvasGeometry.swift
//  NegSwift
//

import CoreGraphics
import Foundation

enum PreviewCanvasGeometry {
    static func fitScale(imageSize: CGSize, in container: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return 1
        }
        return min(container.width / imageSize.width, container.height / imageSize.height)
    }

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

    static func contentOverflows(contentSize: CGSize, viewportSize: CGSize) -> Bool {
        contentSize.width > viewportSize.width + 0.5 || contentSize.height > viewportSize.height + 0.5
    }

    static func centeredContentRect(contentSize: CGSize, in viewportSize: CGSize) -> CGRect {
        CGRect(
            x: (viewportSize.width - contentSize.width) / 2,
            y: (viewportSize.height - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    static func centeredContentOffset(contentSize: CGSize, viewportSize: CGSize) -> CGPoint {
        clampedContentOffset(
            CGPoint(
                x: (viewportSize.width - contentSize.width) / 2,
                y: (viewportSize.height - contentSize.height) / 2
            ),
            contentSize: contentSize,
            viewportSize: viewportSize
        )
    }

    static func clampedContentOffset(
        _ offset: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: clampAxis(offset.x, contentLength: contentSize.width, viewportLength: viewportSize.width),
            y: clampAxis(offset.y, contentLength: contentSize.height, viewportLength: viewportSize.height)
        )
    }

    private static func clampAxis(_ value: CGFloat, contentLength: CGFloat, viewportLength: CGFloat) -> CGFloat {
        if contentLength <= viewportLength {
            return (viewportLength - contentLength) / 2
        }
        let minBound = viewportLength - contentLength
        return min(max(value, minBound), 0)
    }

    /// Content coordinate under ``anchorInViewport`` before a zoom step.
    static func contentPointUnderAnchor(
        anchorInViewport: CGPoint,
        contentOffset: CGPoint,
        contentSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: anchorInViewport.x - contentOffset.x,
            y: anchorInViewport.y - contentOffset.y
        )
    }

    /// Content offset that keeps ``contentPoint`` fixed under ``anchorInViewport`` after content resizes.
    static func contentOffsetKeepingContentPointFixed(
        contentPoint: CGPoint,
        oldContentSize: CGSize,
        newContentSize: CGSize,
        anchorInViewport: CGPoint,
        viewportSize: CGSize
    ) -> CGPoint {
        guard oldContentSize.width > 0, oldContentSize.height > 0,
              newContentSize.width > 0, newContentSize.height > 0
        else {
            return centeredContentOffset(contentSize: newContentSize, viewportSize: viewportSize)
        }

        let ratioX = contentPoint.x / oldContentSize.width
        let ratioY = contentPoint.y / oldContentSize.height
        let newContentPoint = CGPoint(
            x: ratioX * newContentSize.width,
            y: ratioY * newContentSize.height
        )
        return clampedContentOffset(
            CGPoint(x: anchorInViewport.x - newContentPoint.x, y: anchorInViewport.y - newContentPoint.y),
            contentSize: newContentSize,
            viewportSize: viewportSize
        )
    }

    /// Content offset so ``anchorInViewport`` stays fixed at the given magnification.
    static func anchoredContentOffset(
        anchorInViewport: CGPoint?,
        viewportSize: CGSize,
        pixelSize: CGSize,
        magnification: CGFloat
    ) -> CGPoint {
        let fit = fitScale(imageSize: pixelSize, in: viewportSize)
        let contentSize = CGSize(
            width: pixelSize.width * fit * magnification,
            height: pixelSize.height * fit * magnification
        )
        let anchor = anchorInViewport ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)

        let fitContentSize = CGSize(width: pixelSize.width * fit, height: pixelSize.height * fit)
        let fitImageRect = centeredContentRect(contentSize: fitContentSize, in: viewportSize)
        let normalizedX = (anchor.x - fitImageRect.minX) / max(fitImageRect.width, 1)
        let normalizedY = (anchor.y - fitImageRect.minY) / max(fitImageRect.height, 1)
        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)
        let contentPoint = CGPoint(x: clampedX * contentSize.width, y: clampedY * contentSize.height)

        return clampedContentOffset(
            CGPoint(x: anchor.x - contentPoint.x, y: anchor.y - contentPoint.y),
            contentSize: contentSize,
            viewportSize: viewportSize
        )
    }

    /// Content offset so ``clickInViewport`` stays fixed after switching to 1:1.
    static func oneToOneContentOffset(
        clickInViewport: CGPoint?,
        viewportSize: CGSize,
        pixelSize: CGSize
    ) -> CGPoint {
        let fit = fitScale(imageSize: pixelSize, in: viewportSize)
        let magnification = fit > 0 ? 1.0 / fit : 1.0
        return anchoredContentOffset(
            anchorInViewport: clickInViewport,
            viewportSize: viewportSize,
            pixelSize: pixelSize,
            magnification: magnification
        )
    }

    /// Keep the content point under ``anchorInViewport`` fixed while zooming.
    static func zoomAnchorContentOffset(
        currentContentOffset: CGPoint,
        viewportSize: CGSize,
        oldContentSize: CGSize,
        newContentSize: CGSize,
        anchorInViewport: CGPoint
    ) -> CGPoint {
        let contentPoint = contentPointUnderAnchor(
            anchorInViewport: anchorInViewport,
            contentOffset: currentContentOffset,
            contentSize: oldContentSize
        )
        return contentOffsetKeepingContentPointFixed(
            contentPoint: contentPoint,
            oldContentSize: oldContentSize,
            newContentSize: newContentSize,
            anchorInViewport: anchorInViewport,
            viewportSize: viewportSize
        )
    }
}
