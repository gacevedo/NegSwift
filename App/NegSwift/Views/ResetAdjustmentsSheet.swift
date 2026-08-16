//
//  ResetAdjustmentsSheet.swift
//  NegSwift
//

import SwiftUI

struct ResetAdjustmentsSheet: View {
    @Bindable var session: EngineSession
    @Environment(\.dismiss) private var dismiss

    @State private var applyToAll = false

    private var frameCount: Int { session.frames.count }
    private var adjustmentCount: Int { session.framePathsWithAdjustments().count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset all adjustments?")
                .font(.title2)

            Text(explanation)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if frameCount > 1, adjustmentCount > 1 {
                Toggle("Apply to all \(adjustmentCount) modified images", isOn: $applyToAll)
                    .accessibilityIdentifier("negSwift.resetApplyToAll")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Reset", role: .destructive) {
                    let applyAll = frameCount > 1 && adjustmentCount > 1 && applyToAll
                    dismiss()
                    Task {
                        await session.resetFrameEdits(applyToAll: applyAll)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("negSwift.resetConfirm")
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var explanation: String {
        if frameCount > 1 {
            return "Returns frames to default settings and removes saved sidecars. This cannot be undone."
        }
        return "Returns the selected frame to default settings and removes its saved sidecar. This cannot be undone."
    }
}
