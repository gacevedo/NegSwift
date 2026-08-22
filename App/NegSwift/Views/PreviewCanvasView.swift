//
//  PreviewCanvasView.swift
//  NegSwift
//

import AppKit
import SwiftUI

struct PreviewCanvasView: View {
    @Bindable var session: EngineSession
    @Binding var zoom: PreviewCanvasZoom
    let zoomToggleNonce: Int
    let image: NSImage

    @State private var interaction = CanvasInteractionState()
    @State private var viewportSize = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pixelSize = displayedPixelSize
            let fitRect = PreviewCanvasGeometry.aspectFitRect(imageSize: pixelSize, in: size)
            let atFit = zoom.isAtFit()
            let contentSize = atFit
                ? fitRect.size
                : zoom.contentSize(imageSize: pixelSize, viewport: size)
            let contentOrigin = atFit
                ? fitRect.origin
                : PreviewCanvasGeometry.clampedContentOffset(
                    interaction.contentOffset,
                    contentSize: contentSize,
                    viewportSize: size
                )

            canvasViewport(
                contentSize: contentSize,
                viewportSize: size,
                contentOrigin: contentOrigin,
                pixelSize: pixelSize
            )
            .onAppear {
                publishCanvasZoomLabel(viewportSize: size, pixelSize: pixelSize)
            }
            .onChange(of: zoom.magnification) { _, _ in
                publishCanvasZoomLabel(viewportSize: size, pixelSize: pixelSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("negSwift.previewCanvas")
    }

    @ViewBuilder
    private func canvasViewport(
        contentSize: CGSize,
        viewportSize: CGSize,
        contentOrigin: CGPoint,
        pixelSize: CGSize
    ) -> some View {
        let stack = ZStack(alignment: .topLeading) {
            canvasContent(
                contentSize: contentSize,
                visibleContentRect: PreviewCanvasGeometry.visibleContentRect(
                    contentSize: contentSize,
                    contentOffset: contentOrigin,
                    viewportSize: viewportSize
                )
            )
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .offset(x: contentOrigin.x, y: contentOrigin.y)

            if session.isLoadingCropPreview {
                ZStack {
                    Color.black.opacity(0.25)
                    ProgressView("Preparing crop view…")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            canvasHUD(viewportSize: viewportSize, pixelSize: pixelSize)
        }
        .background {
            CanvasZoomGestureView(
                isZoomEnabled: zoomGesturesEnabled,
                isScrollPanEnabled: canScrollPan(contentSize: contentSize, viewportSize: viewportSize),
                onZoomBy: { factor, anchor in
                    applyZoomFactor(factor, anchorInViewport: anchor, viewportSize: viewportSize, pixelSize: pixelSize)
                },
                onScrollPanBy: { delta in
                    applyScrollPan(delta, contentSize: contentSize, viewportSize: viewportSize)
                }
            )
        }
        .onAppear {
            self.viewportSize = viewportSize
            syncContentOffset(pixelSize: pixelSize, viewportSize: viewportSize)
            applyUITestMaxZoomIfNeeded(viewportSize: viewportSize, pixelSize: pixelSize)
        }
        .onChange(of: viewportSize) { _, newValue in
            self.viewportSize = newValue
            syncContentOffset(pixelSize: pixelSize, viewportSize: newValue)
            applyUITestMaxZoomIfNeeded(viewportSize: newValue, pixelSize: pixelSize)
        }
        .onChange(of: session.selectedFrameID) { _, _ in
            syncContentOffset(pixelSize: pixelSize, viewportSize: viewportSize)
        }
        .onChange(of: pixelSize) { _, _ in
            syncContentOffset(pixelSize: pixelSize, viewportSize: viewportSize)
            applyUITestMaxZoomIfNeeded(viewportSize: viewportSize, pixelSize: pixelSize)
        }
        .onChange(of: zoomToggleNonce) { _, _ in
            performMenuToggle(viewportSize: viewportSize, pixelSize: pixelSize)
        }

        if zoomGesturesEnabled {
            stack
                .contentShape(Rectangle())
                .gesture(canvasDoubleClickGesture())
                .gesture(panGesture(contentSize: contentSize, viewportSize: viewportSize))
        } else {
            stack
        }
    }

    @ViewBuilder
    private func canvasContent(contentSize: CGSize, visibleContentRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: contentSize.width, height: contentSize.height)

            toolOverlays(visibleContentRect: visibleContentRect)
                .frame(width: contentSize.width, height: contentSize.height)
        }
    }

    @ViewBuilder
    private func toolOverlays(visibleContentRect: CGRect) -> some View {
        if session.isCropToolActive, session.isCropOverlayReady {
            cropOverlay
        }
        if session.isScratchToolActive {
            scratchOverlay(visibleContentRect: visibleContentRect)
        }
    }

    private func canvasDoubleClickGesture() -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if zoom.isAtFit() {
                    zoomToOneToOne(at: value.location)
                } else {
                    zoomToFit()
                }
            }
    }

    private func panGesture(contentSize: CGSize, viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard canDragPan(contentSize: contentSize, viewportSize: viewportSize) else { return }
                if !interaction.isPanDragging {
                    interaction.isPanDragging = true
                    interaction.panDragStartOffset = interaction.contentOffset
                }
                interaction.contentOffset = PreviewCanvasGeometry.clampedContentOffset(
                    CGPoint(
                        x: interaction.panDragStartOffset.x + value.translation.width,
                        y: interaction.panDragStartOffset.y + value.translation.height
                    ),
                    contentSize: contentSize,
                    viewportSize: viewportSize
                )
            }
            .onEnded { _ in
                interaction.isPanDragging = false
            }
    }

    private func canDragPan(contentSize: CGSize, viewportSize: CGSize) -> Bool {
        !session.isCropToolActive
            && !session.isScratchToolActive
            && PreviewCanvasGeometry.contentOverflows(contentSize: contentSize, viewportSize: viewportSize)
    }

    private func canScrollPan(contentSize: CGSize, viewportSize: CGSize) -> Bool {
        zoomGesturesEnabled
            && PreviewCanvasGeometry.contentOverflows(contentSize: contentSize, viewportSize: viewportSize)
    }

    private var zoomGesturesEnabled: Bool {
        !session.isCropToolActive && !session.isScratchToolActive
    }

    private func syncContentOffset(pixelSize: CGSize, viewportSize: CGSize) {
        guard !interaction.isPanDragging else { return }
        let fitRect = PreviewCanvasGeometry.aspectFitRect(imageSize: pixelSize, in: viewportSize)
        if zoom.isAtFit() {
            interaction.contentOffset = fitRect.origin
            return
        }
        let contentSize = zoom.contentSize(imageSize: pixelSize, viewport: viewportSize)
        interaction.contentOffset = PreviewCanvasGeometry.clampedContentOffset(
            interaction.contentOffset,
            contentSize: contentSize,
            viewportSize: viewportSize
        )
    }

    private func effectiveContentOffset(pixelSize: CGSize, viewportSize: CGSize) -> CGPoint {
        if zoom.isAtFit() {
            return PreviewCanvasGeometry.aspectFitRect(imageSize: pixelSize, in: viewportSize).origin
        }
        return interaction.contentOffset
    }

    private func performMenuToggle(viewportSize: CGSize, pixelSize: CGSize) {
        guard zoomGesturesEnabled else { return }
        if zoom.isAtFit() {
            let anchor = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
            zoom.setOneToOne(imageSize: pixelSize, viewport: viewportSize)
            interaction.contentOffset = PreviewCanvasGeometry.anchoredContentOffset(
                anchorInViewport: anchor,
                viewportSize: viewportSize,
                pixelSize: pixelSize,
                magnification: zoom.magnification
            )
        } else {
            zoom.setFit()
            syncContentOffset(pixelSize: pixelSize, viewportSize: viewportSize)
        }
    }

    private func applyZoomFactor(
        _ factor: CGFloat,
        anchorInViewport: CGPoint,
        viewportSize: CGSize,
        pixelSize: CGSize
    ) {
        guard zoomGesturesEnabled, factor > 0 else { return }

        let oldMagnification = zoom.magnification
        let newMagnification = zoom.clampedMagnification(
            oldMagnification * factor,
            imageSize: pixelSize,
            viewport: viewportSize
        )
        guard abs(newMagnification - oldMagnification) > 0.0001 else { return }

        let oldContentSize = zoom.contentSize(imageSize: pixelSize, viewport: viewportSize)
        let contentPoint = PreviewCanvasGeometry.contentPointUnderAnchor(
            anchorInViewport: anchorInViewport,
            contentOffset: effectiveContentOffset(pixelSize: pixelSize, viewportSize: viewportSize),
            contentSize: oldContentSize
        )

        zoom.magnification = newMagnification
        let newContentSize = zoom.contentSize(imageSize: pixelSize, viewport: viewportSize)
        interaction.contentOffset = PreviewCanvasGeometry.contentOffsetKeepingContentPointFixed(
            contentPoint: contentPoint,
            oldContentSize: oldContentSize,
            newContentSize: newContentSize,
            anchorInViewport: anchorInViewport,
            viewportSize: viewportSize
        )
    }

    private func applyScrollPan(_ delta: CGPoint, contentSize: CGSize, viewportSize: CGSize) {
        interaction.contentOffset = PreviewCanvasGeometry.clampedContentOffset(
            CGPoint(
                x: interaction.contentOffset.x + delta.x,
                y: interaction.contentOffset.y + delta.y
            ),
            contentSize: contentSize,
            viewportSize: viewportSize
        )
    }

    private func zoomToOneToOne(at location: CGPoint) {
        guard zoomGesturesEnabled else { return }
        let pixelSize = displayedPixelSize
        let viewport = viewportSize
        zoom.setOneToOne(imageSize: pixelSize, viewport: viewport)
        interaction.contentOffset = PreviewCanvasGeometry.anchoredContentOffset(
            anchorInViewport: location,
            viewportSize: viewport,
            pixelSize: pixelSize,
            magnification: zoom.magnification
        )
    }

    private func zoomToFit() {
        guard zoomGesturesEnabled else { return }
        zoom.setFit()
        syncContentOffset(pixelSize: displayedPixelSize, viewportSize: viewportSize)
    }

    private var cropOverlay: some View {
        CropOverlayView(
            cropRect: cropBinding,
            aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
            imagePixelSize: session.previewPixelSize ?? image.size,
            onClickOutside: applyCrop
        )
        .background {
            CropKeyCaptureView(onApply: applyCrop)
        }
    }

    private func applyCrop() {
        session.setCropToolActive(false)
    }

    private func scratchOverlay(visibleContentRect: CGRect) -> some View {
        ScratchToolOverlayView(
            imagePixelSize: session.previewPixelSize ?? image.size,
            visibleContentRect: visibleContentRect,
            brushSize: session.currentEdit.manualDustSize,
            inProgressPoints: session.scratchInProgressPoints,
            onAddPoint: { session.appendScratchInProgressPoint($0) },
            onCommit: { points in
                session.scratchInProgressPoints = []
                Task {
                    await session.commitScratchStroke(points: points)
                }
            },
            onBackspace: { session.removeLastScratchInProgressPoint() },
            onEscape: { session.handleScratchEscape() }
        )
    }

    private func canvasHUD(viewportSize: CGSize, pixelSize: CGSize) -> some View {
        let zoomLabel = zoom.label(imageSize: pixelSize, viewport: viewportSize)
        return HStack(spacing: 8) {
            Text(zoomLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if let pixelSize = session.previewPixelSize {
                Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
    }

    private var displayedPixelSize: CGSize {
        session.previewPixelSize ?? image.size
    }

    private var cropBinding: Binding<NormalizedRect> {
        Binding(
            get: { session.currentEdit.manualCropRect ?? .full },
            set: { session.setManualCropRect($0) }
        )
    }

    private func applyUITestMaxZoomIfNeeded(viewportSize: CGSize, pixelSize: CGSize) {
        guard UITestSupport.isActive,
              UITestSupport.canvasZoomToMaxDisplayScale,
              zoom.isAtFit(),
              viewportSize.width > 0,
              viewportSize.height > 0,
              pixelSize.width > 0,
              pixelSize.height > 0
        else { return }
        let fit = zoom.fitScale(imageSize: pixelSize, viewport: viewportSize)
        let maxDisplayMagnification = fit > 0 ? PreviewCanvasZoom.maxDisplayScale / fit : 1.0
        // Tiny fixtures already exceed 400% at fit; use 4× fit so content overflows for pan/cursor tests.
        zoom.magnification = max(4.0, maxDisplayMagnification)
        interaction.contentOffset = PreviewCanvasGeometry.anchoredContentOffset(
            anchorInViewport: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2),
            viewportSize: viewportSize,
            pixelSize: pixelSize,
            magnification: zoom.magnification
        )
        publishCanvasZoomLabel(viewportSize: viewportSize, pixelSize: pixelSize)
    }

    private func publishCanvasZoomLabel(viewportSize: CGSize, pixelSize: CGSize) {
        UITestSupport.reportCanvasZoomLabel(
            zoom.label(imageSize: pixelSize, viewport: viewportSize)
        )
    }
}
