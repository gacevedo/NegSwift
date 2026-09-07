import Foundation

public struct RenderPrintResult: Sendable {
    public var buffer: LinearRGBBuffer
    /// Present only when this render ran border detection and produced a new rect.
    public var resolvedAutocrop: AutocropResolved?
    /// Crop after resolve (stored or newly detected). Used for `detected_crop_rect`.
    public var cropRect: NormalizedCropRect?
    /// S13a: bake (dust/heal) reused from the reprint cache.
    public var reusedBake: Bool
    /// S13a: orient + bounds + metering reused from the reprint cache.
    public var reusedAnalysis: Bool
    /// S13c: this render uploaded post-dust/heal linear to Metal.
    public var uploadedLinear: Bool
    /// S13h: this render `getBytes`'d the float working set (MAE / export / CLI).
    public var downloadedLinear: Bool
    /// S13h: Adobe RGB GPU present (no ColorSync hop). Set when `readback` is false.
    public var gpuPresent: GPUPresentImage?
    /// S13g: draft (first paint) or settled (refine / slider).
    public var previewPass: PreviewPass
    /// S13g: ImageIO/LibRaw sample used the ≥4096 analysis oversample.
    public var analysisOversampled: Bool
    /// S13k: settled preview loaded from the on-disk processed cache.
    public var reusedDiskCache: Bool

    public init(
        buffer: LinearRGBBuffer,
        resolvedAutocrop: AutocropResolved?,
        cropRect: NormalizedCropRect?,
        reusedBake: Bool = false,
        reusedAnalysis: Bool = false,
        uploadedLinear: Bool = false,
        downloadedLinear: Bool = false,
        gpuPresent: GPUPresentImage? = nil,
        previewPass: PreviewPass = .settled,
        analysisOversampled: Bool = false,
        reusedDiskCache: Bool = false
    ) {
        self.buffer = buffer
        self.resolvedAutocrop = resolvedAutocrop
        self.cropRect = cropRect
        self.reusedBake = reusedBake
        self.reusedAnalysis = reusedAnalysis
        self.uploadedLinear = uploadedLinear
        self.downloadedLinear = downloadedLinear
        self.gpuPresent = gpuPresent
        self.previewPass = previewPass
        self.analysisOversampled = analysisOversampled
        self.reusedDiskCache = reusedDiskCache
    }
}

/// In-process pipeline. S13: reprint cache, Metal geometry, resident GPU present
/// without float readback, one linear decode per file, Accelerate convert/resize,
/// splash + cheap thumbs, progressive draft / refine first paint, X-Trans PPG,
/// parallel TIFF/JPEG decode with selected-frame priority and neighbor linear prefetch.
public struct NativePipeline: Sendable {
    public var pixelBackend: PixelBackend

    public init(pixelBackend: PixelBackend = .cpu) {
        self.pixelBackend = pixelBackend
    }

    /// S13k: on-disk processed preview root. Survives ``resetWorkingSets()``.
    public static func configureDiskPreviewCache(rootDirectory: URL?) {
        ProcessedPreviewDiskCache.shared.configure(rootDirectory: rootDirectory)
    }

    /// Drop in-memory decode / reprint / resident GPU caches. Disk preview cache survives (S13k).
    public static func resetWorkingSets() {
        LinearBufferCache.shared.reset()
        NativeJobQueue.shared.reset()
        RawDecode.resetSessions()
        RawDecode.resetStats()
        ReprintCache.shared.reset()
        ProcessedPreviewDiskCache.shared.reset()
        #if canImport(Metal)
        MetalWorkingSet.shared.reset()
        MetalDevice.runtime()?.resetScratch()
        #endif
        PipelineStats.reset()
    }

    public func infoJSON() -> [String: Any] {
        let gpu = MetalDevice.isAvailable
        return [
            "protocol_version": EngineVersion.protocolVersion,
            "negswift_version": EngineVersion.packageVersion,
            "negpy_version": EngineVersion.oracleLabel,
            "python": "n/a",
            "gpu_available": gpu,
            "gpu_backend": gpu ? MetalDevice.backendName : NSNull(),
            "backend": EngineVersion.backendName,
            "pixel_backend": pixelBackend.resolved().rawValue,
            "libraw": RawDecode.isAvailable,
        ]
    }

