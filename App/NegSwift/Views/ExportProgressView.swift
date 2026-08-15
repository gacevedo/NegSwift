//
//  ExportProgressView.swift
//  NegSwift
//

import SwiftUI

struct ExportProgressView: View {
    let statusText: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
