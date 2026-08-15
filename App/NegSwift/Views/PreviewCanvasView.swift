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
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if session.isCropToolActive, session.isCropOverlayReady {
                    CropOverlayView(
                        cropRect: cropBinding,
                        aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
                        onClickOutside: { session.setCropToolActive(false) }
                    )
                }
            }
            .overlay {
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
    }

    private var cropBinding: Binding<NormalizedRect> {
        Binding(
            get: { session.currentEdit.manualCropRect ?? .full },
            set: { session.setManualCropRect($0) }
        )
    }
}
