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

    private let client = EngineClient()
    private var scopedFolderURL: URL?
    private var stripGeneration = 0
    private var previewGeneration = 0

    var engineReady: Bool {
        if case .ready = state { return true }
        return false
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
        previewGeneration += 1
        let generation = previewGeneration
        await renderPreview(at: frame.url, generation: generation)
    }

    private func renderPreview(at url: URL, generation: Int) async {
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
            let result = try await client.render(path: url.path)
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
        stopFolderAccess()
        frames = []
        selectedFrameID = nil
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
        return session
    }
    #endif
}