    public func decode(
        path: String,
        maxLongEdge: Int? = nil,
        analysisOversample: Bool = false
    ) throws -> LinearRGBBuffer {
        try LinearBufferCache.shared.buffer(
            path: path,
            maxLongEdge: maxLongEdge,
            analysisOversample: analysisOversample
        )
    }

    /// Warm the linear LRU for a neighbor frame (S13j). Same sample as a settled preview.
    @discardableResult
    public func prefetchLinear(
        path: String,
        maxLongEdge: Int? = Int(Autocrop.previewRenderSize),
        analysisOversample: Bool = true
    ) throws -> LinearRGBBuffer {
        try decode(
            path: path,
            maxLongEdge: maxLongEdge,
            analysisOversample: analysisOversample
        )
    }

    /// Preview-class decode. LRU reuses a larger sample for a smaller long-edge.
    /// Draft skips analysis oversample; settled oversamples when the long edge is ≥800.
    private func decodeForPrint(
        path: String,
        longEdgePx: Int?,
        previewPass: PreviewPass = .settled
    ) throws -> LinearRGBBuffer {
        try decode(
            path: path,
            maxLongEdge: longEdgePx,
            analysisOversample: previewPass.shouldOversample(longEdgePx: longEdgePx)
        )
    }

    public func detectProcessMode(path: String) throws -> FilmProcessMode {
        try PipelineStats.measure(.detect) {
            // Oversample so detect shares the print-path ImageIO/LibRaw sample (S13d).
            let buffer = try decode(
                path: path,
                maxLongEdge: ProcessDetect.detectDecodeLongEdge,
                analysisOversample: true
            )
            return ProcessDetect.detectLite(buffer)
        }
    }

    /// Mid-gray placeholder used by S0 tests.
    public func stubPreview(longEdgePx: Int?) -> LinearRGBBuffer {
        let edge = max(32, min(longEdgePx ?? 256, 512))
        return .stub(width: edge, height: edge)
    }

    public func normalize(
        _ linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        analysisBuffer: Float = LogNormalization.defaultAnalysisBuffer
    ) -> LinearRGBBuffer {
        LogNormalization.process(
            linear: linear,
            processMode: processMode,
            analysisBuffer: analysisBuffer
        )
    }

    public func renderNormalized(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        analysisBuffer: Float = LogNormalization.defaultAnalysisBuffer
    ) throws -> LinearRGBBuffer {
        let linear = try decodeForPrint(path: path, longEdgePx: longEdgePx, previewPass: .settled)
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        return normalize(linear, processMode: mode, analysisBuffer: analysisBuffer)
    }

    /// S13 print: bake (dust/heal) → detect-once autocrop → orient → analyze →
    /// normalize → H&D + autos → Lab → crop → OETF. Slider reprints reuse the
    /// bake/orient/analyze working set. Pixel stages may run on Metal.
    /// Matches NegPy `DarkroomEngine` order (dust/heals before geometry; Lab before pixel crop).
    public func renderPrint(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin,
        previewPass: PreviewPass = .settled
    ) throws -> LinearRGBBuffer {
        try renderPrintDetailed(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: config,
            previewPass: previewPass
        ).buffer
    }

    public func renderPrintDetailed(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin,
        previewPass: PreviewPass = .settled,
        readback: Bool = true
    ) throws -> RenderPrintResult {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            switch previewPass {
            case .draft: PipelineStats.record(.firstPaint, milliseconds: ms)
            case .settled: PipelineStats.record(.fullPreview, milliseconds: ms)
            }
        }

        let passConfig = previewPass.applyingDraftShortcuts(config)
        let resolvedEdge = previewPass.resolvedLongEdge(longEdgePx)
        let oversampled = previewPass.shouldOversample(longEdgePx: resolvedEdge)
        let stamp = ReprintCache.fileStamp(path)
        let bakeKey = ReprintCache.bakeKey(
            path: path,
            stamp: stamp,
            longEdgePx: resolvedEdge,
            config: passConfig
        )
        let analysisKey = ReprintCache.analysisKey(
            bakeKey: bakeKey,
            config: passConfig,
            processMode: processMode
        )

