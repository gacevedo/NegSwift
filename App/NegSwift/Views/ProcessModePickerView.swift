//
//  ProcessModePickerView.swift
//  NegSwift
//

import SwiftUI

struct ProcessModePickerView: View {
    @Bindable var session: EngineSession

    var body: some View {
        Picker("Process", selection: processModeBinding) {
            ForEach(ProcessMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Process mode")
        .disabled(session.selectedFrameID == nil)
    }

    private var processModeBinding: Binding<ProcessMode> {
        Binding(
            get: { session.currentEdit.processMode },
            set: { session.setProcessMode($0) }
        )
    }
}

#Preview {
    ProcessModePickerView(session: .preview)
        .padding()
        .frame(width: 280)
}
