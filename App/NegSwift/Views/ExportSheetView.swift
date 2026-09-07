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
    @State private var longEdgeText = ""
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

            sizeSection

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
            syncLongEdgeTextFromSettings()
            refreshSourceSizes()
            if destinationURL == nil {
                destinationURL = RecentPathsStore.directoryURL(for: .exportFolder)
                    ?? defaultDestinationURL()
            }
        }
        .onChange(of: scope) { _, _ in
            refreshSourceSizes()
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
    private static let longEdgeControlsWidth: CGFloat = 132
    private static let scopeSectionHeight: CGFloat = 44
    private static let baseSheetHeight: CGFloat = 348

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
                return "\(name) as \(formatLabel)\(sizeSummarySuffix(for: session.selectedFramePath))"
            }
            return name
        case .all:
            if targets.count == 1, let frame = targets.first {
                return "\(frame.name) as \(formatLabel)\(sizeSummarySuffix(for: frame.path))"
            }
            return "Export \(targets.count) frames as \(formatLabel)\(sizeSummarySuffix(for: nil)) to \(destination)"
        case .selected:
            if targets.count == 1, let frame = targets.first {
                return "\(frame.name) as \(formatLabel)\(sizeSummarySuffix(for: frame.path))"
            }
            return "Export \(targets.count) selected frames as \(formatLabel)\(sizeSummarySuffix(for: nil)) to \(destination)"
        }
    }

    private func sizeSummarySuffix(for path: String?) -> String {
        if let path, let px = session.exportLongEdgePx(for: path, settings: settings) {
            switch settings.resolutionMode {
            case .original:
                return " at \(px)px (full size)"
            case .targetLongEdge:
                return " at \(px)px"
            }
        }
        switch settings.resolutionMode {
        case .original:
            return " at full size"
        case .targetLongEdge:
            return " at \(settings.targetLongEdgePx)px"
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

    /// Defer size-mode changes so NSSegmentedControl finishes layout before the sheet updates.
    private var resolutionModeSelection: Binding<ExportResolutionMode> {
        Binding(
            get: { settings.resolutionMode },
            set: { newValue in
                guard newValue != settings.resolutionMode else { return }
                Task { @MainActor in
                    await Task.yield()
                    if newValue == .targetLongEdge {
                        let sourceSize = session.selectedFramePath.flatMap { session.sourcePixelSize(for: $0) }
                        settings.targetLongEdgePx = InstagramExportSizing.defaultLongEdge(
                            for: session.currentEdit,
                            sourceSize: sourceSize
                        )
                        syncLongEdgeTextFromSettings()
                    }
                    settings.resolutionMode = newValue
                }
            }
        )
    }

    private var sizeSection: some View {
        HStack(spacing: 8) {
            Picker("Size", selection: resolutionModeSelection) {
                Text("Full size").tag(ExportResolutionMode.original)
                Text("Long edge").tag(ExportResolutionMode.targetLongEdge)
            }
            .pickerStyle(.segmented)
            .layoutPriority(1)

            longEdgeControls
                .frame(width: settings.resolutionMode == .targetLongEdge ? Self.longEdgeControlsWidth : 0)
                .clipped()
                .opacity(settings.resolutionMode == .targetLongEdge ? 1 : 0)
                .allowsHitTesting(settings.resolutionMode == .targetLongEdge)
                .accessibilityHidden(settings.resolutionMode != .targetLongEdge)
        }
    }

    private var longEdgeControls: some View {
        HStack(spacing: 6) {
            TextField("", text: $longEdgeText)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitLongEdgeText)
                .onChange(of: longEdgeText) { _, newValue in
                    let sanitized = sanitizeLongEdgeText(newValue)
                    if sanitized != newValue {
                        longEdgeText = sanitized
                    }
                }
            Text("px")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("", value: longEdgeStepperValue, in: Self.longEdgeRange, step: 10)
                .labelsHidden()
        }
    }

    private static let longEdgeRange = 256 ... 32768

    private var longEdgeStepperValue: Binding<Int> {
        Binding(
            get: { settings.targetLongEdgePx },
            set: { newValue in
                settings.targetLongEdgePx = newValue
                longEdgeText = String(newValue)
            }
        )
    }

    private func sanitizeLongEdgeText(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(5))
    }

    private func syncLongEdgeTextFromSettings() {
        longEdgeText = String(settings.targetLongEdgePx)
    }

    private func commitLongEdgeText() {
        guard let value = Int(longEdgeText) else {
            syncLongEdgeTextFromSettings()
            return
        }
        let clamped = min(Self.longEdgeRange.upperBound, max(Self.longEdgeRange.lowerBound, value))
        settings.targetLongEdgePx = clamped
        longEdgeText = String(clamped)
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

    private func refreshSourceSizes() {
        let targets = session.frames(for: scope)
        Task { await session.ensureSourceSizes(for: targets) }
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
        if settings.resolutionMode == .targetLongEdge {
            commitLongEdgeText()
        }
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