        let shouldCache = resolvedEdge != nil && previewPass != .draft && passConfig.applyPixelCrop
        if shouldCache,
           let cachedBuffer = ProcessedPreviewDiskCache.shared.lookup(
               path: path,
               longEdgePx: resolvedEdge,
               config: passConfig,
               processMode: processMode
           )
        {
            var present: GPUPresentImage?
            if !readback, let image = try? DisplayTransform.workingImage(fromWorkingSpace: cachedBuffer) {
                present = GPUPresentImage(
                    width: cachedBuffer.width,
                    height: cachedBuffer.height,
                    cgImage: image
                )
            }
            return RenderPrintResult(
                buffer: cachedBuffer,
                resolvedAutocrop: nil,
                cropRect: passConfig.cropRect,
                reusedBake: true,
                reusedAnalysis: true,
                uploadedLinear: false,
                downloadedLinear: false,
                gpuPresent: present,
                previewPass: previewPass,
                analysisOversampled: oversampled,
                reusedDiskCache: true
            )
        }

        // Draft is a throwaway first paint — do not replace the settled reprint / Metal set.
        let cached = shouldCache ? ReprintCache.shared.lookup(analysisKey: analysisKey) : nil
        let priorBaked = cached?.baked ?? (shouldCache ? ReprintCache.shared.lookupBaked(bakeKey: bakeKey) : nil)
        let reusedAnalysis = cached != nil
        let reusedBake = priorBaked != nil
        let baked: LinearRGBBuffer
        if let priorBaked {
            baked = priorBaked
        } else {
            var linear = try decodeForPrint(
                path: path,
                longEdgePx: resolvedEdge,
                previewPass: previewPass
            )
            if passConfig.dustRemove {
                PipelineStats.increment(.dust)
                linear = PipelineStats.measure(.dust) {
                    OpticalDust.bake(linear, threshold: passConfig.dustThreshold, size: passConfig.dustSize)
                }
            }
            if !passConfig.healStrokes.isEmpty || !passConfig.dustSpots.isEmpty {
                PipelineStats.increment(.heal)
            }
            linear = PipelineStats.measure(.heal) {
                HealInpaint.bake(linear, strokes: passConfig.healStrokes, spots: passConfig.dustSpots)
            }
            baked = linear
        }

        let armed: AutocropArmedResult
        let oriented: LinearRGBBuffer
        let mode: FilmProcessMode
        let bounds: LogNegativeBounds
        let analysis: PhotometricPrint.MeteringAnalysis
        if let cached {
            var reprint = passConfig
            if let crop = cached.armed.config.cropRect {
                reprint.cropRect = crop
                reprint.cropDetectKey = cached.armed.config.cropDetectKey
                reprint.cropFromAuto = cached.armed.config.cropFromAuto
                reprint.autoCropEnabled = cached.armed.config.autoCropEnabled
            }
            armed = AutocropArmedResult(config: reprint, resolved: cached.armed.resolved)
            oriented = cached.oriented
            mode = cached.processMode
            bounds = cached.bounds
            analysis = cached.analysis
        } else {
            armed = PipelineStats.measure(.autocrop) {
                Autocrop.resolveArmed(baked, config: passConfig)
            }
            PipelineStats.increment(.autocrop)
            PipelineStats.increment(.orient)
            oriented = PipelineStats.measure(.orient) {
                if pixelBackend.resolved() == .metal,
                   let gpuOriented = MetalGeometry.oriented(
                       baked,
                       rotation: armed.config.rotation,
                       flipHorizontal: armed.config.flipHorizontal,
                       flipVertical: armed.config.flipVertical,
                       fineRotation: armed.config.fineRotation
                   )
                {
                    return gpuOriented
                }
                return baked.oriented(
                    rotation: armed.config.rotation,
                    flipHorizontal: armed.config.flipHorizontal,
                    flipVertical: armed.config.flipVertical,
                    fineRotation: armed.config.fineRotation
                )
            }
            mode = processMode ?? ProcessDetect.detectLite(oriented)
            PipelineStats.increment(.analyze)
            let remapped = armed.config.applyingMeteringRemap()
            let region = remapped.resolvedAnalysisRegion()
            bounds = PipelineStats.measure(.analyze) {
                LogNormalization.analyzeBounds(
                    linear: oriented,
                    processMode: mode,
                    analysisBuffer: region.buffer,
                    analysisRect: region.rect
                )
            }
            analysis = PipelineStats.measure(.analyze) {
                PhotometricPrint.analyzeMetering(
                    linear: oriented,
                    bounds: bounds,
                    processMode: mode,
                    config: remapped
                )
            }
            if shouldCache {
                ReprintCache.shared.store(
                    ReprintCache.Entry(
                        bakeKey: bakeKey,
                        analysisKey: analysisKey,
                        baked: baked,
                        oriented: oriented,
                        processMode: mode,
                        bounds: bounds,
                        analysis: analysis,
                        armed: armed
                    )
                )
            }
        }

