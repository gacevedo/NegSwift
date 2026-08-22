//
//  CropOverlayView.swift
//  NegSwift
//

import SwiftUI

struct CropOverlayView: View {
    @Binding var cropRect: NormalizedRect
    let aspectRatio: CropAspectRatio
    let imagePixelSize: CGSize
    var onClickOutside: () -> Void = {}

    @State private var dragRect: NormalizedRect?
    @State private var dragStartRect: NormalizedRect?
    @State private var dragStartHandlePoint: CGPoint?
    @State private var activeHandle: CropHandle?

    private let cornerHandleSize: CGFloat = 12
    private let edgeHandleShort: CGFloat = 8
    private let edgeHandleLong: CGFloat = 28
    private let minSpan: Double = 0.05

    private var activeRect: NormalizedRect {
        dragRect ?? cropRect
    }

    var body: some View {
        GeometryReader { geometry in
            let container = geometry.size
            let imageRect = Self.aspectFitRect(
                imageAspect: imagePixelSize.width / max(imagePixelSize.height, 1),
                in: container
            )
            let cropScreenRect = screenRect(for: activeRect, in: imageRect)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: container))
                    path.addRect(cropScreenRect)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: max(cropScreenRect.width, 1), height: max(cropScreenRect.height, 1))
                    .position(x: cropScreenRect.midX, y: cropScreenRect.midY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(imageRect: imageRect))

                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleView(handle, cropScreenRect: cropScreenRect, imageRect: imageRect)
                }
            }
            .contentShape(Rectangle())
            .gesture(outsideTapGesture(cropScreenRect: cropScreenRect))
        }
    }

    private func outsideTapGesture(cropScreenRect rect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = value.location
                guard !rect.contains(point), !isNearHandle(point, cropScreenRect: rect) else { return }
                onClickOutside()
            }
    }

    private func isNearHandle(_ point: CGPoint, cropScreenRect rect: CGRect) -> Bool {
        for handle in CropHandle.allCases {
            if handleRect(handle, in: rect, grabMultiplier: 1.5).contains(point) {
                return true
            }
        }
        return false
    }

    private func handleRect(_ handle: CropHandle, in cropRect: CGRect, grabMultiplier: CGFloat = 1) -> CGRect {
        let point = handle.point(in: cropRect)
        let size = handle.frameSize(
            cornerSize: cornerHandleSize,
            edgeShort: edgeHandleShort,
            edgeLong: edgeHandleLong
        )
        let width = size.width * grabMultiplier
        let height = size.height * grabMultiplier
        return CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = activeRect
                }
                guard let start = dragStartRect else { return }
                let dx = Double(value.translation.width / imageRect.width)
                let dy = Double(value.translation.height / imageRect.height)
                dragRect = NormalizedRect(
                    x1: start.x1 + dx,
                    y1: start.y1 + dy,
                    x2: start.x2 + dx,
                    y2: start.y2 + dy
                ).clamped()
            }
            .onEnded { _ in
                commitDrag()
            }
    }

    @ViewBuilder
    private func handleView(_ handle: CropHandle, cropScreenRect rect: CGRect, imageRect: CGRect) -> some View {
        let point = handle.point(in: rect)
        let size = handle.frameSize(
            cornerSize: cornerHandleSize,
            edgeShort: edgeHandleShort,
            edgeLong: edgeHandleLong
        )
        let handleShape = Group {
            if handle.isCorner {
                Circle()
                    .fill(Color.white)
            } else {
                Rectangle()
                    .fill(Color.white)
            }
        }
        handleShape
            .frame(width: size.width, height: size.height)
            .position(x: point.x, y: point.y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if activeHandle == nil {
                            activeHandle = handle
                            dragStartRect = activeRect
                            dragStartHandlePoint = handle.point(in: screenRect(for: activeRect, in: imageRect))
                        }
                        guard activeHandle == handle,
                              let start = dragStartRect,
                              let startPoint = dragStartHandlePoint
                        else { return }
                        let loc = CGPoint(
                            x: startPoint.x + value.translation.width,
                            y: startPoint.y + value.translation.height
                        )
                        dragRect = resized(from: start, handle: handle, to: loc, imageRect: imageRect)
                    }
                    .onEnded { _ in
                        activeHandle = nil
                        dragStartRect = nil
                        dragStartHandlePoint = nil
                        commitDrag()
                    }
            )
    }

    private func commitDrag() {
        if let dragRect {
            cropRect = dragRect
        }
        self.dragRect = nil
        dragStartRect = nil
        dragStartHandlePoint = nil
    }

    private func resized(
        from start: NormalizedRect,
        handle: CropHandle,
        to point: CGPoint,
        imageRect: CGRect
    ) -> NormalizedRect {
        let nx = Double(min(max((point.x - imageRect.minX) / imageRect.width, 0), 1))
        let ny = Double(min(max((point.y - imageRect.minY) / imageRect.height, 0), 1))

        var x1 = start.x1
        var y1 = start.y1
        var x2 = start.x2
        var y2 = start.y2

        switch handle {
        case .topLeft:
            x1 = nx; y1 = ny
        case .topRight:
            x2 = nx; y1 = ny
        case .bottomRight:
            x2 = nx; y2 = ny
        case .bottomLeft:
            x1 = nx; y2 = ny
        case .top:
            y1 = ny
            x1 = start.x1
            x2 = start.x2
            y2 = start.y2
        case .bottom:
            y2 = ny
            x1 = start.x1
            x2 = start.x2
            y1 = start.y1
        case .left:
            x1 = nx
            y1 = start.y1
            y2 = start.y2
            x2 = start.x2
        case .right:
            x2 = nx
            y1 = start.y1
            y2 = start.y2
            x1 = start.x1
        }

        if x2 < x1 { swap(&x1, &x2) }
        if y2 < y1 { swap(&y1, &y2) }

        if x2 - x1 < minSpan { x2 = x1 + minSpan }
        if y2 - y1 < minSpan { y2 = y1 + minSpan }

        if let wh = aspectRatio.widthOverHeight {
            let imageAspect = Double(imagePixelSize.width / max(imagePixelSize.height, 1))
            let baseTarget = wh / imageAspect
            let orientedTarget = start.height > start.width
                ? min(baseTarget, 1.0 / baseTarget)
                : max(baseTarget, 1.0 / baseTarget)

            switch handle {
            case .topLeft, .topRight, .bottomRight, .bottomLeft:
                var w = x2 - x1
                var h = y2 - y1
                if w / h > orientedTarget {
                    w = h * orientedTarget
                } else {
                    h = w / orientedTarget
                }
                switch handle {
                case .topLeft:
                    x1 = x2 - w; y1 = y2 - h
                case .topRight:
                    x2 = x1 + w; y1 = y2 - h
                case .bottomRight:
                    x2 = x1 + w; y2 = y1 + h
                case .bottomLeft:
                    x1 = x2 - w; y2 = y1 + h
                default:
                    break
                }
            case .top, .bottom:
                let anchorY = handle == .top ? start.y2 : start.y1
                var h = abs(anchorY - (handle == .top ? y1 : y2))
                if h < minSpan { h = minSpan }
                let w = h * orientedTarget
                let cx = (start.x1 + start.x2) / 2
                x1 = cx - w / 2
                x2 = cx + w / 2
                if handle == .top {
                    y2 = anchorY
                    y1 = y2 - h
                } else {
                    y1 = anchorY
                    y2 = y1 + h
                }
            case .left, .right:
                let anchorX = handle == .left ? start.x2 : start.x1
                var w = abs(anchorX - (handle == .left ? x1 : x2))
                if w < minSpan { w = minSpan }
                let h = w / orientedTarget
                let cy = (start.y1 + start.y2) / 2
                y1 = cy - h / 2
                y2 = cy + h / 2
                if handle == .left {
                    x2 = anchorX
                    x1 = x2 - w
                } else {
                    x1 = anchorX
                    x2 = x1 + w
                }
            }
        }

        return NormalizedRect(x1: x1, y1: y1, x2: x2, y2: y2).clamped()
    }

    private func screenRect(for normalized: NormalizedRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalized.x1 * imageRect.width,
            y: imageRect.minY + normalized.y1 * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    private static func aspectFitRect(imageAspect: CGFloat, in container: CGSize) -> CGRect {
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
}

private enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        case .top, .right, .bottom, .left: false
        }
    }

    func frameSize(cornerSize: CGFloat, edgeShort: CGFloat, edgeLong: CGFloat) -> CGSize {
        if isCorner {
            return CGSize(width: cornerSize, height: cornerSize)
        }
        switch self {
        case .top, .bottom:
            return CGSize(width: edgeLong, height: edgeShort)
        case .left, .right:
            return CGSize(width: edgeShort, height: edgeLong)
        default:
            return CGSize(width: cornerSize, height: cornerSize)
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        let midX = rect.midX
        let midY = rect.midY
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: midY)
        }
    }
}
