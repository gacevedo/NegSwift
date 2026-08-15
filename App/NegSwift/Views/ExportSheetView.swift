//
//  ExportSheetView.swift
//  NegSwift
//

import SwiftUI

struct ExportSheetView: View {
    @Bindable var session: EngineSession
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ExportSettings()
    @State private var destinationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.title2)

            if let frameName = session.selectedFrameName {
                Text(frameName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Format", selection: formatSelection) {
                ForEach(ExportFileFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)

            // Fixed slot — inserting/removing this row during NSSegmentedControl layout
            // triggers AppKit layout recursion when the sheet resizes.
            jpegQualitySection
                .opacity(settings.format == .jpeg ? 1 : 0)
                .allowsHitTesting(settings.format == .jpeg)
                .accessibilityHidden(settings.format != .jpeg)
                .frame(height: Self.jpegQualitySectionHeight, alignment: .top)
                .clipped()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(destinationLabel)
                        .lineLimit(2)
                        .font(.body)
                }
                Spacer()
                Button("Choose…") {
                    Task {
                        if let url = await FolderPicker.chooseFolder(
                            prompt: "Export To",
                            recentKind: .exportFolder
                        ) {
                            destinationURL = url
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Export") {
                    Task { await runExport() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
            }
        }
        .padding(20)
        .frame(width: 420, height: Self.sheetHeight)
        .onAppear {
            if destinationURL == nil {
                destinationURL = RecentPathsStore.directoryURL(for: .exportFolder)
                    ?? defaultDestinationURL()
            }
        }
    }

    private static let jpegQualitySectionHeight: CGFloat = 52
    private static let sheetHeight: CGFloat = 340

    /// Defer format changes so NSSegmentedControl finishes layout before the sheet updates.
    private var formatSelection: Binding<ExportFileFormat> {
        Binding(
            get: { settings.format },
            set: { newValue in
                guard newValue != settings.format else { return }
                Task { @MainActor in
                    await Task.yield()
                    settings.format = newValue
                }
            }
        )
    }

    private var jpegQualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("JPEG Quality")
                    .font(.caption)
                Spacer()
                Text("\(settings.jpegQuality)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.jpegQuality) },
                    set: { settings.jpegQuality = Int($0.rounded()) }
                ),
                in: 60 ... 100,
                step: 1
            )
        }
    }

    private var canExport: Bool {
        session.selectedFrameID != nil && destinationURL != nil && !session.isExporting
    }

    private var destinationLabel: String {
        guard let destinationURL else { return "Choose a folder" }
        return destinationURL.path
    }

    private func defaultDestinationURL() -> URL? {
        guard let path = session.selectedFramePath else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    private func runExport() async {
        guard let destinationURL else { return }
        let exportSettings = settings
        session.clearExportError()
        dismiss()
        let gotAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            _ = try await session.exportCurrentFrame(
                to: destinationURL,
                settings: exportSettings
            )
            RecentPathsStore.remember(destinationURL, for: .exportFolder)
        } catch is CancellationError {
            return
        } catch {
            session.noteExportError(error.localizedDescription)
        }
    }
}

#Preview {
    ExportSheetView(session: .preview)
}
