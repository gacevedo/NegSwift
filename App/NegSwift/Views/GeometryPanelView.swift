//
//  GeometryPanelView.swift
//  NegSwift
//

import SwiftUI

struct GeometryPanelView: View {
    @Bindable var session: EngineSession
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarSection(title: "Crop & Rotate", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    cropToolButton

                    geometryIconButton(
                        title: "Rotate 90° clockwise",
                        systemImage: "rotate.right"
                    ) {
                        session.rotateClockwise()
                    }

                    geometryIconButton(
                        title: "Rotate 90° counter-clockwise",
                        systemImage: "rotate.left"
                    ) {
                        session.rotateCounterClockwise()
                    }

                    geometryIconButton(
                        title: "Flip horizontal",
                        systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                    ) {
                        session.toggleFlipHorizontal()
                    }

                    geometryIconButton(
                        title: "Flip vertical",
                        systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down"
                    ) {
                        session.toggleFlipVertical()
                    }
                }

                cropToolControls

                fineRotationRow
            }
        }
        .disabled(session.selectedFrameID == nil)
    }

    @ViewBuilder
    private var cropToolControls: some View {
        if session.isCropToolActive {
            Picker("Ratio", selection: aspectRatioBinding) {
                ForEach(CropAspectRatio.allCases) { ratio in
                    Text(ratio.pickerLabel).tag(ratio)
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
    }

    private var cropToolButton: some View {
        Button(action: toggleCropTool) {
            Label("Crop Tool", systemImage: "crop")
                .labelStyle(.iconOnly)
        }
        .controlSize(.small)
        .tint(session.isCropToolActive ? .accentColor : nil)
        .help("Draw and adjust the crop box on the preview (⇧C)")
        .accessibilityIdentifier("negSwift.cropToolToggle")
    }

    private func geometryIconButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .controlSize(.small)
        .help(title)
    }

    private func toggleCropTool() {
        Task { @MainActor in
            await Task.yield()
            session.setCropToolActive(!session.isCropToolActive)
        }
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
            "Click outside the box or press Enter to apply. Auto Density follows the crop box as you drag."
        } else {
            "Click outside the box or press Enter to apply. Full frame loads first; tone stays fixed while adjusting."
        }
    }

    private var aspectRatioBinding: Binding<CropAspectRatio> {
        Binding(
            get: { CropAspectRatio.canonical(session.currentEdit.autocropRatio) },
            set: { session.setAutocropRatio($0.rawValue) }
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
