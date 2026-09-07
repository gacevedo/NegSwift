//
//  EngineBackend.swift
//  NegSwift
//

import Foundation
import NegSwiftEngine

/// Same method surface as ``EngineClient`` so ``EngineSession`` can A/B backends.
protocol EngineBackend: Sendable {
    func start() async throws
    func stop() async
    func ping() async throws
    func info() async throws -> EngineInfo
    func open(path: String, includeSplash: Bool, config: FrameEditState?) async throws -> OpenResult
    func render(
        path: String,
        longEdgePx: Int?,
        preferGPU: Bool,
        config: FrameEditState?,
        cropPreviewFull: Bool,
        stripThumbnail: Bool,
        draftPreview: Bool,
        previewFormat: PreviewTransportFormat,
        jpegQuality: Int,
        previewLongEdgePx: Int?,
        meteringAnchorFineRotation: Float?
    ) async throws -> RenderResult
    func loadConfig(path: String) async throws -> LoadConfigResult
    func detectProcessMode(path: String, force: Bool) async throws -> DetectProcessModeResult
    func saveConfig(path: String, config: FrameEditState) async throws -> SaveConfigResult
    func resetConfig(path: String) async throws -> ResetConfigResult
    func appendHealStroke(
        path: String,
        points: [[Double]],
        brushSize: Int,
        config: FrameEditState
    ) async throws -> AppendHealStrokeResult
    func undoLastHeal(path: String, config: FrameEditState) async throws -> UndoLastHealResult
    func discover(paths: [String]) async throws -> DiscoverResult
    func export(
        path: String,
        destDir: String,
        config: FrameEditState,
        export settings: ExportSettings,
        preferGPU: Bool
    ) async throws -> ExportResult
    func cancel(jobID: String) async throws
    /// Warm neighbor linear buffers (native LRU / Python PreviewManager). Strip priority.
    func prefetchLinear(path: String, maxLongEdge: Int?, analysisOversample: Bool) async throws
    /// Drop queued strip thumbs / prefetch when the selected frame changes.
    func cancelQueuedStripJobs() async
    /// S13k: settled processed preview on disk for this path + config.
    func hasSettledPreviewDiskCache(path: String, config: FrameEditState?, previewLongEdgePx: Int) async -> Bool
}

enum EngineBackendFactory {
    static func make(_ kind: EngineBackendKind) -> any EngineBackend {
        switch kind {
        case .python:
            PythonEngineBackend()
        case .swift:
            NativeEngineBackend()
        }
    }
}

