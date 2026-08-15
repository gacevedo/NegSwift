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
                if session.isCropToolActive {
                    CropOverlayView(
                        cropRect: cropBinding,
                        aspectRatio: CropAspectRatio.canonical(session.currentEdit.autocropRatio),
                        onClickOutside: { session.setCropToolActive(false) }
                    )
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
