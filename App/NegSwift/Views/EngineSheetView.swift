//
//  EngineSheetView.swift
//  NegSwift
//

import SwiftUI

struct EngineSheetView: View {
    @Bindable var session: EngineSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Engine")
                .font(.title2)

            engineStatusContent

            Spacer(minLength: 0)

            HStack {
                if showsRestartAction {
                    Button(restartLabel) {
                        Task { await session.restart() }
                    }
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 248)
    }

    private var showsRestartAction: Bool {
        switch session.state {
        case .ready, .failed:
            return true
        case .idle, .starting, .previewUnavailable:
            return false
        }
    }

    private var restartLabel: String {
        if case .failed = session.state {
            return "Retry"
        }
        return "Restart Engine"
    }

    @ViewBuilder
    private var engineStatusContent: some View {
        switch session.state {
        case .idle:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Idle")
                    .foregroundStyle(.secondary)
            }
        case .starting:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Starting negswift-engine…")
            }
        case let .ready(info):
            VStack(alignment: .leading, spacing: 8) {
                statusRow("NegSwift", info.negswiftVersion)
                statusRow("NegPy", info.negpyVersion)
                statusRow("Python", info.python)
                statusRow("GPU", info.gpuAvailable ? (info.gpuBackend ?? "yes") : "CPU fallback")
                statusRow("Data", AppPreferences.negpyUserDirectoryPath)
                statusRow("Frames", "\(session.frames.count)")
                if let path = session.currentPath {
                    statusRow("File", (path as NSString).lastPathComponent)
                }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .previewUnavailable:
            Text("Engine not started in SwiftUI Preview. Press ⌘R to run the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }
}

#Preview {
    EngineSheetView(session: .preview)
}
