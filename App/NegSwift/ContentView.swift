//
//  ContentView.swift
//  NegSwift
//

import SwiftUI

struct ContentView: View {
    @Bindable var engineSession: EngineSession
    @State private var showExportSheet = false
    @State private var showEngineSheet = false
    @State private var showResetConfirm = false

    @AppStorage("negSwift.sidebar.filmStrip") private var filmStripExpanded = true
    @AppStorage("negSwift.sidebar.tone") private var toneExpanded = true
    @AppStorage("negSwift.sidebar.color") private var colorExpanded = false
    @AppStorage("negSwift.sidebar.crop") private var cropExpanded = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("NegSwift", systemImage: "film")
                            .font(.headline)

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

                            Button("Open File…") {
                                Task {
                                    guard let url = await FolderPicker.chooseScanFile() else { return }
                                    await engineSession.importFileFromPicker(url)
                                }
                            }
                            .disabled(!engineSession.engineReady || engineSession.isRenderingPreview)
                        }
                        .controlSize(.small)

                        SidebarSection(title: "Film Strip", isExpanded: $filmStripExpanded) {
                            FilmStripView(
                                frames: engineSession.frames,
                                selectedID: engineSession.selectedFrameID,
                                onSelect: { id in
                                    Task { await engineSession.selectFrame(id) }
                                }
                            )
                            .frame(minHeight: 96, maxHeight: 220)
                        }

                        ProcessModePickerView(session: engineSession)

                        GeometryPanelView(session: engineSession, isExpanded: $cropExpanded)

                        ControlsPanelView(
                            session: engineSession,
                            toneExpanded: $toneExpanded,
                            colorExpanded: $colorExpanded
                        )
                    }
                    .padding()
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Reset Adjustments…") {
                        showResetConfirm = true
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
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Quick Export") {
                            Task { await engineSession.quickExport() }
                        }
                        .disabled(!engineSession.engineReady || engineSession.selectedFrameID == nil || engineSession.isExporting)

                        Button("Export…") {
                            showExportSheet = true
                        }
                        .disabled(!engineSession.engineReady || engineSession.selectedFrameID == nil || engineSession.isExporting)
                    }
                }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(session: engineSession)
        }
        .sheet(isPresented: $showEngineSheet) {
            EngineSheetView(session: engineSession)
        }
        .confirmationDialog(
            "Reset all adjustments?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await engineSession.resetCurrentFrameEdits() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Returns the selected frame to default settings and removes its saved sidecar. This cannot be undone.")
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var previewPane: some View {
        ZStack {
            if engineSession.isRenderingPreview, engineSession.previewImage == nil {
                ProgressView("Rendering preview…")
            } else if let image = engineSession.previewImage {
                PreviewCanvasView(session: engineSession, image: image)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Import a folder or open a scan")
                        .foregroundStyle(.secondary)
                    if !engineSession.engineReady {
                        Text("Waiting for engine…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if engineSession.isExporting, let settings = engineSession.activeExportSettings {
                ExportProgressView(statusText: settings.progressStatusText)
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
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView(engineSession: .preview)
}
