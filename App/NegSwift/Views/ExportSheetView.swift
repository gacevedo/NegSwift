//
//  ExportSheetView.swift
//  NegSwift
//

import SwiftUI

struct ExportSheetView: View {
    @Bindable var session: EngineSession
    let initialScope: ExportScope
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ExportSettings()
    @State private var destinationURL: URL?
    @State private var scope: ExportScope
    @State private var confirmBatchExport = false

    init(session: EngineSession, initialScope: ExportScope = .current) {
        self.session = session
        self.initialScope = initialScope
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.title2)

            if showsScopePicker {
                scopePickerSection
            }

            Text(scopeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

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
                Button(exportButtonTitle) {
                    beginExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
                .accessibilityIdentifier(scope == .all ? "negSwift.exportAllSheet" : "negSwift.exportSheet")
            }
        }
        .padding(20)
        .frame(width: 420, height: sheetHeight)
        .onAppear {
            applyInitialScope()
            if destinationURL == nil {
                destinationURL = RecentPathsStore.directoryURL(for: .exportFolder)
                    ?? defaultDestinationURL()
            }
        }
        .confirmationDialog(
            "Export \(exportTargetCount) frames?",
            isPresented: $confirmBatchExport,
            titleVisibility: .visible
        ) {
            Button("Export") {
                Task { await runExport() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private static let jpegQualitySectionHeight: CGFloat = 52
    private static let scopeSectionHeight: CGFloat = 44
    private static let baseSheetHeight: CGFloat = 340

    private var showsScopePicker: Bool {
        session.frames.count > 1
    }

    private var sheetHeight: CGFloat {
        Self.baseSheetHeight + (showsScopePicker ? Self.scopeSectionHeight : 0)
    }

    private var availableScopes: [ExportScope] {
        ExportScope.availableScopes(selectionCount: session.exportSelectionCount)
    }

    private var scopePickerSection: some View {
        Picker("Frames", selection: scopeSelection) {
            ForEach(availableScopes, id: \.self) { exportScope in
                Text(
                    exportScope.pickerLabel(
                        selectionCount: session.exportSelectionCount,
                        frameCount: session.frames.count
                    )
                )
                .tag(exportScope)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("negSwift.exportScopePicker")
    }

    private var exportTargetCount: Int {
        session.frames(for: scope).count
    }

    private var exportButtonTitle: String {
        switch scope {
        case .all where exportTargetCount > 1:
            "Export All"
        case .current, .selected, .all:
            "Export"
        }
    }

    private var scopeSummary: String {
        let targets = session.frames(for: scope)
        let formatLabel = settings.format.label
        let destination = destinationURL?.lastPathComponent ?? "chosen folder"

        switch scope {
        case .current:
            let name = session.selectedFrameName ?? "No frame selected"
            if exportTargetCount <= 1 {
                return "\(name) as \(formatLabel)"
            }
            return name
        case .all:
            if targets.count == 1, let name = targets.first?.name {
                return "\(name) as \(formatLabel)"
            }
            return "Export \(targets.count) frames as \(formatLabel) to \(destination)"
        case .selected:
            if targets.count == 1, let name = targets.first?.name {
                return "\(name) as \(formatLabel)"
            }
            return "Export \(targets.count) selected frames as \(formatLabel) to \(destination)"
        }
    }

    /// Defer scope changes so NSSegmentedControl finishes layout before the sheet updates.
    private var scopeSelection: Binding<ExportScope> {
        Binding(
            get: { scope },
            set: { newValue in
                guard newValue != scope else { return }
                Task { @MainActor in
                    await Task.yield()
                    scope = newValue
                }
            }
        )
    }

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
        !session.frames(for: scope).isEmpty && destinationURL != nil && !session.isExporting
    }

    private var destinationLabel: String {
        guard let destinationURL else { return "Choose a folder" }
        return destinationURL.path
    }

    private func defaultDestinationURL() -> URL? {
        if let path = session.selectedFramePath {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        if let path = session.frames.first?.path {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return nil
    }

    private func applyInitialScope() {
        if initialScope == .current {
            scope = session.defaultExportScope
        } else {
            scope = initialScope
        }
        normalizeScopeSelection()
    }

    private func normalizeScopeSelection() {
        guard !availableScopes.contains(scope) else { return }
        scope = availableScopes.contains(.current) ? .current : (availableScopes.first ?? .current)
    }

    private func beginExport() {
        guard destinationURL != nil else { return }
        if exportTargetCount > 1 {
            confirmBatchExport = true
            return
        }
        Task { await runExport() }
    }

    private func runExport() async {
        guard let destinationURL else { return }
        let exportSettings = settings
        let exportScope = scope
        session.clearExportError()
        dismiss()
        let gotAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            _ = try await session.exportBatch(
                scope: exportScope,
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

#Preview("Export All") {
    ExportSheetView(session: .preview, initialScope: .all)
}
