//
//  PreviewCanvasView.swift
//  NegSwift
//

import AppKit
import SwiftUI

struct PreviewCanvasView: View {
    @Bindable var session: EngineSession
    @Binding var zoomMode: PreviewZoomMode
    let image: NSImage

    @State private var scrollPosition = ScrollPosition()
    @State private var pendingOneToOneClick: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                switch zoomMode {
                case .fit:
                    fitCanvas(in: size)
                case .oneToOne:
                    oneToOneCanvas(viewportSize: size)
                }

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
            .overlay(alignment: .bottomLeading) {
                canvasHUD
            }
            .onChange(of: zoomMode) { _, newValue in
                guard newValue == .oneToOne else { return }
                applyOneToOneScroll(viewportSize: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fitCanvas(in size: CGSize) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(fitDoubleClickGesture())

            toolOverlays
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func oneToOneCanvas(viewportSize: CGSize) -> some View {
        let pixelSize = displayedPixelSize
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: pixelSize.width, height: pixelSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        zoomToFit()
                    }

                toolOverlays
                    .frame(width: pixelSize.width, height: pixelSize.height)
            }
            .frame(width: pixelSize.width, height: pixelSize.height)
        }
        .scrollDisabled(session.isScratchToolActive)
        .scrollPosition($scrollPosition)
    }

    @ViewBuilder
    private var toolOverlays: some View {
        if session.isCropToolActive, session.isCropOverlayReady {
            cropOverlay
        }
        if session.isScratchToolActive {
            scratchOverlay
        }
    }

    private func fitDoubleClickGesture() -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                zoomToOneToOne(at: value.location)
            }
    }

    private func zoomToOneToOne(at location: CGPoint) {
        guard !session.isCropToolActive, !session.isScratchToolActive else { return }
        pendingOneToOneClick = location
        zoomMode = .oneToOne
    }

    private func zoomToFit() {
        guard !session.isCropToolActive, !session.isScratchToolActive else { return }
        pendingOneToOneClick = nil
        zoomMode = .fit
    }

    private func applyOneToOneScroll(viewportSize: CGSize) {
        let pixelSize = displayedPixelSize
        let offset = PreviewCanvasGeometry.oneToOneScrollOffset(
            clickInViewport: pendingOneToOneClick,
            viewportSize: viewportSize,
            pixelSize: pixelSize
        )
        Task { @MainActor in
            await Task.yield()
            scrollPosition.scrollTo(x: offset.x, y: offset.y)
            pendingOneToOneClick = nil
        }
    }

    private var cropOverlay: some View {
        CropOverlayView(
            cropRect: cropBinding,
            aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
            imagePixelSize: session.previewPixelSize ?? image.size,
            onClickOutside: { session.setCropToolActive(false) }
        )
    }

    private var scratchOverlay: some View {
        ScratchToolOverlayView(
            imagePixelSize: session.previewPixelSize ?? image.size,
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

    private var canvasHUD: some View {
        HStack(spacing: 8) {
            Text(zoomMode.label)
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
        .accessibilityIdentifier("negSwift.canvasZoomLabel")
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
}
