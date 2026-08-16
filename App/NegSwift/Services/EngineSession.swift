//
//  EngineSession.swift
//  NegSwift
//

import AppKit
import Foundation
import Observation
import SwiftUI

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
    private(set) var isCropToolActive = false
    private(set) var isCropOverlayReady = false
    private(set) var previewPixelSize: CGSize?

    /// Tone snapshot when crop mode opens. Crop drags can re-meter live when
    /// ``autoDensityUsesCrop`` is on (via a wire ``analysis_rect`` that busts the engine cache).
    private var cropPreviewBaseline: FrameEditState?

    /// Set when crop mode closes; thumbnail refresh waits for the post-close preview render.
    private var pendingThumbnailRefreshAfterCropClose = false

    private let client = EngineClient()
    private let preferences: AppPreferences
    private let previewDebounce = DebounceScheduler(interval: DebounceScheduler.previewInterval)
    private let saveDebounce = DebounceScheduler(interval: DebounceScheduler.saveInterval)
    private let thumbnailDebounce = DebounceScheduler(interval: DebounceScheduler.previewInterval)
    private var dirtyPaths: Set<String> = []
    private var scopedFolderURL: URL?
    private var scopedFileURLs: [String: URL] = [:]
    private var stripGeneration = 0
    private var previewGeneration = 0
    private var thumbnailGeneration = 0
    private var isThumbnailLoadRunning = false
    private(set) var isExporting = false
    private(set) var isRestartingEngine = false
    private(set) var activeExportSettings: ExportSettings?
    private(set) var exportError: String?

    private var exportTask: Task<ExportResult, Error>?

    var engineReady: Bool {
        if case .ready = state { return true }
        return false
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        preferences.onPreviewSettingsChanged = { [weak self] in
            Task { @MainActor in
                self?.applyAutoCropPreferenceToLoadedEdits()
                self?.refreshPreviewNow()
            }
        }
        preferences.onUserDataLocationChanged = { [weak self] in
            Task { @MainActor in
                await self?.restartEnginePreservingWorkspace()
            }
        }
    }

    var currentEdit: FrameEditState {
        guard let path = selectedFramePath else { return FrameEditState() }
        return frameEdits[path] ?? FrameEditState()
    }

    var selectedFrameName: String? {
        guard let id = selectedFrameID else { return nil }
        return frames.first(where: { $0.id == id })?.name
    }

    var selectedFramePath: String? {
        guard let id = selectedFrameID else { return nil }
        return frames.first(where: { $0.id == id })?.path
    }

    func clearExportError() {
        exportError = nil
    }

    func noteExportError(_ message: String) {
        exportError = message
    }

    func quickExport() async {
        guard let destination = UITestSupport.exportDestinationURL ?? RecentPathsStore.quickExportDestinationURL() else {
            exportError = "No export folder available. Use Export… to choose a destination."
            return
        }
        clearExportError()
        let gotAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        do {
            _ = try await exportCurrentFrame(to: destination, settings: .quickExport)
            RecentPathsStore.remember(destination, for: .exportFolder)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    func exportCurrentFrame(to destination: URL, settings: ExportSettings) async throws -> ExportResult {
        guard engineReady else {
            throw EngineClientError.notRunning
        }
        guard let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else {
            throw EngineClientError.notRunning
        }

        exportTask?.cancel()
        await flushPendingSaves()

        let config = pipelineConfig(for: frameEdits[path] ?? defaultEditState())
        let task = Task { () throws -> ExportResult in
            try Task.checkCancellation()
            let gotAccess = beginFileAccess(for: frame.url)
            defer {
                if gotAccess {
                    endFileAccess(for: frame.url)
                }
            }
            return try await client.export(
                path: path,
                destDir: destination.path,
                config: config,
                export: settings,
                preferGPU: PreviewRenderSettings(preferences: preferences).preferGPU
            )
        }
        exportTask = task
        isExporting = true
        activeExportSettings = settings
        exportError = nil
        defer {
            isExporting = false
            activeExportSettings = nil
            exportTask = nil
        }
        do {
            return try await task.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            exportError = error.localizedDescription
            throw error
        }
    }

    func setProcessMode(_ value: ProcessMode) { updateEdit { $0.processMode = value } }

    func autodetectProcessModeForSelectedFrame() async {
        guard let path = selectedFramePath else { return }
        guard let detected = await detectProcessMode(path: path, force: true) else { return }
        updateEdit { $0.processMode = detected }
        thumbnailGeneration += 1
        await refreshThumbnail(for: path, generation: thumbnailGeneration)
    }

    func setDensity(_ value: Double) { updateEdit { $0.density = value } }
    func setGrade(_ value: Double) { updateEdit { $0.grade = value } }
    func setSaturation(_ value: Double) { updateEdit { $0.saturation = value } }
    func setWBCyan(_ value: Double) { updateEdit { $0.wbCyan = value } }
    func setWBMagenta(_ value: Double) { updateEdit { $0.wbMagenta = value } }
    func setWBYellow(_ value: Double) { updateEdit { $0.wbYellow = value } }
    func setAutoExposure(_ value: Bool) { updateEdit { $0.autoExposure = value } }
    func setAutoNormalizeContrast(_ value: Bool) { updateEdit { $0.autoNormalizeContrast = value } }
    func setAnalysisBuffer(_ value: Double) { updateEdit { $0.analysisBuffer = value } }
    func setAutoDensityUsesCrop(_ value: Bool) { updateEdit { $0.autoDensityUsesCrop = value } }

    func resetCurrentFrameEdits() async {
        guard let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }

        previewDebounce.cancel()
        saveDebounce.cancel()
        thumbnailDebounce.cancel()
        isCropToolActive = false
        isCropOverlayReady = false
        cropPreviewBaseline = nil
        pendingThumbnailRefreshAfterCropClose = false

        frameEdits[path] = defaultEditState()
        dirtyPaths.remove(path)

        let gotAccess = beginFileAccess(for: frame.url)
        defer {
            if gotAccess {
                endFileAccess(for: frame.url)
            }
        }

        do {
            _ = try await client.resetConfig(path: path)
        } catch {
            previewError = "Could not reset edits: \(error.localizedDescription)"
            return
        }

        if preferences.autodetectProcessMode,
           let detected = await detectProcessMode(path: path, force: false)
        {
            frameEdits[path]?.processMode = detected
        }
        frameEdits[path]?.autoCropEnabled = preferences.autoCropEnabled

        if let index = frames.firstIndex(where: { $0.path == path }) {
            updateFrame(at: index) { $0.thumbnail = nil }
        }

        previewGeneration += 1
        let generation = previewGeneration
        await renderPreview(at: frame.url, generation: generation)
        await refreshThumbnail(for: path)
    }

    var isLoadingCropPreview: Bool {
        isCropToolActive && !isCropOverlayReady
    }

    func setCropToolActive(_ active: Bool) {
        guard isCropToolActive != active else { return }
        if active {
            initializeCropRectIfNeeded()
            if let path = selectedFramePath {
                cropPreviewBaseline = frameEdits[path] ?? FrameEditState()
            }
            isCropOverlayReady = false
            isCropToolActive = true
        } else {
            isCropToolActive = false
            isCropOverlayReady = false
            cropPreviewBaseline = nil
            pendingThumbnailRefreshAfterCropClose = true
            thumbnailDebounce.cancel()
        }
        refreshPreviewNow()
    }

    func setFineRotation(_ value: Double) {
        updateEdit { $0.fineRotation = value }
        syncCropPreviewBaselineGeometry(from: currentEdit)
    }

    func setAutocropRatio(_ value: String) {
        guard isCropToolActive else { return }
        updateEdit(refreshPreview: false) { edit in
            edit.autocropRatio = value
            if let size = previewPixelSize {
                edit.manualCropRect = NormalizedRect.centered(
                    ratioLabel: value,
                    imageAspect: size.width / max(size.height, 1)
                )
            }
        }
    }

    func setManualCropRect(_ rect: NormalizedRect) {
        updateEdit(refreshPreview: false) {
            $0.manualCropRect = rect
            $0.autoCropEnabled = false
        }
        guard isCropToolActive,
              currentEdit.autoExposure,
              currentEdit.autoDensityUsesCrop,
              let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }
        scheduleDebouncedPreview(for: frame)
    }

    func resetCrop() {
        updateEdit(refreshPreview: !isCropToolActive) { edit in
            edit.manualCropRect = nil
            edit.autoCropEnabled = preferences.autoCropEnabled
            if isCropToolActive, let size = previewPixelSize {
                edit.manualCropRect = NormalizedRect.centered(
                    ratioLabel: edit.autocropRatio,
                    imageAspect: size.width / max(size.height, 1)
                )
                edit.autoCropEnabled = false
            }
        }
    }

    func rotateClockwise() { applyRotation(direction: -1) }

    func rotateCounterClockwise() { applyRotation(direction: 1) }

    private func applyRotation(direction: Int) {
        updateEdit(refreshPreview: false) { edit in
            edit.rotation = (edit.rotation + direction + 4) % 4
            if let rect = edit.manualCropRect {
                edit.manualCropRect = rect.rotated(quarterTurnsCCW: direction)
            }
        }
        syncCropPreviewBaselineGeometry(from: currentEdit)
        invalidateCropOverlayForGeometryPreview()
        refreshPreviewNow()
    }

    /// Hide the crop overlay until the crop-preview render catches up with geometry edits.
    private func invalidateCropOverlayForGeometryPreview() {
        guard isCropToolActive else { return }
        isCropOverlayReady = false
    }

    private func initializeCropRectIfNeeded() {
        guard let path = selectedFramePath else { return }
        var edit = frameEdits[path] ?? defaultEditState()
        guard edit.manualCropRect == nil else { return }
        let aspect = previewPixelSize.map { $0.width / max($0.height, 1) } ?? 1.5
        edit.manualCropRect = NormalizedRect.centered(ratioLabel: edit.autocropRatio, imageAspect: aspect)
        edit.autoCropEnabled = false
        frameEdits[path] = edit
        dirtyPaths.insert(path)
    }

    private func defaultEditState() -> FrameEditState {
        var edit = FrameEditState()
        edit.autoCropEnabled = preferences.autoCropEnabled
        return edit
    }

    private func applyAutoCropPreferenceToLoadedEdits() {
        let enabled = preferences.autoCropEnabled
        var changed = false
        for path in frameEdits.keys {
            guard frameEdits[path]?.manualCropRect == nil else { continue }
            if frameEdits[path]?.autoCropEnabled != enabled {
                frameEdits[path]?.autoCropEnabled = enabled
                changed = true
            }
        }
        guard changed else { return }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        Task {
            for frame in frames {
                await refreshThumbnail(for: frame.path, generation: generation)
            }
        }
    }

    /// Map UI edit state to NegPy pipeline config (auto crop, crop-tool preview metering).
    private func pipelineConfig(for config: FrameEditState) -> FrameEditState {
        var out = effectivePreviewConfig(config)
        if out.manualCropRect != nil {
            out.autoCropEnabled = false
            return out
        }
        if out.autoCropEnabled {
            out.autocropRatio = "Free"
        }
        return out
    }

    private func effectivePreviewConfig(_ config: FrameEditState) -> FrameEditState {
        guard isCropToolActive, let baseline = cropPreviewBaseline else { return config }
        if config.autoDensityUsesCrop {
            return config
        }
        var preview = baseline
        preview.rotation = config.rotation
        preview.fineRotation = config.fineRotation
        preview.manualCropRect = config.manualCropRect
        preview.analysisBuffer = config.analysisBuffer
        preview.autoDensityUsesCrop = config.autoDensityUsesCrop
        return preview
    }

    private func syncCropPreviewBaselineGeometry(from config: FrameEditState) {
        guard isCropToolActive, var baseline = cropPreviewBaseline else { return }
        baseline.rotation = config.rotation
        baseline.fineRotation = config.fineRotation
        baseline.manualCropRect = config.manualCropRect
        cropPreviewBaseline = baseline
    }

    private func refreshPreviewNow() {
        guard let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }
        previewDebounce.cancel()
        previewGeneration += 1
        let generation = previewGeneration
        Task {
            await renderPreview(at: frame.url, generation: generation)
        }
    }

    private func updateEdit(refreshPreview: Bool = true, _ transform: (inout FrameEditState) -> Void) {
        guard let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }
        var edit = frameEdits[path] ?? defaultEditState()
        transform(&edit)
        frameEdits[path] = edit
        dirtyPaths.insert(path)
        scheduleDebouncedSave(for: path)
        if refreshPreview {
            scheduleDebouncedPreview(for: frame)
        }
    }

    private func scheduleDebouncedSave(for path: String) {
        saveDebounce.schedule { [weak self] in
            guard let self else { return }
            await self.persistEdit(for: path)
        }
    }

    func flushPendingSaves() async {
        saveDebounce.cancel()
        let paths = dirtyPaths
        for path in paths {
            await persistEdit(for: path)
        }
    }

    private func persistEdit(for path: String) async {
        guard dirtyPaths.contains(path), let edit = frameEdits[path] else { return }
        guard let frame = frames.first(where: { $0.path == path }) else { return }

        let gotAccess = beginFileAccess(for: frame.url)
        defer {
            if gotAccess {
                endFileAccess(for: frame.url)
            }
        }

        do {
            _ = try await client.saveConfig(path: path, config: pipelineConfig(for: edit))
            dirtyPaths.remove(path)
        } catch {
            previewError = "Could not save edits: \(error.localizedDescription)"
        }
    }

    private func scheduleDebouncedPreview(for frame: ScanFrame) {
        previewGeneration += 1
        let generation = previewGeneration
        previewDebounce.schedule { [weak self] in
            guard let self else { return }
            await self.renderPreview(
                at: frame.url,
                generation: generation
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
        await restartEnginePreservingWorkspace(clearWorkspace: true)
    }

    func restartEnginePreservingWorkspace(clearWorkspace: Bool = false) async {
        isRestartingEngine = true
        defer { isRestartingEngine = false }

        await flushPendingSaves()

        let savedFrames = frames
        let savedSelected = selectedFrameID
        let savedEdits = frameEdits
        let savedFolder = scopedFolderURL
        let savedFiles = scopedFileURLs

        previewDebounce.cancel()
        thumbnailDebounce.cancel()
        saveDebounce.cancel()

        await client.stop()
        state = .idle
        previewImage = nil
        previewError = nil
        currentPath = nil
        isRenderingPreview = false

        if clearWorkspace {
            clearFilmStrip()
            stopFolderAccess()
            stopFileAccess()
        } else {
            frames = savedFrames
            selectedFrameID = savedSelected
            frameEdits = savedEdits
            scopedFolderURL = savedFolder
            scopedFileURLs = savedFiles
        }

        await start()

        guard !clearWorkspace,
              let id = selectedFrameID,
              let frame = frames.first(where: { $0.id == id })
        else { return }

        previewGeneration += 1
        let generation = previewGeneration
        await renderPreview(at: frame.url, generation: generation)
        thumbnailGeneration += 1
        await loadMissingThumbnails()
    }

    /// Re-render after preview quality or GPU preference changes (no engine restart).
    func refreshAfterPreferenceChange() async {
        guard engineReady, let path = selectedFramePath,
              let frame = frames.first(where: { $0.path == path })
        else { return }

        previewDebounce.cancel()
        thumbnailDebounce.cancel()
        previewGeneration += 1
        let previewGen = previewGeneration
        stripGeneration += 1
        let stripGen = stripGeneration

        for index in frames.indices {
            updateFrame(at: index) { $0.thumbnail = nil }
        }

        await renderPreview(at: frame.url, generation: previewGen)
        await loadThumbnails(generation: stripGen)
    }

    func stop() async {
        await flushPendingSaves()
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
        } catch {
            previewError = error.localizedDescription
        }
    }

    func importFile(at url: URL) async {
        guard engineReady else { return }
        stripGeneration += 1
        let frame = ScanFrame(
            id: UUID(),
            url: url,
            path: url.path,
            name: url.lastPathComponent
        )
        frames = [frame]
        await selectFrame(frame.id)
    }

    func importFileFromPicker(_ url: URL) async {
        if url.startAccessingSecurityScopedResource() {
            scopedFileURLs[url.path] = url
        }
        await importFile(at: url)
    }

    func importDroppedURLs(_ urls: [URL]) async {
        guard engineReady else { return }
        previewError = nil

        switch ImportDropResolver.action(for: urls) {
        case let .folder(url):
            await importFolder(at: url)
        case let .singleFile(url):
            await importFileFromPicker(url)
        case let .multipleFiles(urls):
            await importDroppedFiles(urls)
        case let .unsupported(message):
            previewError = message
        }
    }

    private func importDroppedFiles(_ urls: [URL]) async {
        stopFolderAccess()
        stopFileAccess()
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                scopedFileURLs[url.path] = url
            }
        }
        if let first = urls.first {
            RecentPathsStore.remember(first.deletingLastPathComponent(), for: .openFileDirectory)
        }
        stripGeneration += 1
        previewError = nil
        do {
            let discovered = try await client.discover(paths: urls.map(\.path))
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
                previewError = "No supported scans in the dropped files."
            }
        } catch {
            previewError = error.localizedDescription
        }
    }

    func selectFrame(_ id: UUID) async {
        let selectStart = CFAbsoluteTimeGetCurrent()
        let previousPath = selectedFramePath
        isCropToolActive = false
        isCropOverlayReady = false
        cropPreviewBaseline = nil
        pendingThumbnailRefreshAfterCropClose = false
        selectedFrameID = id
        guard let frame = frames.first(where: { $0.id == id }) else { return }
        if let previousPath, previousPath != frame.path {
            saveDebounce.cancel()
            await persistEdit(for: previousPath)
            await refreshThumbnail(for: previousPath)
        }
        await ensureEditLoaded(for: frame.path)
        previewDebounce.cancel()
        previewGeneration += 1
        let generation = previewGeneration
        await renderPreview(at: frame.url, generation: generation)
        await loadMissingThumbnails()
        if PerformanceLogger.isEnabled {
            let ms = (CFAbsoluteTimeGetCurrent() - selectStart) * 1000
            PerformanceLogger.event("frame_switch_total", milliseconds: ms)
        }
    }

    private func ensureEditLoaded(for path: String) async {
        _ = await frameEditState(for: path)
    }

    private func frameEditState(for path: String) async -> FrameEditState {
        if let cached = frameEdits[path] {
            return cached
        }
        let edit = await fetchFrameEditState(for: path)
        frameEdits[path] = edit
        return edit
    }

    private func fetchFrameEditState(for path: String) async -> FrameEditState {
        do {
            let loaded = try await client.loadConfig(path: path)
            let flat = loaded.config.mapValues(\.anyValue)
            var edit = FrameEditState.fromFlatConfig(flat)
            if flat["auto_crop_enabled"] == nil {
                edit.autoCropEnabled = preferences.autoCropEnabled
            }
            if edit.manualCropRect != nil {
                edit.autoCropEnabled = false
            }
            if let detected = await detectProcessMode(path: path, force: false) {
                edit.processMode = detected
            }
            return edit
        } catch {
            return defaultEditState()
        }
    }

    private func detectProcessMode(path: String, force: Bool) async -> ProcessMode? {
        guard preferences.autodetectProcessMode || force else { return nil }
        guard engineReady,
              let frame = frames.first(where: { $0.path == path })
        else { return nil }

        let gotAccess = beginFileAccess(for: frame.url)
        defer {
            if gotAccess {
                endFileAccess(for: frame.url)
            }
        }

        do {
            let result = try await client.detectProcessMode(path: path, force: force)
            guard !result.skipped, let mode = result.processMode else { return nil }
            return ProcessMode.fromFlatValue(mode)
        } catch {
            return nil
        }
    }

    private func renderPreview(at url: URL, generation: Int, config: FrameEditState? = nil) async {
        guard engineReady else { return }

        let gotAccess = beginFileAccess(for: url)
        defer {
            if gotAccess {
                endFileAccess(for: url)
            }
        }

        isRenderingPreview = true
        previewError = nil

        let path = url.path
        let baseConfig = frameEdits[path] ?? config ?? defaultEditState()
        let effectiveConfig = pipelineConfig(for: baseConfig)
        let refreshThumbnailAfterClose = pendingThumbnailRefreshAfterCropClose && path == selectedFramePath

        do {
            let settings = PreviewRenderSettings(preferences: preferences)
            let result = try await PerformanceLogger.measure("render_ipc") {
                try await client.render(
                    path: path,
                    longEdgePx: settings.longEdgePx,
                    preferGPU: settings.preferGPU,
                    config: effectiveConfig,
                    cropPreviewFull: isCropToolActive
                )
            }
            guard generation == previewGeneration else { return }
            let image = await decodePreviewPNG(base64: result.pngBase64)
            guard let image else {
                previewError = "Engine returned an invalid PNG."
                await finishCropCloseThumbnailRefresh(
                    for: path,
                    generation: generation,
                    refreshAfterClose: refreshThumbnailAfterClose
                )
                return
            }
            previewImage = image
            previewPixelSize = CGSize(width: result.width, height: result.height)
            currentPath = path
            if isCropToolActive {
                isCropOverlayReady = true
            } else {
                applyPreviewToSelectedThumbnail()
            }
            await finishCropCloseThumbnailRefresh(
                for: path,
                generation: generation,
                refreshAfterClose: refreshThumbnailAfterClose
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == previewGeneration else { return }
            previewError = error.localizedDescription
            await finishCropCloseThumbnailRefresh(
                for: path,
                generation: generation,
                refreshAfterClose: refreshThumbnailAfterClose
            )
        }

        if generation == previewGeneration {
            isRenderingPreview = false
        }
    }

    private func finishCropCloseThumbnailRefresh(
        for path: String,
        generation: Int,
        refreshAfterClose: Bool
    ) async {
        guard generation == previewGeneration else { return }
        if refreshAfterClose {
            pendingThumbnailRefreshAfterCropClose = false
            if !applyPreviewToSelectedThumbnail(for: path) {
                await refreshThumbnail(for: path)
            }
        } else {
            scheduleDebouncedThumbnailRefresh(for: path)
        }
    }

    private func scheduleDebouncedThumbnailRefresh(for path: String) {
        if isCropToolActive, path == selectedFramePath { return }
        if applyPreviewToSelectedThumbnail(for: path) { return }
        guard !isThumbnailLoadRunning else { return }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        thumbnailDebounce.schedule { [weak self] in
            guard let self else { return }
            guard generation == self.thumbnailGeneration else { return }
            await self.refreshThumbnail(for: path, generation: generation)
        }
    }

    private func refreshThumbnail(for path: String, generation: Int? = nil) async {
        guard engineReady,
              let index = frames.firstIndex(where: { $0.path == path })
        else { return }
        if let generation, generation != thumbnailGeneration { return }
        if applyPreviewToSelectedThumbnail(for: path) { return }

        let frame = frames[index]
        let gotAccess = beginFileAccess(for: frame.url)
        defer {
            if gotAccess {
                endFileAccess(for: frame.url)
            }
        }

        let config = pipelineConfig(for: frameEdits[path] ?? defaultEditState())
        let stripGen = stripGeneration
        let showSpinner = frame.thumbnail == nil
        updateFrame(at: index) { $0.isLoadingThumbnail = showSpinner }
        defer { updateFrame(at: index) { $0.isLoadingThumbnail = false } }

        do {
            let preferGPU = PreviewRenderSettings(preferences: preferences).preferGPU
            let result = try await client.render(
                path: path,
                longEdgePx: FilmStripLayout.thumbnailLongEdge,
                preferGPU: preferGPU,
                config: config,
                cropPreviewFull: false
            )
            if let generation, generation != thumbnailGeneration { return }
            guard stripGen == stripGeneration else { return }
            guard let frameIndex = frames.firstIndex(where: { $0.path == path }) else { return }
            if let data = result.pngData, let image = NSImage(data: data) {
                updateFrame(at: frameIndex) { $0.thumbnail = image }
            }
        } catch {
            // Thumbnail failure is non-fatal; full preview may still work.
        }
    }

    private func updateFrame(at index: Int, _ transform: (inout ScanFrame) -> Void) {
        guard frames.indices.contains(index) else { return }
        var frame = frames[index]
        transform(&frame)
        frames[index] = frame
    }

    private func loadMissingThumbnails() async {
        resetStuckThumbnailSpinners()
        guard frames.contains(where: { $0.thumbnail == nil }) else { return }
        guard !isThumbnailLoadRunning else { return }
        isThumbnailLoadRunning = true
        defer { isThumbnailLoadRunning = false }
        await loadThumbnails(generation: stripGeneration)
    }

    private func resetStuckThumbnailSpinners() {
        for index in frames.indices where frames[index].thumbnail == nil && frames[index].isLoadingThumbnail {
            updateFrame(at: index) { $0.isLoadingThumbnail = false }
        }
    }

    private func loadThumbnails(generation: Int) async {
        // Preview completion schedules a debounced thumb for the selected frame;
        // cancel it so that job does not pre-empt the next strip thumbnail.
        thumbnailDebounce.cancel()
        thumbnailGeneration += 1
        for index in frames.indices {
            guard generation == stripGeneration else {
                resetStuckThumbnailSpinners()
                return
            }
            guard frames[index].thumbnail == nil else { continue }
            if applyPreviewToSelectedThumbnail(for: frames[index].path) { continue }

            updateFrame(at: index) { $0.isLoadingThumbnail = true }
            defer { updateFrame(at: index) { $0.isLoadingThumbnail = false } }

            let path = frames[index].path
            let config = await frameEditState(for: path)
            let preferGPU = PreviewRenderSettings(preferences: preferences).preferGPU
            do {
                let result = try await client.render(
                    path: path,
                    longEdgePx: FilmStripLayout.thumbnailLongEdge,
                    preferGPU: preferGPU,
                    config: config,
                    cropPreviewFull: false
                )
                guard generation == stripGeneration else {
                    resetStuckThumbnailSpinners()
                    return
                }
                if let data = result.pngData, let image = NSImage(data: data) {
                    updateFrame(at: index) { $0.thumbnail = image }
                }
            } catch {
                // Thumbnail failure is non-fatal; full preview may still work.
            }
        }
    }

    private func clearFilmStrip() {
        stripGeneration += 1
        previewGeneration += 1
        previewDebounce.cancel()
        saveDebounce.cancel()
        thumbnailDebounce.cancel()
        stopFolderAccess()
        stopFileAccess()
        frames = []
        selectedFrameID = nil
        frameEdits = [:]
        dirtyPaths = []
        isCropToolActive = false
        isCropOverlayReady = false
        cropPreviewBaseline = nil
        pendingThumbnailRefreshAfterCropClose = false
        previewPixelSize = nil
    }

    private func beginFileAccess(for url: URL) -> Bool {
        if let folder = scopedFolderURL, url.path.hasPrefix(folder.path) {
            return false
        }
        if scopedFileURLs[url.path] != nil {
            return false
        }
        return url.startAccessingSecurityScopedResource()
    }

    private func endFileAccess(for url: URL) {
        if let folder = scopedFolderURL, url.path.hasPrefix(folder.path) {
            return
        }
        if scopedFileURLs[url.path] != nil {
            return
        }
        url.stopAccessingSecurityScopedResource()
    }

    private func stopFileAccess() {
        for url in scopedFileURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        scopedFileURLs = [:]
    }

    private func stopFolderAccess() {
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL = nil
    }

    private func decodePreviewPNG(base64: String) async -> NSImage? {
        if PerformanceLogger.isEnabled {
            let start = CFAbsoluteTimeGetCurrent()
            guard let cgImage = await Self.decodePNGCGImageOffMain(base64: base64) else { return nil }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            PerformanceLogger.event("render_decode_png", milliseconds: ms)
            return image
        }
        guard let cgImage = await Self.decodePNGCGImageOffMain(base64: base64) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    /// Base64 + PNG decode off the main thread; ``NSImage`` is built on the main actor (AppKit is not thread-safe).
    nonisolated private static func decodePNGCGImageOffMain(base64: String) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = Data(base64Encoded: base64) else { return nil as CGImage? }
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return image
        }.value
    }

    #if DEBUG
    func decodePreviewPNGForTesting(base64: String) async -> NSImage? {
        await decodePreviewPNG(base64: base64)
    }
    #endif

    @discardableResult
    private func applyPreviewToSelectedThumbnail(for path: String? = nil) -> Bool {
        let targetPath = path ?? selectedFramePath
        guard let targetPath,
              targetPath == selectedFramePath,
              targetPath == currentPath,
              !isCropToolActive,
              let preview = previewImage,
              let index = frames.firstIndex(where: { $0.path == targetPath }),
              let thumbnail = Self.makeStripThumbnail(from: preview)
        else { return false }
        updateFrame(at: index) { $0.thumbnail = thumbnail }
        return true
    }

    nonisolated private static func makeStripThumbnail(from preview: NSImage) -> NSImage? {
        let longEdge = CGFloat(FilmStripLayout.thumbnailLongEdge)
        let sourceSize = preview.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = longEdge / max(sourceSize.width, sourceSize.height)
        let targetSize = NSSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        preview.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }

    static var preview: EngineSession {
        let session = EngineSession(preferences: AppPreferences())
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
}
