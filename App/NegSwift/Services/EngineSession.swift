//
//  EngineSession.swift
//  NegSwift
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class EngineSession {
    enum State: Equatable {
        case idle
        case starting
        case ready(EngineInfo)
        case failed(String)
        case previewUnavailable
    }

    private(set) var state: State = .idle
    private(set) var previewImage: NSImage?
    private(set) var isRenderingPreview = false
    private(set) var previewError: String?
    private(set) var currentPath: String?
    private(set) var frames: [ScanFrame] = []
    private(set) var selectedFrameID: UUID?
    private(set) var frameEdits: [String: FrameEditState] = [:]

    private let client = EngineClient()
    private let previewDebounce = DebounceScheduler()
    private var scopedFolderURL: URL?
    private var stripGeneration = 0
    private var previewGeneration = 0

    var engineReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var currentEdit: FrameEditState {
        guard let path = selectedFramePath else { return FrameEditState() }
        return frameEdits[path] ?? FrameEditState()
    }

    private var selectedFramePath: String? {
        guard let id = selectedFrameID else { return nil }
        return frames.first(where: { $0.id == id })?.path
    }

    func setProcessMode(_ value: ProcessMode) { updateEdit { $0.processMode = value } }
    func setDensity(_ value: Double) { updateEdit { $0.density = value } }
    func setGrade(_ value: Double) { updateEdit { $0.grade = value } }
    func setSaturation(_ value: Double) { updateEdit { $0.saturation = value } }
    func setWBCyan(_ value: Double) { updateEdit { $0.wbCyan = value } }
    func setWBMagenta(_ value: Double) { updateEdit { $0.wbMagenta = value } }
    func setWBYellow(_ value: Double) { updateEdit { $0.wbYellow = value } }
    func setAutoExposure(_ value: Bool) { updateEdit { $0.autoExposure = value } }
    func setAutoNormalizeContrast(_ value: Bool) { updateEdit { $0.autoNormalizeContrast = value } }

    private func updateEdit(_ transform: (inout FrameEditState) -> Void) {
        guard let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }
        var edit = frameEdits[path] ?? FrameEditState()
        transform(&edit)
        frameEdits[path] = edit
        scheduleDebouncedPreview(for: frame)
    }

    private func scheduleDebouncedPreview(for frame: ScanFrame) {
        previewGeneration += 1
        let generation = previewGeneration
        let config = frameEdits[frame.path] ?? FrameEditState()
        previewDebounce.schedule { [weak self] in
            guard let self else { return }
            await self.renderPreview(
                at: frame.url,
                generation: generation,
                config: config
            )
        }
    }

    func start() async {
        if ProcessInfoPreview.isRunningForPreviews {
            state = .previewUnavailable
            return
        }
        guard case .idle = state else { return }
        state = .starting
        do {
            let info = try await client.info()
            state = .ready(info)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restart() async {
        await client.stop()
        clearFilmStrip()
        state = .idle
        previewImage = nil
        previewError = nil
        currentPath = nil
        await start()
    }

    func stop() async {
        await client.stop()
        clearFilmStrip()
        state = .idle
        previewImage = nil
        previewError = nil
        currentPath = nil
    }

    func noteImportError(_ message: String) {
        previewError = message
    }

    func importFolder(at url: URL) async {
        guard engineReady else { return }
        stopFolderAccess()
        if url.startAccessingSecurityScopedResource() {
            scopedFolderURL = url
        }
        stripGeneration += 1
        let generation = stripGeneration
        previewError = nil
        do {
            let discovered = try await client.discover(paths: [url.path])
            frames = discovered.assets.map { asset in
                ScanFrame(
                    id: UUID(),
                    url: URL(fileURLWithPath: asset.path),
                    path: asset.path,
                    name: asset.name
                )
            }
            if let first = frames.first {
                await selectFrame(first.id)
            } else {
                previewError = "No supported scans found in this folder."
            }
            await loadThumbnails(generation: generation)
        } catch {
            previewError = error.localizedDescription
        }
    }

    func importFile(at url: URL) async {
        guard engineReady else { return }
        stripGeneration += 1
        let generation = stripGeneration
        let frame = ScanFrame(
            id: UUID(),
            url: url,
            path: url.path,
            name: url.lastPathComponent
        )
        frames = [frame]
        await selectFrame(frame.id)
        await loadThumbnails(generation: generation)
    }

    func importFileFromPicker(_ url: URL) async {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        await importFile(at: url)
    }

    func selectFrame(_ id: UUID) async {
        selectedFrameID = id
        guard let frame = frames.first(where: { $0.id == id }) else { return }
        await ensureEditLoaded(for: frame.path)
        previewDebounce.cancel()
        previewGeneration += 1
        let generation = previewGeneration
        let config = frameEdits[frame.path] ?? FrameEditState()
        await renderPreview(at: frame.url, generation: generation, config: config)
    }

    private func ensureEditLoaded(for path: String) async {
        guard frameEdits[path] == nil else { return }
        do {
            let loaded = try await client.loadConfig(path: path)
            let flat = loaded.config.mapValues(\.anyValue)
            frameEdits[path] = FrameEditState.fromFlatConfig(flat)
        } catch {
            frameEdits[path] = FrameEditState()
        }
    }

    private func renderPreview(at url: URL, generation: Int, config: FrameEditState? = nil) async {
        guard engineReady else { return }

        let gotAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        isRenderingPreview = true
        previewError = nil

        do {
            let result = try await client.render(path: url.path, config: config)
            guard generation == previewGeneration else { return }
            guard let data = result.pngData, let image = NSImage(data: data) else {
                previewError = "Engine returned an invalid PNG."
                return
            }
            previewImage = image
            currentPath = url.path
        } catch {
            guard generation == previewGeneration else { return }
            previewError = error.localizedDescription
        }

        if generation == previewGeneration {
            isRenderingPreview = false
        }
    }

    private func loadThumbnails(generation: Int) async {
        for index in frames.indices {
            guard generation == stripGeneration else { return }
            frames[index].isLoadingThumbnail = true
            let path = frames[index].path
            do {
                let result = try await client.render(
                    path: path,
                    longEdgePx: FilmStripLayout.thumbnailLongEdge
                )
                guard generation == stripGeneration else { return }
                if let data = result.pngData, let image = NSImage(data: data) {
                    frames[index].thumbnail = image
                }
            } catch {
                // Thumbnail failure is non-fatal; full preview may still work.
            }
            if generation == stripGeneration {
                frames[index].isLoadingThumbnail = false
            }
        }
    }

    private func clearFilmStrip() {
        stripGeneration += 1
        previewGeneration += 1
        previewDebounce.cancel()
        stopFolderAccess()
        frames = []
        selectedFrameID = nil
        frameEdits = [:]
    }

    private func stopFolderAccess() {
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL = nil
    }

    #if DEBUG
    static var preview: EngineSession {
        let session = EngineSession()
        session.state = .ready(
            EngineInfo(
                protocolVersion: "0.1",
                negswiftVersion: "0.1.0",
                negpyVersion: "preview",
                python: "—",
                gpuAvailable: false,
                gpuBackend: nil
            )
        )
        session.frames = [
            ScanFrame(id: UUID(), url: URL(fileURLWithPath: "/preview/a.tif"), path: "/preview/a.tif", name: "a.tif"),
            ScanFrame(id: UUID(), url: URL(fileURLWithPath: "/preview/b.tif"), path: "/preview/b.tif", name: "b.tif"),
        ]
        session.selectedFrameID = session.frames.first?.id
        session.frameEdits["/preview/a.tif"] = FrameEditState()
        return session
    }
    #endif
}
