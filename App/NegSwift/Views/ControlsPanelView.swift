//
//  ControlsPanelView.swift
//  NegSwift
//

import SwiftUI

struct ControlsPanelView: View {
    @Bindable var session: EngineSession
    @Binding var toneExpanded: Bool
    @Binding var colorExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarSection(title: "Tone", isExpanded: $toneExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    autoRow
                    sliderRow("Print Density", value: densityBinding, range: EditControlRanges.density, defaultValue: EditControlDefaults.density, format: "%.2f")
                    sliderRow("ISO-R Grade", value: gradeBinding, range: EditControlRanges.grade, defaultValue: EditControlDefaults.grade, format: "%.0f")
                    sliderRow("Chroma", value: saturationBinding, range: EditControlRanges.saturation, defaultValue: EditControlDefaults.saturation, format: "%.2f")
                }
            }

            SidebarSection(title: "Color", isExpanded: $colorExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow("Cyan", value: wbCyanBinding, range: EditControlRanges.whiteBalance, defaultValue: EditControlDefaults.whiteBalance, format: "%.2f")
                    sliderRow("Magenta", value: wbMagentaBinding, range: EditControlRanges.whiteBalance, defaultValue: EditControlDefaults.whiteBalance, format: "%.2f")
                    sliderRow("Yellow", value: wbYellowBinding, range: EditControlRanges.whiteBalance, defaultValue: EditControlDefaults.whiteBalance, format: "%.2f")
                }
            }
        }
        .disabled(session.selectedFrameID == nil)
    }

    private var autoRow: some View {
        HStack(spacing: 8) {
            Toggle("Auto Density", isOn: autoExposureBinding)
                .controlSize(.small)
            Toggle("Auto Grade", isOn: autoGradeBinding)
                .controlSize(.small)
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultValue: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ResetDefaultSlider(value: value, range: range, defaultValue: defaultValue)
        }
    }

    private var densityBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.density },
            set: { session.setDensity($0) }
        )
    }

    private var gradeBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.grade },
            set: { session.setGrade($0) }
        )
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.saturation },
            set: { session.setSaturation($0) }
        )
    }

    private var wbCyanBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.wbCyan },
            set: { session.setWBCyan($0) }
        )
    }

    private var wbMagentaBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.wbMagenta },
            set: { session.setWBMagenta($0) }
        )
    }

    private var wbYellowBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.wbYellow },
            set: { session.setWBYellow($0) }
        )
    }

    private var autoExposureBinding: Binding<Bool> {
        Binding(
            get: { session.currentEdit.autoExposure },
            set: { session.setAutoExposure($0) }
        )
    }

    private var autoGradeBinding: Binding<Bool> {
        Binding(
            get: { session.currentEdit.autoNormalizeContrast },
            set: { session.setAutoNormalizeContrast($0) }
        )
    }
}

#Preview {
    ControlsPanelView(session: .preview, toneExpanded: .constant(true), colorExpanded: .constant(false))
        .padding()
        .frame(width: 280)
}
