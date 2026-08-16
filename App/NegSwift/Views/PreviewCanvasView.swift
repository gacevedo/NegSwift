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

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                switch zoomMode {
                case .fit:
                    fitCanvas(in: size)
                case .oneToOne:
                    oneToOneCanvas
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fitCanvas(in size: CGSize) -> some View {
        ZStack {
            zoomOnDoubleClick(
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            )
            .frame(width: size.width, height: size.height)

            if session.isCropToolActive, session.isCropOverlayReady {
                cropOverlay
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var oneToOneCanvas: some View {
        let pixelSize = displayedPixelSize
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                zoomOnDoubleClick(
                    Image(nsImage: image)
                        .resizable()
                )
                .frame(width: pixelSize.width, height: pixelSize.height)

                if session.isCropToolActive, session.isCropOverlayReady {
                    cropOverlay
                        .frame(width: pixelSize.width, height: pixelSize.height)
                }
            }
            .frame(width: pixelSize.width, height: pixelSize.height)
        }
    }

    private func zoomOnDoubleClick<Content: View>(_ content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                toggleZoomMode()
            }
    }

    private func toggleZoomMode() {
        guard !session.isCropToolActive else { return }
        zoomMode.toggle()
    }

    private var cropOverlay: some View {
        CropOverlayView(
            cropRect: cropBinding,
            aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
            imagePixelSize: session.previewPixelSize ?? image.size,
            onClickOutside: { session.setCropToolActive(false) }
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
