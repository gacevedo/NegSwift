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
                    .help("Draw and adjust the crop box on the preview (⇧C)")

                if session.isCropToolActive {
                    Picker("Ratio", selection: aspectRatioBinding) {
                        ForEach(CropAspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.menu)

                    if session.currentEdit.autoExposure {
                        Toggle("Apply Auto Density while cropping", isOn: autoDensityUsesCropBinding)
                            .controlSize(.small)
                    }

                    Button("Reset Crop Box") {
                        session.resetCrop()
                    }
                    .controlSize(.small)

                    Text(cropToolHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Turn on Crop Tool to draw and adjust the crop box on the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    geometryIconButton(
                        title: "Rotate 90° counter-clockwise",
                        systemImage: "rotate.left"
                    ) {
                        session.rotateCounterClockwise()
                    }

                    geometryIconButton(
                        title: "Rotate 90° clockwise",
                        systemImage: "rotate.right"
                    ) {
                        session.rotateClockwise()
                    }

                    geometryIconButton(
                        title: "Flip horizontal",
                        systemImage: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right"
                    ) {
                        session.toggleFlipHorizontal()
                    }

                    geometryIconButton(
                        title: "Flip vertical",
                        systemImage: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right",
                        rotationDegrees: 90
                    ) {
                        session.toggleFlipVertical()
                    }
                }

                fineRotationRow
            }
        }
        .disabled(session.selectedFrameID == nil)
    }

    private func geometryIconButton(
        title: String,
        systemImage: String,
        rotationDegrees: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .rotationEffect(.degrees(rotationDegrees))
        }
        .controlSize(.small)
        .help(title)
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
            GradientSlider(
                value: Binding(
                    get: { -session.currentEdit.fineRotation },
                    set: { session.setFineRotation(-$0) }
                ),
                style: .fineRotation,
                range: EditControlRanges.fineRotation,
                defaultValue: EditControlDefaults.fineRotation
            )
        }
    }

    private var cropToolHint: String {
        if session.currentEdit.autoExposure && session.currentEdit.autoDensityUsesCrop {
            "Click outside the box to apply. Auto Density follows the crop box as you drag."
        } else {
            "Click outside the box to apply. Full frame loads first; tone stays fixed while adjusting."
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
            set: { newValue in
                guard newValue != session.isCropToolActive else { return }
                Task { @MainActor in
                    await Task.yield()
                    session.setCropToolActive(newValue)
                }
            }
        )
    }

    private var autoDensityUsesCropBinding: Binding<Bool> {
        Binding(
            get: { session.currentEdit.autoDensityUsesCrop },
            set: { session.setAutoDensityUsesCrop($0) }
        )
    }
}

#Preview {
    GeometryPanelView(session: .preview, isExpanded: .constant(true))
        .padding()
        .frame(width: 280)
}