actor PythonEngineBackend: EngineBackend {
    private let client = EngineClient()

    func start() async throws {
        try await client.start()
    }

    func stop() async {
        await client.stop()
    }

    func ping() async throws {
        try await client.ping()
    }

    func info() async throws -> EngineInfo {
        try await client.info()
    }

    func open(path: String, includeSplash: Bool, config: FrameEditState?) async throws -> OpenResult {
        try await client.open(path: path, includeSplash: includeSplash, config: config)
    }

    func render(
        path: String,
        longEdgePx: Int?,
        preferGPU: Bool,
        config: FrameEditState?,
        cropPreviewFull: Bool,
        stripThumbnail: Bool,
        draftPreview: Bool = false,
        previewFormat: PreviewTransportFormat,
        jpegQuality: Int,
        previewLongEdgePx: Int? = nil,
        meteringAnchorFineRotation: Float? = nil
    ) async throws -> RenderResult {
        _ = draftPreview
        _ = previewLongEdgePx
        _ = meteringAnchorFineRotation
        return try await client.render(
            path: path,
            longEdgePx: longEdgePx,
            preferGPU: preferGPU,
            config: config,
            cropPreviewFull: cropPreviewFull,
            stripThumbnail: stripThumbnail,
            previewFormat: previewFormat,
            jpegQuality: jpegQuality
        )
    }

    func loadConfig(path: String) async throws -> LoadConfigResult {
        try await client.loadConfig(path: path)
    }

    func detectProcessMode(path: String, force: Bool) async throws -> DetectProcessModeResult {
        try await client.detectProcessMode(path: path, force: force)
    }

    func saveConfig(path: String, config: FrameEditState) async throws -> SaveConfigResult {
        try await client.saveConfig(path: path, config: config)
    }

    func resetConfig(path: String) async throws -> ResetConfigResult {
        try await client.resetConfig(path: path)
    }

    func appendHealStroke(
        path: String,
        points: [[Double]],
        brushSize: Int,
        config: FrameEditState
    ) async throws -> AppendHealStrokeResult {
        try await client.appendHealStroke(path: path, points: points, brushSize: brushSize, config: config)
    }

    func undoLastHeal(path: String, config: FrameEditState) async throws -> UndoLastHealResult {
        try await client.undoLastHeal(path: path, config: config)
    }

    func discover(paths: [String]) async throws -> DiscoverResult {
        try await client.discover(paths: paths)
    }

    func export(
        path: String,
        destDir: String,
        config: FrameEditState,
        export settings: ExportSettings,
        preferGPU: Bool
    ) async throws -> ExportResult {
        try await client.export(
            path: path,
            destDir: destDir,
            config: config,
            export: settings,
            preferGPU: preferGPU
        )
    }

    func cancel(jobID: String) async throws {
        try await client.cancel(jobID: jobID)
    }

    func prefetchLinear(path: String, maxLongEdge: Int?, analysisOversample: Bool) async throws {
        _ = maxLongEdge
        _ = analysisOversample
        _ = try await client.open(path: path, includeSplash: false, config: nil)
    }

    func cancelQueuedStripJobs() async {
        await client.cancelQueuedStripJobs()
    }

    func hasSettledPreviewDiskCache(path: String, config: FrameEditState?, previewLongEdgePx: Int) async -> Bool {
        false
    }
}

