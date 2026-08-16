//
//  PreviewCanvasView.swift
//  NegSwift
//

import AppKit
import SwiftUI

struct PreviewCanvasView: View {
    @Bindable var session: EngineSession
    let image: NSImage

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if session.isCropToolActive, session.isCropOverlayReady {
                    CropOverlayView(
                        cropRect: cropBinding,
                        aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
                        imagePixelSize: session.previewPixelSize ?? image.size,
                        onClickOutside: { session.setCropToolActive(false) }
                    )
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
                if let pixelSize = session.previewPixelSize {
                    Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cropBinding: Binding<NormalizedRect> {
        Binding(
            get: { session.currentEdit.manualCropRect ?? .full },
            set: { session.setManualCropRect($0) }
        )
    }
}
