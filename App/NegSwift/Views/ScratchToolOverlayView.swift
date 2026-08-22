//
//  ScratchToolOverlayView.swift
//  NegSwift
//

import SwiftUI

struct ScratchToolOverlayView: View {
    let imagePixelSize: CGSize
    let visibleContentRect: CGRect
    let brushSize: Int
    let inProgressPoints: [CGPoint]
    var onAddPoint: (CGPoint) -> Void
    var onCommit: ([CGPoint]) -> Void
    var onBackspace: () -> Void
    var onEscape: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let imageRect = PreviewCanvasGeometry.aspectFitRect(
                imageSize: imagePixelSize,
                in: geometry.size
            )

            ZStack {
                polylineLayer(imageRect: imageRect)
                    .allowsHitTesting(false)

                ScratchMouseCaptureView(
                    imagePixelSize: imagePixelSize,
                    imageRect: imageRect,
                    interactionRect: ScratchToolOverlayGeometry.scratchInteractionRect(
                        imageRect: imageRect,
                        visibleContentRect: visibleContentRect
                    ),
                    brushSize: brushSize,
                    onAddPoint: onAddPoint,
                    onFinish: { finish(imageRect: imageRect) },
                    onBackspace: onBackspace,
                    onEscape: onEscape
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            ScratchCursor.reset()
        }
    }

    private func finish(imageRect: CGRect) {
        commit(points: inProgressPoints, imageRect: imageRect)
    }

    private func commit(points: [CGPoint], imageRect: CGRect) {
        let deduped = ScratchToolOverlayGeometry.dedupeNormalizedPoints(points, imageRect: imageRect)
        guard !deduped.isEmpty else { return }
        onCommit(deduped)
    }

    @ViewBuilder
    private func polylineLayer(imageRect: CGRect) -> some View {
        let screenPoints = inProgressPoints.map { screenPoint($0, imageRect: imageRect) }
        let bandWidth = ScratchToolOverlayGeometry.scratchBandWidth(
            brushSize: CGFloat(brushSize),
            imageRect: imageRect
        )
        let pointDiameter = ScratchToolOverlayGeometry.pointMarkerDiameter(
            brushSize: CGFloat(brushSize),
            imageRect: imageRect
        )
        let strokeStyle = StrokeStyle(lineWidth: bandWidth, lineCap: .round, lineJoin: .round)
        ZStack {
            if screenPoints.count >= 2 {
                let path = Path { path in
                    path.move(to: screenPoints[0])
                    for point in screenPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                path.stroke(Color.accentColor.opacity(0.35), style: strokeStyle)
                path.stroke(Color.white, lineWidth: 1)
            }
            ForEach(Array(screenPoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: pointDiameter, height: pointDiameter)
                    .position(point)
            }
        }
    }

    private func screenPoint(_ normalized: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }
}

enum ScratchToolOverlayGeometry {
    /// NegPy `HEAL_SIZE_REF` — brush diameter is defined at this reference dimension.
    static let healSizeRef: CGFloat = 1600

    /// Region where scratch hits, cursor hiding, and brush preview are active.
    static func scratchInteractionRect(imageRect: CGRect, visibleContentRect: CGRect) -> CGRect {
        guard !visibleContentRect.isNull, visibleContentRect.width > 0, visibleContentRect.height > 0 else {
            return imageRect
        }
        let intersection = imageRect.intersection(visibleContentRect)
        return intersection.isNull || intersection.width <= 0 || intersection.height <= 0 ? imageRect : intersection
    }

    static func brushScreenRadius(brushSize: CGFloat, imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0, imageRect.height > 0 else { return 0 }
        let maxDim = max(imageRect.width, imageRect.height)
        return (brushSize / (2 * healSizeRef)) * maxDim
    }

    static func scratchBandWidth(brushSize: CGFloat, imageRect: CGRect) -> CGFloat {
        max(1.5, 2 * brushScreenRadius(brushSize: brushSize, imageRect: imageRect))
    }

    static func pointMarkerDiameter(brushSize: CGFloat, imageRect: CGRect) -> CGFloat {
        max(6, 2 * brushScreenRadius(brushSize: brushSize, imageRect: imageRect))
    }

    static func dedupeNormalizedPoints(
        _ points: [CGPoint],
        imageRect: CGRect,
        minScreenDistance: CGFloat = 2
    ) -> [CGPoint] {
        var deduped: [CGPoint] = []
        for point in points {
            if let last = deduped.last {
                let lastScreen = screenPoint(last, imageRect: imageRect)
                let newScreen = screenPoint(point, imageRect: imageRect)
                if hypot(newScreen.x - lastScreen.x, newScreen.y - lastScreen.y) <= minScreenDistance {
                    continue
                }
            }
            deduped.append(point)
        }
        return deduped
    }

    /// Map a click in overlay coordinates to normalized image space (0–1).
    static func normalizedPoint(_ location: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        guard imageRect.contains(location) else { return nil }
        let nx = (location.x - imageRect.minX) / imageRect.width
        let ny = (location.y - imageRect.minY) / imageRect.height
        return CGPoint(x: nx, y: ny)
    }

    /// Map local image-target coordinates (0…width/height) to normalized space.
    static func normalizedPointInImage(_ location: CGPoint, imageSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        guard location.x >= 0, location.y >= 0,
              location.x <= imageSize.width, location.y <= imageSize.height else { return nil }
        return CGPoint(x: location.x / imageSize.width, y: location.y / imageSize.height)
    }

    private static func screenPoint(_ normalized: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }
}