actor NativeEngineBackend: EngineBackend {
    /// Bumped on ``stop`` so an in-flight detached render is discarded.
    private var workGeneration = 0

    func start() async throws {
        let cacheRoot = AppPreferencesStorage.resolvedNegPyUserDirectoryURL()
            .appendingPathComponent("processed_previews", isDirectory: true)
        NativePipeline.configureDiskPreviewCache(rootDirectory: cacheRoot)
    }

    func stop() async {
        workGeneration += 1
        NativeJobQueue.shared.cancelStripJobs()
    }

    func ping() async throws {}

    func info() async throws -> EngineInfo {
        EngineInfo(
            protocolVersion: EngineVersion.protocolVersion,
            negswiftVersion: EngineVersion.packageVersion,
            negpyVersion: EngineVersion.oracleLabel,
            python: "n/a",
            gpuAvailable: MetalDevice.isAvailable,
            gpuBackend: MetalDevice.isAvailable ? MetalDevice.backendName : EngineVersion.backendName
        )
    }

    func open(path: String, includeSplash: Bool, config: FrameEditState?) async throws -> OpenResult {
        let dims = NativePipeline().probeSource(at: path) ?? (1, 1)
        var suggestedCropRect: [Double]?
        var cropDetectKey: String?
        // includeSplash: false stays a cheap probe (dimensions). Neighbor linear
        // prefetch is prefetchLinear — selected-frame work does not wait on it.
        // Splash is an embedded JPEG (or TIFF preview page); it does not decode linear.
        // Armed crop reuses the S13d linear LRU (same oversampled sample as detect/print).
        let splash = includeSplash ? NativePipeline().splashJPEG(path: path) : nil
        if includeSplash {
            let printConfig = Self.printInputs(from: config).printConfig
            if Autocrop.isArmed(printConfig), printConfig.cropRect == nil {
                do {
                    let generation = workGeneration
                    let resolved = try await Self.performSelected(path: path) {
                        let preview = try NativePipeline().decode(
                            path: path,
                            maxLongEdge: Autocrop.detectResolution,
                            analysisOversample: true
                        )
                        return Autocrop.resolveRect(preview, config: printConfig)
                    }
                    guard generation == workGeneration else {
                        throw CancellationError()
                    }
                    if let rect = resolved {
                        suggestedCropRect = rect.arrayValue
                        cropDetectKey = Autocrop.detectionKey(printConfig)
                    }
                } catch let error as LinearDecodeError {
                    throw Self.mapDecode(error)
                }
            }
        }
        return OpenResult(
            path: path,
            hash: Self.fileToken(path),
            width: dims.width,
            height: dims.height,
            hasSidecar: SidecarLocator.exists(forScanPath: path),
            splashWidth: splash?.width,
            splashHeight: splash?.height,
            splashJPEGBase64: splash.map { $0.jpeg.base64EncodedString() },
            suggestedCropRect: suggestedCropRect,
            cropDetectKey: cropDetectKey
        )
    }

    func render(
        path: String,
        longEdgePx: Int?,
        preferGPU: Bool,
        config: FrameEditState?,
        cropPreviewFull: Bool,
        stripThumbnail: Bool,
        draftPreview: Bool = false,
        previewFormat: PreviewTransportFormat,
        jpegQuality: Int,
        previewLongEdgePx: Int? = nil,
        meteringAnchorFineRotation: Float? = nil
    ) async throws -> RenderResult {
        _ = preferGPU
        let generation = workGeneration
        let mapped = Self.printInputs(from: config)
        var printConfig = mapped.printConfig
        // Crop-tool preview stays full-bleed; stored crop still remaps to analysis_rect.
        printConfig.applyPixelCrop = !cropPreviewFull
        let result: RenderResult
        do {
            if stripThumbnail {
                result = try await Self.performStrip(lane: .raster) {
                    if let previewEdge = previewLongEdgePx,
                       let thumbEdge = longEdgePx,
                       let processed = try Self.performProcessedStripThumb(
                           path: path,
                           thumbLongEdge: thumbEdge,
                           previewLongEdge: previewEdge,
                           processMode: mapped.processMode,
                           printConfig: printConfig
                       )
                    {
                        return processed
                    }
                    return try Self.performCheapThumb(
                        path: path,
                        longEdgePx: longEdgePx,
                        processMode: mapped.processMode,
                        printConfig: printConfig
                    )
                }
            } else {
                result = try await Self.performSelected(path: path) {
                    try Self.performRender(
                        path: path,
                        longEdgePx: longEdgePx,
                        processMode: mapped.processMode,
                        printConfig: printConfig,
                        previewPass: draftPreview ? .draft : .settled,
                        previewFormat: previewFormat,
                        jpegQuality: jpegQuality,
                        meteringAnchorFineRotation: meteringAnchorFineRotation
                    )
                }
            }
        } catch let error as LinearDecodeError {
            throw Self.mapDecode(error)
        }
        guard generation == workGeneration else { throw CancellationError() }
        return result
    }

    func hasSettledPreviewDiskCache(path: String, config: FrameEditState?, previewLongEdgePx: Int) async -> Bool {
        let mapped = Self.printInputs(from: config)
        var printConfig = mapped.printConfig
        printConfig.applyPixelCrop = true
        return NativePipeline().hasProcessedPreviewDiskCache(
            path: path,
            longEdgePx: previewLongEdgePx,
            processMode: mapped.processMode,
            config: printConfig
        )
    }

    func loadConfig(path: String) async throws -> LoadConfigResult {
        let loaded = try SidecarStore.load(path: path)
        return LoadConfigResult(config: try Self.jsonValues(loaded.config), hasSidecar: loaded.hasSidecar)
    }

    func detectProcessMode(path: String, force: Bool) async throws -> DetectProcessModeResult {
        if !force, SidecarLocator.exists(forScanPath: path) {
            return DetectProcessModeResult(
                skipped: true,
                reason: "has_sidecar",
                detectedMode: nil,
                processMode: nil
            )
        }
        do {
            let generation = workGeneration
            let mode = try await Self.performSelected(path: path) {
                try NativePipeline().detectProcessMode(path: path)
            }
            guard generation == workGeneration else { throw CancellationError() }
            return DetectProcessModeResult(
                skipped: false,
                reason: nil,
                detectedMode: mode.rawValue,
                processMode: mode.liteMode.rawValue
            )
        } catch let error as LinearDecodeError {
            throw Self.mapDecode(error)
        }
    }

    func saveConfig(path: String, config: FrameEditState) async throws -> SaveConfigResult {
        do {
            let sidecar = try SidecarStore.save(path: path, overrides: try Self.flatOverrides(config))
            return SaveConfigResult(sidecarPath: sidecar)
        } catch {
            throw EngineClientError.engine(EngineErrorPayload(code: "SAVE_FAILED", message: error.localizedDescription))
        }
    }

    func resetConfig(path: String) async throws -> ResetConfigResult {
        let removed = try SidecarStore.reset(path: path)
        return ResetConfigResult(sidecarRemoved: removed)
    }

    func appendHealStroke(
        path: String,
        points: [[Double]],
        brushSize: Int,
        config: FrameEditState
    ) async throws -> AppendHealStrokeResult {
        let payload = try HealStore.appendStroke(
            path: path,
            points: points,
            brushSize: Double(brushSize),
            configOverrides: try Self.flatOverrides(config)
        )
        return try Self.decode(AppendHealStrokeResult.self, from: payload)
    }

    func undoLastHeal(path: String, config: FrameEditState) async throws -> UndoLastHealResult {
        let payload = try HealStore.undoLast(path: path, configOverrides: try Self.flatOverrides(config))
        return try Self.decode(UndoLastHealResult.self, from: payload)
    }

    func discover(paths: [String]) async throws -> DiscoverResult {
        var assets: [DiscoverAsset] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                for name in names {
                    let full = (path as NSString).appendingPathComponent(name)
                    if Self.isSupportedScan(full) {
                        assets.append(DiscoverAsset(path: full, name: name))
                    }
                }
            } else if Self.isSupportedScan(path) {
                assets.append(DiscoverAsset(path: path, name: (path as NSString).lastPathComponent))
            }
        }
        let unique = Dictionary(assets.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return DiscoverResult(assets: sorted)
    }

    func export(
        path: String,
        destDir: String,
        config: FrameEditState,
        export settings: ExportSettings,
        preferGPU: Bool
    ) async throws -> ExportResult {
        _ = preferGPU
        let generation = workGeneration
        let mapped = Self.printInputs(from: config)
        let nativeSettings = NativeExportSettings(
            format: settings.format == .tiff ? .tiff : .jpeg,
            jpegQuality: settings.jpegQuality,
            overwrite: false,
            resolutionMode: settings.resolutionMode == .targetLongEdge ? .targetPx : .original,
            targetLongEdgePx: settings.targetLongEdgePx
        )
        let result: ExportResult
        do {
            result = try await Self.performSelected(path: path) {
                let exported = try PerformanceLogger.measureSync("native_export_ms") {
                    try NativePipeline(pixelBackend: .auto).export(
                        path: path,
                        destDir: destDir,
                        processMode: mapped.processMode,
                        config: mapped.printConfig,
                        settings: nativeSettings
                    )
                }
                return ExportResult(
                    outputPath: exported.url.path,
                    width: exported.width,
                    height: exported.height,
                    format: exported.format
                )
            }
        } catch let error as LinearDecodeError {
            throw Self.mapDecode(error)
        } catch let failure as ProtocolFailure {
            throw EngineClientError.engine(EngineErrorPayload(code: failure.code, message: failure.message))
        } catch {
            throw EngineClientError.engine(
                EngineErrorPayload(code: "EXPORT_FAILED", message: error.localizedDescription)
            )
        }
        guard generation == workGeneration else { throw CancellationError() }
        return result
    }

    func cancel(jobID: String) async throws {
        _ = jobID
    }

    func prefetchLinear(path: String, maxLongEdge: Int?, analysisOversample: Bool) async throws {
        let generation = workGeneration
        do {
            _ = try await Self.performStrip(lane: NativeJobQueue.prefetchLane(forScan: path)) {
                try NativePipeline().prefetchLinear(
                    path: path,
                    maxLongEdge: maxLongEdge,
                    analysisOversample: analysisOversample
                )
            }
        } catch let error as LinearDecodeError {
            throw Self.mapDecode(error)
        } catch is CancellationError {
            throw CancellationError()
        }
        guard generation == workGeneration else { throw CancellationError() }
    }

    func cancelQueuedStripJobs() async {
        NativeJobQueue.shared.cancelStripJobs()
    }

    nonisolated static func printInputs(from config: FrameEditState?) -> (
        processMode: FilmProcessMode?,
        printConfig: PrintConfig
    ) {
        var printConfig = PrintConfig.s8Pin
        guard let config else {
            return (nil, printConfig)
        }
        printConfig.density = Float(config.density)
        printConfig.grade = Float(config.grade)
        printConfig.shadowDensity = Float(config.shadowDensity)
        printConfig.highlightDensity = Float(config.highlightDensity)
        printConfig.shadowGrade = Float(config.shadowGrade)
        printConfig.highlightGrade = Float(config.highlightGrade)
        printConfig.wbCyan = Float(config.wbCyan)
        printConfig.wbMagenta = Float(config.wbMagenta)
        printConfig.wbYellow = Float(config.wbYellow)
        printConfig.saturation = Float(config.saturation)
        printConfig.analysisBuffer = Float(config.analysisBuffer)
        printConfig.autoExposure = config.autoExposure
        printConfig.autoNormalizeContrast = config.autoNormalizeContrast
        printConfig.autoDensityUsesCrop = config.autoDensityUsesCrop
        printConfig.cropFromAuto = config.cropFromAuto
        printConfig.autoCropEnabled = config.autoCropEnabled
        printConfig.rotation = config.rotation
        printConfig.flipHorizontal = config.flipHorizontal
        printConfig.flipVertical = config.flipVertical
        printConfig.fineRotation = Float(config.fineRotation)
        if let crop = config.manualCropRect {
            printConfig.cropRect = NormalizedCropRect(
                x1: crop.x1,
                y1: crop.y1,
                x2: crop.x2,
                y2: crop.y2
            )
        }
        printConfig.healStrokes = config.manualHealStrokes.map { stroke in
            NegSwiftEngine.HealStroke(
                points: stroke.points.map { HealPoint(x: $0.x, y: $0.y) },
                size: stroke.size
            )
        }
        printConfig.dustRemove = config.dustRemove
        printConfig.dustThreshold = Float(config.dustThreshold)
        printConfig.dustSize = max(1, config.dustSize)
        printConfig = printConfig.applyingMeteringRemap()
        let processMode = FilmProcessMode(rawValue: config.processMode.rawValue) ?? .colorNegative
        return (processMode, printConfig)
    }

    /// Raster strip (thumbs / TIFF prefetch) overlaps selected TIFF print. RAW stays
    /// one worker. ``cancelQueuedStripJobs`` drops queued strip work on frame change.
    private static func performSelected<T: Sendable>(
        path: String,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await NativeJobQueue.shared.submit(
            kind: .selected,
            lane: NativeJobQueue.selectedLane(forScan: path),
            operation: operation
        )
    }

    private static func performStrip<T: Sendable>(
        lane: NativeJobLane,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await NativeJobQueue.shared.submit(
            kind: .strip,
            lane: lane,
            operation: operation
        )
    }

    private static func performRender(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode?,
        printConfig: PrintConfig,
        previewPass: PreviewPass,
        previewFormat: PreviewTransportFormat,
        jpegQuality: Int,
        meteringAnchorFineRotation: Float? = nil
    ) throws -> RenderResult {
        let detailed = try NativePipeline(pixelBackend: .auto).renderPrintDetailed(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: printConfig,
            previewPass: previewPass,
            readback: false,
            meteringAnchorFineRotation: meteringAnchorFineRotation
        )
        var metrics: RenderMetrics?
        if detailed.resolvedAutocrop != nil || detailed.cropRect != nil {
            metrics = RenderMetrics(
                detectedCropRect: detailed.cropRect?.arrayValue,
                autocropResolvedRect: detailed.resolvedAutocrop?.arrayValue,
                autocropResolvedKey: detailed.resolvedAutocrop?.key
            )
        }
        _ = previewFormat
        _ = jpegQuality
        if let present = detailed.gpuPresent {
            return RenderResult(
                width: present.width,
                height: present.height,
                previewFormat: "cgimage",
                pngBase64: nil,
                jpegBase64: nil,
                metrics: metrics,
                nativePreview: NativePreview(cgImage: present.cgImage, ciImage: present.ciImage),
                reusedDiskCache: detailed.reusedDiskCache
            )
        }
        let buffer = detailed.buffer
        let cgImage = try DisplayTransform.workingImage(fromWorkingSpace: buffer, bitsPerComponent: 8)
        return RenderResult(
            width: buffer.width,
            height: buffer.height,
            previewFormat: "cgimage",
            pngBase64: nil,
            jpegBase64: nil,
            metrics: metrics,
            nativePreview: NativePreview(cgImage: cgImage),
            reusedDiskCache: detailed.reusedDiskCache
        )
    }

    private static func performProcessedStripThumb(
        path: String,
        thumbLongEdge: Int,
        previewLongEdge: Int,
        processMode: FilmProcessMode?,
        printConfig: PrintConfig
    ) throws -> RenderResult? {
        guard let buffer = NativePipeline().processedStripThumb(
            path: path,
            thumbLongEdge: thumbLongEdge,
            previewLongEdge: previewLongEdge,
            processMode: processMode,
            config: printConfig
        ) else { return nil }
        guard let cgImage = try? DisplayTransform.workingImage(fromWorkingSpace: buffer, bitsPerComponent: 8) else {
            return nil
        }
        return RenderResult(
            width: buffer.width,
            height: buffer.height,
            previewFormat: "cgimage",
            pngBase64: nil,
            jpegBase64: nil,
            metrics: nil,
            nativePreview: NativePreview(cgImage: cgImage),
            reusedDiskCache: true
        )
    }

    private static func performCheapThumb(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode?,
        printConfig: PrintConfig
    ) throws -> RenderResult {
        let buffer = try NativePipeline().cheapThumb(
            path: path,
            longEdgePx: longEdgePx ?? 256,
            processMode: processMode,
            config: printConfig
        )
        guard let cgImage = ImageCoding.sRGBDisplayImage(from: buffer) else {
            throw LinearDecodeError.decodeFailed
        }
        return RenderResult(
            width: buffer.width,
            height: buffer.height,
            previewFormat: "cgimage",
            pngBase64: nil,
            jpegBase64: nil,
            metrics: nil,
            nativePreview: NativePreview(cgImage: cgImage)
        )
    }

    private static func isSupportedScan(_ path: String) -> Bool {
        ScanFormat.isSupportedScan(path)
    }

    private static func fileToken(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? NSNumber ?? 0
        return "s0-\(size.intValue)"
    }

    nonisolated private static func flatOverrides(_ config: FrameEditState) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }

    nonisolated private static func jsonValues(_ dict: [String: Any]) throws -> [String: JSONValue] {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    nonisolated private static func decode<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func notImplemented(_ message: String) -> EngineClientError {
        .engine(EngineErrorPayload(code: "NOT_IMPLEMENTED", message: message))
    }

    private static func mapDecode(_ error: LinearDecodeError) -> EngineClientError {
        switch error {
        case .fileNotFound:
            .engine(EngineErrorPayload(code: "NOT_FOUND", message: error.localizedDescription))
        case .unsupported, .decodeFailed, .rawUnavailable, .rawDecodeFailed:
            .engine(EngineErrorPayload(code: "DECODE_FAILED", message: error.localizedDescription))
        }
    }
}
