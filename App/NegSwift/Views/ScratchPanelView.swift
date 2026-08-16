//
//  ScratchPanelView.swift
//  NegSwift
//

import SwiftUI

struct ScratchPanelView: View {
    @Bindable var session: EngineSession
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarSection(title: "Scratch", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Scratch Tool", isOn: scratchToolBinding)
                    .controlSize(.small)
                    .help("Click points along a scratch or hair on the preview (⇧S)")
                    .accessibilityIdentifier("negSwift.scratchToolToggle")
                    .frame(maxWidth: .infinity, alignment: .leading)

                if session.isScratchToolActive {
                    activeControls
                } else {
                    Text("Turn on Scratch Tool, then click along scratches or hairs on the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(session.selectedFrameID == nil || session.previewImage == nil)
    }

    @ViewBuilder
    private var activeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            brushSizeRow

            if session.scratchInProgressPoints.isEmpty {
                Text("Click each point along the defect on the preview. Release quickly — do not drag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(session.scratchInProgressPoints.count) point\(session.scratchInProgressPoints.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("negSwift.scratchPointCount")

                    HStack(spacing: 8) {
                        Button("Finish") {
                            Task { await session.finishScratchInProgress() }
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("negSwift.scratchFinish")

                        Button("Clear") {
                            session.clearScratchInProgressPoints()
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("negSwift.scratchClear")
                    }

                    Text("Enter or Finish to apply · Esc clears points or exits the tool")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if session.currentEdit.hasHealStrokes {
                Button("Undo Last Heal") {
                    Task { await session.undoLastHeal() }
                }
                .controlSize(.small)
                .accessibilityIdentifier("negSwift.scratchUndoHeal")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var brushSizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Brush Size")
                    .font(.caption)
                Spacer(minLength: 8)
                Text("\(session.currentEdit.manualDustSize) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(session.currentEdit.manualDustSize) },
                    set: { session.setManualDustSize(Int($0.rounded())) }
                ),
                in: EditControlRanges.manualDustSize,
                step: 1
            )
            .accessibilityIdentifier("negSwift.scratchBrushSize")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scratchToolBinding: Binding<Bool> {
        Binding(
            get: { session.isScratchToolActive },
            set: { newValue in
                guard newValue != session.isScratchToolActive else { return }
                Task { @MainActor in
                    await Task.yield()
                    session.setScratchToolActive(newValue)
                }
            }
        )
    }
}

#Preview {
    ScratchPanelView(session: .preview, isExpanded: .constant(true))
        .padding()
        .frame(width: 280)
}
