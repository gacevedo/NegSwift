//
//  ExportProgressView.swift
//  NegSwift
//

import SwiftUI

struct ExportProgressView: View {
    let statusText: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .accessibilityIdentifier("negSwift.cancelExport")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ExportProgressView(statusText: ExportSettings.quickExport.progressStatusText)
        .padding()
}

#Preview("Batch") {
    ExportProgressView(
        statusText: BatchExportProgress(
            scope: .all,
            settings: .quickExport,
            completed: 2,
            total: 5,
            currentName: "scan_003.tif"
        ).statusText,
        onCancel: {}
    )
    .padding()
}
