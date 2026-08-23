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
                    if session.currentEdit.autoExposure {
                        meteringSection
                    }
                    gradientSliderRow(
                        "Print Density",
                        style: .density,
                        value: densityBinding,
                        range: EditControlRanges.density,
                        defaultValue: EditControlDefaults.density,
                        format: "%.2f"
                    )
                    zoneDensityRow
                    gradientSliderRow(
                        "ISO-R Grade",
                        style: .grade,
                        value: gradeBinding,
                        range: EditControlRanges.grade,
                        defaultValue: EditControlDefaults.grade,
                        format: "%.0f"
                    )
                    splitGradeRow
                    gradientSliderRow(
                        "Chroma",
                        style: .chroma,
                        value: saturationBinding,
                        range: EditControlRanges.saturation,
                        defaultValue: EditControlDefaults.saturation,
                        format: "%.2f"
                    )
                }
            }

            SidebarSection(title: "Color", isExpanded: $colorExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    filtrationSliderRow("Cyan", axis: .cyan, value: wbCyanBinding)
                    filtrationSliderRow("Magenta", axis: .magenta, value: wbMagentaBinding)
                    filtrationSliderRow("Yellow", axis: .yellow, value: wbYellowBinding)
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

    private var meteringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            gradientSliderRow(
                "Analysis Buffer",
                style: .analysisBuffer,
                value: analysisBufferBinding,
                range: EditControlRanges.analysisBuffer,
                defaultValue: EditControlDefaults.analysisBuffer,
                format: "%.0f%%",
                valueScale: 100
            )
            Text(meteringHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var meteringHint: String {
        if session.currentEdit.hasCrop {
            "Auto Density meters inside your crop. Raise Analysis Buffer to inset further from the crop edge."
        } else {
            "Crop to the film area so Auto Density ignores scanner borders, or raise Analysis Buffer on full-frame scans."
        }
    }

    private var zoneDensityRow: some View {
        pairedGradientSliderRow(
            leftTitle: "Shadows Density",
            leftStyle: .density,
            leftValue: shadowDensityBinding,
            leftRange: EditControlRanges.shadowDensity,
            leftDefault: EditControlDefaults.shadowDensity,
            leftFormat: "%.2f",
            rightTitle: "Highlights Density",
            rightStyle: .density,
            rightValue: highlightDensityBinding,
            rightRange: EditControlRanges.highlightDensity,
            rightDefault: EditControlDefaults.highlightDensity,
            rightFormat: "%.2f"
        )
    }

    private var splitGradeRow: some View {
        pairedGradientSliderRow(
            leftTitle: "Shadows Grade",
            leftStyle: .grade,
            leftValue: shadowGradeBinding,
            leftRange: EditControlRanges.zoneGrade,
            leftDefault: EditControlDefaults.shadowGrade,
            leftFormat: "%.0f",
            rightTitle: "Highlights Grade",
            rightStyle: .grade,
            rightValue: highlightGradeBinding,
            rightRange: EditControlRanges.zoneGrade,
            rightDefault: EditControlDefaults.highlightGrade,
            rightFormat: "%.0f"
        )
    }

    private func pairedGradientSliderRow(
        leftTitle: String,
        leftStyle: SliderTrackStyle,
        leftValue: Binding<Double>,
        leftRange: ClosedRange<Double>,
        leftDefault: Double,
        leftFormat: String,
        rightTitle: String,
        rightStyle: SliderTrackStyle,
        rightValue: Binding<Double>,
        rightRange: ClosedRange<Double>,
        rightDefault: Double,
        rightFormat: String
    ) -> some View {
        HStack(spacing: 8) {
            compactGradientSlider(
                title: leftTitle,
                style: leftStyle,
                value: leftValue,
                range: leftRange,
                defaultValue: leftDefault,
                format: leftFormat
            )
            compactGradientSlider(
                title: rightTitle,
                style: rightStyle,
                value: rightValue,
                range: rightRange,
                defaultValue: rightDefault,
                format: rightFormat
            )
        }
    }

    private func compactGradientSlider(
        title: String,
        style: SliderTrackStyle,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultValue: Double,
        format: String,
        valueScale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(String(format: format, value.wrappedValue * valueScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GradientSlider(
                value: value,
                style: style,
                range: range,
                defaultValue: defaultValue
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func gradientSliderRow(
        _ title: String,
        style: SliderTrackStyle,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultValue: Double,
        format: String,
        valueScale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue * valueScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GradientSlider(
                value: value,
                style: style,
                range: range,
                defaultValue: defaultValue
            )
        }
    }

    private func filtrationSliderRow(
        _ title: String,
        axis: FiltrationAxis,
        value: Binding<Double>
    ) -> some View {
        gradientSliderRow(
            title,
            style: .filtration(axis),
            value: value,
            range: EditControlRanges.whiteBalance,
            defaultValue: EditControlDefaults.whiteBalance,
            format: "%.2f"
        )
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

    private var shadowDensityBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.shadowDensity },
            set: { session.setShadowDensity($0) }
        )
    }

    private var highlightDensityBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.highlightDensity },
            set: { session.setHighlightDensity($0) }
        )
    }

    private var shadowGradeBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.shadowGrade },
            set: { session.setShadowGrade($0) }
        )
    }

    private var highlightGradeBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.highlightGrade },
            set: { session.setHighlightGrade($0) }
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
            set: { newValue in
                guard newValue != session.currentEdit.autoExposure else { return }
                Task { @MainActor in
                    await Task.yield()
                    session.setAutoExposure(newValue)
                }
            }
        )
    }

    private var autoGradeBinding: Binding<Bool> {
        Binding(
            get: { session.currentEdit.autoNormalizeContrast },
            set: { session.setAutoNormalizeContrast($0) }
        )
    }

    private var analysisBufferBinding: Binding<Double> {
        Binding(
            get: { session.currentEdit.analysisBuffer },
            set: { session.setAnalysisBuffer($0) }
        )
    }
}

#Preview {
    ControlsPanelView(session: .preview, toneExpanded: .constant(true), colorExpanded: .constant(false))
        .padding()
        .frame(width: 280)
}
