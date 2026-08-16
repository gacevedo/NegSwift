//
//  ScratchToolOverlayView.swift
//  NegSwift
//

import SwiftUI

struct ScratchToolOverlayView: View {
    let imagePixelSize: CGSize
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
        ZStack {
            if screenPoints.count >= 2 {
                Path { path in
                    path.move(to: screenPoints[0])
                    for point in screenPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)
            }
            ForEach(Array(screenPoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
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
