//
//  GeometryPanelView.swift
//  NegSwift
//

import SwiftUI

struct GeometryPanelView: View {
    @Bindable var session: EngineSession
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarSection(title: "Crop", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Crop Tool", isOn: cropToolBinding)
                    .controlSize(.small)

                if session.isCropToolActive {
                    Picker("Ratio", selection: aspectRatioBinding) {
                        ForEach(CropAspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Reset Crop Box") {
                        session.resetCrop()
                    }
                    .controlSize(.small)

                    Text("Click outside the crop box to apply. Exposure stays fixed while you adjust the box.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Turn on Crop Tool to draw and adjust the crop box on the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        session.rotateCounterClockwise()
                    } label: {
                        Label("90° CCW", systemImage: "rotate.left")
                    }
                    .controlSize(.small)

                    Button {
                        session.rotateClockwise()
                    } label: {
                        Label("90° CW", systemImage: "rotate.right")
                    }
                    .controlSize(.small)
                }

                fineRotationRow
            }
        }
        .disabled(session.selectedFrameID == nil)
    }

    private var fineRotationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fine Rotation")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.1f°", -session.currentEdit.fineRotation))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { -session.currentEdit.fineRotation },
                    set: { session.setFineRotation(-$0) }
                ),
                in: -45 ... 45
            )
        }
    }

    private var aspectRatioBinding: Binding<CropAspectRatio> {
        Binding(
            get: { CropAspectRatio.canonical(session.currentEdit.autocropRatio) },
            set: { session.setAutocropRatio($0.rawValue) }
        )
    }

    private var cropToolBinding: Binding<Bool> {
        Binding(
            get: { session.isCropToolActive },
            set: { session.setCropToolActive($0) }
        )
    }
}

#Preview {
    GeometryPanelView(session: .preview, isExpanded: .constant(true))
        .padding()
        .frame(width: 280)
}
