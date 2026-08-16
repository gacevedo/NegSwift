//
//  ContentView.swift
//  NegSwift
//

import SwiftUI

struct ContentView: View {
    @Bindable var engineSession: EngineSession
    @Binding var showAbout: Bool
    @State private var showExportSheet = false
    @State private var showEngineSheet = false
    @State private var showResetConfirm = false

    @AppStorage("negSwift.sidebar.filmStrip") private var filmStripExpanded = true
    @AppStorage("negSwift.sidebar.tone") private var toneExpanded = true
    @AppStorage("negSwift.sidebar.color") private var colorExpanded = false
    @AppStorage("negSwift.sidebar.crop") private var cropExpanded = false
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
        .importDropTarget(session: engineSession, isTargeted: $isImportDropTargeted)
    }

    @ViewBuilder
    private var previewPane: some View {
        ZStack {
            if engineSession.isRenderingPreview, engineSession.previewImage == nil {
                ProgressView("Rendering preview…")
            } else if let image = engineSession.previewImage {
                PreviewCanvasView(session: engineSession, image: image)
            } else {
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
                        .accessibilityIdentifier("negSwift.previewError")
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView(engineSession: .preview, showAbout: .constant(false))
}
