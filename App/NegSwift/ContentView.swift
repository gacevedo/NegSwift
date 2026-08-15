//
//  ContentView.swift
//  NegSwift
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var engineSession: EngineSession
    @State private var showFolderImporter = false
    @State private var showFileImporter = false

    @AppStorage("negSwift.sidebar.filmStrip") private var filmStripExpanded = true
    @AppStorage("negSwift.sidebar.tone") private var toneExpanded = true
    @AppStorage("negSwift.sidebar.colour") private var colourExpanded = false
    @AppStorage("negSwift.sidebar.crop") private var cropExpanded = false
    @AppStorage("negSwift.sidebar.engine") private var engineExpanded = false

    private static let importTypes: [UTType] = [.tiff, .png, .jpeg, .heic, .rawImage]

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("NegSwift", systemImage: "film")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Button("Import Folder…") {
                            showFolderImporter = true
                        }
                        .disabled(!engineSession.engineReady)

                        Button("Open File…") {
                            showFileImporter = true
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

                    ControlsPanelView(
                        session: engineSession,
                        toneExpanded: $toneExpanded,
                        colourExpanded: $colourExpanded
                    )

                    GeometryPanelView(session: engineSession, isExpanded: $cropExpanded)

                    SidebarSection(title: "Engine", isExpanded: $engineExpanded) {
                        engineStatusCard
                    }
                }
                .padding()
            }
            .frame(minWidth: 240, idealWidth: 280)
        } detail: {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await engineSession.importFolder(at: url) }
            case let .failure(error):
                engineSession.noteImportError(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await engineSession.importFileFromPicker(url) }
            case let .failure(error):
                engineSession.noteImportError(error.localizedDescription)
            }
        }
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
        .overlay(alignment: .bottom) {
            if let error = engineSession.previewError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var engineStatusCard: some View {
        switch engineSession.state {
        case .idle:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Idle")
                    .foregroundStyle(.secondary)
            }
        case .starting:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Starting negswift-engine…")
            }
        case let .ready(info):
            VStack(alignment: .leading, spacing: 6) {
                statusRow("NegSwift", info.negswiftVersion)
                statusRow("NegPy", info.negpyVersion)
                statusRow("Python", info.python)
                statusRow("GPU", info.gpuAvailable ? (info.gpuBackend ?? "yes") : "CPU fallback")
                statusRow("Frames", "\(engineSession.frames.count)")
                if let path = engineSession.currentPath {
                    statusRow("File", (path as NSString).lastPathComponent)
                }
                Button("Restart engine") {
                    Task { await engineSession.restart() }
                }
                .controlSize(.small)
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Retry") {
                    Task { await engineSession.restart() }
                }
                .controlSize(.small)
            }
        case .previewUnavailable:
            Text("Engine not started in SwiftUI Preview. Press ⌘R to run the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

#Preview {
    ContentView(engineSession: .preview)
}
