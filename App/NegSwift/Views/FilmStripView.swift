//
//  FilmStripView.swift
//  NegSwift
//

import SwiftUI

struct FilmStripView: View {
    let frames: [ScanFrame]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        Group {
            if frames.isEmpty {
                Text("Import a folder to see frames")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(frames) { frame in
                            FilmStripCell(
                                frame: frame,
                                isSelected: frame.id == selectedID,
                                onSelect: { onSelect(frame.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct FilmStripCell: View {
    let frame: ScanFrame
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 56, height: 56)
                    if let thumbnail = frame.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if frame.isLoadingThumbnail {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(frame.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
