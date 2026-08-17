//
//  FilmStripView.swift
//  NegSwift
//

import SwiftUI

struct FilmStripView: View {
    let frames: [ScanFrame]
    let selectedID: UUID?
    let selectedIDs: Set<UUID>
    let onSelect: (UUID, FilmStripSelectionModifiers) -> Void

    var body: some View {
        Group {
            if frames.isEmpty {
                Text("Open a folder or file to see frames")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(frames) { frame in
                            FilmStripCell(
                                frame: frame,
                                isPrimary: frame.id == selectedID,
                                isSecondarySelected: selectedIDs.contains(frame.id) && frame.id != selectedID,
                                onSelect: {
                                    onSelect(frame.id, FilmStripSelectionModifiers.fromCurrentEvent())
                                }
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
    let isPrimary: Bool
    let isSecondarySelected: Bool
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
                            .scaledToFit()
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isSecondarySelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var cellBackground: Color {
        if isPrimary {
            return Color.accentColor.opacity(0.18)
        }
        if isSecondarySelected {
            return Color.accentColor.opacity(0.08)
        }
        return .clear
    }
}