        let printConfig = armed.config.applyingMeteringRemap()
        let params = PhotometricPrint.resolvePixelParams(
            linear: oriented,
            bounds: bounds,
            processMode: mode,
            config: printConfig,
            analysis: analysis
        )
        PipelineStats.increment(.print)
        let persistResident = resolvedEdge != nil && previewPass != .draft
        func persistDiskCache(_ buffer: LinearRGBBuffer, processMode mode: FilmProcessMode?) {
            guard shouldCache else { return }
            ProcessedPreviewDiskCache.shared.store(
                path: path,
                longEdgePx: resolvedEdge,
                config: passConfig,
                processMode: mode,
                buffer: buffer
            )
        }
        var gpuResult: MetalPrint.Output?
        if pixelBackend.resolved() == .metal {
            gpuResult = PipelineStats.measure(.print) {
                MetalPrint.processDetailed(
                    linear: oriented,
                    processMode: mode,
                    config: printConfig,
                    bounds: bounds,
                    params: params,
                    baked: baked,
                    bakeKey: bakeKey,
                    persistResident: persistResident,
                    readback: readback
                )
            }
        }
        if let gpu = gpuResult {
            if let present = gpu.present, !readback {
                if let cacheBuffer = gpu.cacheBuffer {
                    persistDiskCache(cacheBuffer, processMode: mode)
                }
                return RenderPrintResult(
                    buffer: LinearRGBBuffer.stub(width: 1, height: 1),
                    resolvedAutocrop: armed.resolved,
                    cropRect: printConfig.cropRect,
                    reusedBake: reusedBake,
                    reusedAnalysis: reusedAnalysis,
                    uploadedLinear: gpu.uploaded,
                    downloadedLinear: false,
                    gpuPresent: present,
                    previewPass: previewPass,
                    analysisOversampled: oversampled
                )
            }
            if let pixels = gpu.buffer {
                persistDiskCache(pixels, processMode: mode)
                return RenderPrintResult(
                    buffer: pixels,
                    resolvedAutocrop: armed.resolved,
                    cropRect: printConfig.cropRect,
                    reusedBake: reusedBake,
                    reusedAnalysis: reusedAnalysis,
                    uploadedLinear: gpu.uploaded,
                    downloadedLinear: gpu.downloaded,
                    gpuPresent: gpu.present,
                    previewPass: previewPass,
                    analysisOversampled: oversampled
                )
            }
        }
        let normalized = PipelineStats.measure(.print) {
            LogNormalization.process(
                linear: oriented,
                processMode: mode,
                analysisBuffer: printConfig.resolvedAnalysisRegion().buffer,
                analysisRect: printConfig.resolvedAnalysisRegion().rect,
                bounds: bounds
            )
        }
        var printed = PipelineStats.measure(.print) {
            PhotometricPrint.apply(normalized: normalized, params: params)
        }
        printed = PipelineStats.measure(.print) {
            PhotoLab.process(printed, config: printConfig)
        }
        if printConfig.applyPixelCrop, let crop = printConfig.cropRect {
            printed = applyStoredCrop(printed, rect: crop, offsetPx: printConfig.autocropOffset)
        }
        let encoded = WorkingOETF.encode(printed)
        var present: GPUPresentImage?
        if !readback, let image = try? DisplayTransform.workingImage(fromWorkingSpace: encoded) {
            present = GPUPresentImage(
                width: encoded.width,
                height: encoded.height,
                cgImage: image
            )
        }
        persistDiskCache(encoded, processMode: mode)
        return RenderPrintResult(
            buffer: encoded,
            resolvedAutocrop: armed.resolved,
            cropRect: printConfig.cropRect,
            reusedBake: reusedBake,
            reusedAnalysis: reusedAnalysis,
            uploadedLinear: false,
            downloadedLinear: false,
            gpuPresent: present,
            previewPass: previewPass,
            analysisOversampled: oversampled
        )
    }

    /// Stored rect plus Crop Offset (preview-px, scaled to this buffer's long edge).
    private func applyStoredCrop(_ image: LinearRGBBuffer, rect: NormalizedCropRect, offsetPx: Int) -> LinearRGBBuffer {
        guard let roi = LinearRGBBuffer.storedCropPixelROI(
            width: image.width,
            height: image.height,
            rect: rect,
            offsetPx: offsetPx
        ) else {
            return image
        }
        let w = Double(image.width)
        let h = Double(image.height)
        return image.cropped(
            normalized: (
                Double(roi.x1) / w,
                Double(roi.y1) / h,
                Double(roi.x2) / w,
                Double(roi.y2) / h
            )
        )
    }

    public func writePrintF32(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin,
        to outURL: URL
    ) throws -> (width: Int, height: Int) {
        let buffer = try renderPrint(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: config
        )
        let data = buffer.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outURL, options: .atomic)
        return (buffer.width, buffer.height)
    }

    public func renderPNG(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        analysisBuffer: Float = LogNormalization.defaultAnalysisBuffer,
        config: PrintConfig = .s4aPin,
        to outURL: URL
    ) throws -> (width: Int, height: Int) {
        var printConfig = config
        printConfig.analysisBuffer = analysisBuffer
        let buffer = try renderPrint(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: printConfig
        )
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try ImageCoding.pngDataFromWorkingSpace(buffer)
        try ImageCoding.writeData(data, to: outURL)
        return (buffer.width, buffer.height)
    }

    /// S13m: ``target_px`` prints at ``export_target_long_edge_px`` (reuses preview linear / reprint
    /// cache when the edge is ≤ the settled preview). ``original`` stays full-res (RAW uses AHD).
    public func export(
        path: String,
        destDir: String,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s8Pin,
        settings: NativeExportSettings = NativeExportSettings()
    ) throws -> (url: URL, width: Int, height: Int, format: String) {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            PipelineStats.record(.export, milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let printLongEdge = settings.resolutionMode == .targetPx ? settings.targetLongEdgePx : nil
        var buffer = try renderPrint(
            path: path,
            longEdgePx: printLongEdge,
            processMode: processMode,
            config: config,
            previewPass: .settled
        )
        if settings.resolutionMode == .targetPx {
            buffer = buffer.sizedToLongEdge(settings.targetLongEdgePx)
        }
        let dest = try ExportNaming.outputURL(
            sourcePath: path,
            destDir: destDir,
            format: settings.format,
            overwrite: settings.overwrite
        )
        let data: Data
        switch settings.format {
        case .jpeg:
            data = try ImageCoding.jpegDataFromWorkingSpace(
                buffer,
                quality: Double(settings.jpegQuality) / 100
            )
        case .tiff:
            data = try ImageCoding.tiffDataFromWorkingSpace(
                buffer,
                bitsPerComponent: settings.tiffBitDepth
            )
        }
        try ImageCoding.writeData(data, to: dest)
        return (dest.resolvingSymlinksInPath(), buffer.width, buffer.height, settings.format.rawValue)
    }

    public func writeLinearF32(path: String, to outURL: URL) throws -> (width: Int, height: Int) {
        let buffer = try LinearDecode.decode(path: path)
        let data = buffer.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outURL, options: .atomic)
        return (buffer.width, buffer.height)
    }

    public func probeSource(at path: String) -> (width: Int, height: Int)? {
        if ScanFormat.isCameraRaw(path) {
            return RawDecode.probe(path: path)
        }
        return ImageCoding.probeDimensions(at: URL(fileURLWithPath: path))
    }

    /// RAW embedded JPEG for first paint. Nil for raster or when the file has no safe thumb.
    public func splashJPEG(path: String) -> SplashJPEG? {
        EmbeddedPreview.splashJPEG(path: path)
    }

    /// ImageIO / embedded-JPEG strip thumb. Not the H&D+Lab print path.
    public func cheapThumb(
        path: String,
        longEdgePx: Int,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s8Pin
    ) throws -> LinearRGBBuffer {
        try EmbeddedPreview.cheapThumb(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: config
        )
    }

    /// Synthetic linear vs encoded ramp PNGs. Not used by scan preview (S4a wires encode).
    public func writeOETFRampPNGs(to directory: URL, width: Int = 512, height: Int = 64) throws {
        let linear = WorkingOETF.linearRamp(width: width, height: height)
        let encoded = WorkingOETF.encode(linear)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ImageCoding.writePNG(linear, to: directory.appendingPathComponent("oetf-linear.png"))
        try ImageCoding.writePNG(encoded, to: directory.appendingPathComponent("oetf-encoded.png"))
    }
}
