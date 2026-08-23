//
//  AboutView.swift
//  NegSwift
//

import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            if let icon = AppMetadata.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Text("NegSwift")
                .font(.title2.weight(.semibold))

            Text("Version \(AppMetadata.appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(AppMetadata.copyrightLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                creditRow(title: "NegSwift source", url: AppMetadata.negSwiftSourceURL)
                creditRow(title: "NegPy upstream", url: AppMetadata.negPySourceURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(
                "NegSwift and the bundled NegPy engine are free software under "
                    + "GNU GPL v3. Corresponding source must be offered with any binary distribution."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if AppMetadata.legalFileURL(named: "LICENSE") != nil {
                    Button("View License") { openLegalFile(named: "LICENSE") }
                }
                if AppMetadata.legalFileURL(named: "NOTICE") != nil {
                    Button("View Notice") { openLegalFile(named: "NOTICE") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 420)
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }

    private func creditRow(title: String, url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .trailing)
            Link(url.absoluteString, destination: url)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private func openLegalFile(named name: String) {
        guard let url = AppMetadata.legalFileURL(named: name) else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    AboutView()
}
