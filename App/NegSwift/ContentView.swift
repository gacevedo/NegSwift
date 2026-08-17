//
//  ContentView.swift
//  NegSwift
//

import SwiftUI

struct ContentView: View {
    @Bindable var engineSession: EngineSession
    @Binding var showAbout: Bool
    @Bindable var commandBridge: MainWindowCommandBridge
    @State private var showExportSheet = false
    @State private var showEngineSheet = false
    @State private var showResetSheet = false
    @State private var previewZoomMode: PreviewZoomMode = .fit

    @AppStorage("negSwift.sidebar.filmStrip") private var filmStripExpanded = true
    @AppStorage("negSwift.sidebar.tone") private var toneExpanded = true
    @AppStorage("negSwift.sidebar.color") private var colorExpanded = false
    @AppStorage("negSwift.sidebar.crop") private var cropExpanded = false
    @AppStorage("negSwift.sidebar.scratch") private var scratchExpanded = false
    @State private var isImportDropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            showAbout = true
                        } label: {
                            HStack(alignment: .bottom, spacing: 6) {
                                if let icon = AppMetadata.appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                }
                                Text("NegSwift")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(AppMetadata.appVersion)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("About NegSwift")

                        HStack(spacing: 8) {
                            Button("Open Folder…") {
                                Task {
                                    guard let url = await FolderPicker.chooseFolder(
                                        prompt: "Open Folder",
                                        recentKind: .importFolder
                                    ) else { return }
                                    await engineSession.importFolder(at: url)
                                }
                            }
                            .disabled(!engineSession.engineReady)
                            .accessibilityIdentifier("negSwift.openFolder")

                            Button("Open File…") {
                                Task {
                                    guard let url = await FolderPicker.chooseScanFile() else { return }
                                    await engineSession.importFileFromPicker(url)
                                }
                            }
                            .disabled(!engineSession.engineReady || engineSession.isRenderingPreview)
                            .accessibilityIdentifier("negSwift.openFile")
                        }
                        .controlSize(.small)

                        SidebarSection(title: "Film Strip", isExpanded: $filmStripExpanded) {
                            FilmStripView(
                                frames: engineSession.frames,
                                selectedID: engineSession.selectedFrameID,
                                selectedIDs: engineSession.selectedFrameIDs,
                                onSelect: { id, modifiers in
                                    Task { await engineSession.selectFrame(id, modifiers: modifiers) }
                                }
                            )
                            .frame(minHeight: 96, maxHeight: 220)
                        }

                        ProcessModePickerView(session: engineSession)

                        GeometryPanelView(session: engineSession, isExpanded: $cropExpanded)

                        ScratchPanelView(session: engineSession, isExpanded: $scratchExpanded)

                        ControlsPanelView(
                            session: engineSession,
                            toneExpanded: $toneExpanded,
                            colorExpanded: $colorExpanded
                        )
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)

                Divider()

                HStack(spacing: 12) {
                    Button("Reset Adjustments…") {
                        showResetSheet = true
                    }
                    .controlSize(.mini)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(!engineSession.engineReady || engineSession.selectedFrameID == nil || engineSession.isExporting)

                    Button("Engine") {
                        showEngineSheet = true
                    }
                    .controlSize(.mini)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 240, idealWidth: 280)
        } detail: {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 8) {
                            Button("Quick Export") {
                                Task { await engineSession.quickExport() }
                            }
                            .disabled(!engineSession.engineReady || engineSession.selectedFrameID == nil || engineSession.isExporting)
                            .accessibilityIdentifier("negSwift.quickExport")

                            Button("Export…") {
                                showExportSheet = true
                            }
                            .disabled(!engineSession.engineReady || engineSession.selectedFrameID == nil || engineSession.isExporting)
                            .accessibilityIdentifier("negSwift.exportSheet")
                        }
                        .padding(.trailing, 16)
                    }
                }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(session: engineSession)
        }
        .sheet(isPresented: $showEngineSheet) {
            EngineSheetView(session: engineSession)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showResetSheet) {
            ResetAdjustmentsSheet(session: engineSession)
        }
        .navigationSplitViewStyle(.balanced)
        .importDropTarget(session: engineSession, isTargeted: $isImportDropTargeted)
        .onAppear {
            wireCommandBridge()
        }
        .onChange(of: engineSession.selectedFrameID) { _, _ in
            previewZoomMode = .fit
            syncCommandBridgeState()
        }
        .onChange(of: engineSession.engineReady) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.frames.count) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.isExporting) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.isCropToolActive) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.isScratchToolActive) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.scratchHealRevision) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.previewImage) { _, _ in syncCommandBridgeState() }
        .onChange(of: engineSession.exportSelectionCount) { _, _ in syncCommandBridgeState() }
        .onChange(of: showExportSheet) { _, _ in syncCommandBridgeState() }
        .onChange(of: showEngineSheet) { _, _ in syncCommandBridgeState() }
        .onChange(of: showAbout) { _, _ in syncCommandBridgeState() }
        .onChange(of: showResetSheet) { _, _ in syncCommandBridgeState() }
    }

    private func wireCommandBridge() {
        commandBridge.openImport = {
            Task { await performOpenImport() }
        }
        commandBridge.openExport = {
            showExportSheet = true
        }
        commandBridge.toggleCanvasZoom = {
            previewZoomMode.toggle()
        }
        commandBridge.toggleCropTool = {
            Task { @MainActor in
                await Task.yield()
                engineSession.setCropToolActive(!engineSession.isCropToolActive)
            }
        }
        commandBridge.toggleScratchTool = {
            Task { @MainActor in
                await Task.yield()
                engineSession.setScratchToolActive(!engineSession.isScratchToolActive)
            }
        }
        commandBridge.undoLastHeal = {
            Task {
                await engineSession.undoLastHeal()
            }
        }
        syncCommandBridgeState()
    }

    private func syncCommandBridgeState() {
        let modalOpen = showExportSheet || showEngineSheet || showAbout || showResetSheet
        commandBridge.canOpenImport = engineSession.engineReady
        commandBridge.canOpenExport = engineSession.engineReady
            && !engineSession.frames.isEmpty
            && !engineSession.isExporting
        commandBridge.canToggleCanvasZoom = engineSession.previewImage != nil
            && !modalOpen
        commandBridge.canToggleCropTool = engineSession.engineReady
            && engineSession.selectedFrameID != nil
            && !modalOpen
        commandBridge.canToggleScratchTool = engineSession.engineReady
            && engineSession.selectedFrameID != nil
            && engineSession.previewImage != nil
            && !modalOpen
        commandBridge.canUndoLastHeal = engineSession.isScratchToolActive
            && engineSession.currentEdit.hasHealStrokes
            && !modalOpen
    }

    private func performOpenImport() async {
        guard engineSession.engineReady else { return }
        guard let urls = await FolderPicker.chooseImport() else { return }
        await engineSession.importDroppedURLs(urls)
    }

    @ViewBuilder
    private var previewPane: some View {
        ZStack {
            if let image = engineSession.previewImage {
                PreviewCanvasView(
                    session: engineSession,
                    zoomMode: $previewZoomMode,
                    image: image
                )
            } else if !engineSession.isPreviewStale {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Open a folder, open a file, or drop files here")
                        .foregroundStyle(.secondary)
                    if !engineSession.engineReady {
                        switch engineSession.state {
                        case .starting:
                            Text("Waiting for engine…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case let .failed(message):
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        default:
                            Text("Waiting for engine…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if engineSession.isPreviewStale {
                previewLoadingOverlay
            }
        }
        .overlay {
            if engineSession.isExporting {
                ExportProgressView(
                    statusText: engineSession.exportProgressStatusText,
                    onCancel: { engineSession.cancelExport() }
                )
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let error = engineSession.exportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                if let error = engineSession.previewError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("negSwift.previewError")
                }
            }
            .padding()
        }
    }

    private var previewLoadingOverlay: some View {
        ZStack {
            if engineSession.previewImage != nil {
                Color.black.opacity(0.25)
            }
            ProgressView(engineSession.previewLoadingMessage ?? "Loading image…")
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("negSwift.previewLoading")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(
        engineSession: .preview,
        showAbout: .constant(false),
        commandBridge: MainWindowCommandBridge()
    )
}
