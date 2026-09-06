import Foundation

public struct RenderPrintResult: Sendable {
    public var buffer: LinearRGBBuffer
    /// Present only when this render ran border detection and produced a new rect.
    public var resolvedAutocrop: AutocropResolved?
    /// Crop after resolve (stored or newly detected). Used for `detected_crop_rect`.
    public var cropRect: NormalizedCropRect?

    public init(buffer: LinearRGBBuffer, resolvedAutocrop: AutocropResolved?, cropRect: NormalizedCropRect?) {
        self.buffer = buffer
        self.resolvedAutocrop = resolvedAutocrop
        self.cropRect = cropRect
    }
}

/// In-process pipeline. S12: optional Metal for used WGSL stages after CPU goldens.
public struct NativePipeline: Sendable {
    public var pixelBackend: PixelBackend

    public init(pixelBackend: PixelBackend = .cpu) {
        self.pixelBackend = pixelBackend
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
        ]
    }

    public func decode(path: String, maxLongEdge: Int? = nil) throws -> LinearRGBBuffer {
        try LinearDecode.decode(path: path, maxLongEdge: maxLongEdge)
    }

    /// Last canvas-size decode. Analysis Buffer drags reuse it so the 4096-px sample is not reloaded.
    private static let decodeLock = NSLock()
    nonisolated(unsafe) private static var lastPrintDecode: (key: String, buffer: LinearRGBBuffer)?

    private func decodeForPrint(path: String, longEdgePx: Int?) throws -> LinearRGBBuffer {
        let key = "\(path)|\(longEdgePx ?? 0)|\(Self.fileStamp(path))"
        Self.decodeLock.lock()
        if let last = Self.lastPrintDecode, last.key == key {
            let buffer = last.buffer
            Self.decodeLock.unlock()
            return buffer
        }
        Self.decodeLock.unlock()
        let buffer = try LinearDecode.decode(
            path: path,
            maxLongEdge: longEdgePx,
            analysisOversample: (longEdgePx ?? 0) >= 800
        )
        Self.decodeLock.lock()
        Self.lastPrintDecode = (key, buffer)
        Self.decodeLock.unlock()
        return buffer
    }

    private static func fileStamp(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? NSNumber ?? 0
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return "\(size.intValue)|\(modified.timeIntervalSince1970)"
    }

    public func detectProcessMode(path: String) throws -> FilmProcessMode {
        let buffer = try LinearDecode.decode(path: path, maxLongEdge: ProcessDetect.detectDecodeLongEdge)
        return ProcessDetect.detectLite(buffer)
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
        let linear = try decodeForPrint(path: path, longEdgePx: longEdgePx)
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        return normalize(linear, processMode: mode, analysisBuffer: analysisBuffer)
    }

    /// S12 print: optical dust + heal on decoded linear → detect-once autocrop → orient →
    /// normalize → H&D + autos → Lab → crop → OETF. Pixel stages may run on Metal.
    /// Matches NegPy `DarkroomEngine` order (dust/heals before geometry; Lab before pixel crop).
    /// Autocrop runs on the pre-geometry buffer and freezes `crop_rect` so preview and export
    /// share one rect. Meters on the oriented full frame, then crops pixels unless
    /// ``PrintConfig.applyPixelCrop`` is false (`crop_preview_full`).
    public func renderPrint(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin
    ) throws -> LinearRGBBuffer {
        try renderPrintDetailed(
            path: path,
            longEdgePx: longEdgePx,
            processMode: processMode,
            config: config
        ).buffer
    }

    public func renderPrintDetailed(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin
    ) throws -> RenderPrintResult {
        var linear = try decodeForPrint(path: path, longEdgePx: longEdgePx)
        if config.dustRemove {
            linear = OpticalDust.bake(linear, threshold: config.dustThreshold, size: config.dustSize)
        }
        linear = HealInpaint.bake(linear, strokes: config.healStrokes, spots: config.dustSpots)
        let armed = Autocrop.resolveArmed(linear, config: config)
        let printConfig = armed.config
        linear = linear.oriented(
            rotation: printConfig.rotation,
            flipHorizontal: printConfig.flipHorizontal,
            flipVertical: printConfig.flipVertical,
            fineRotation: printConfig.fineRotation
        )
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        if pixelBackend.resolved() == .metal,
           let gpu = MetalPrint.process(linear: linear, processMode: mode, config: printConfig)
        {
            var printed = gpu
            if printConfig.applyPixelCrop, let crop = printConfig.cropRect {
                printed = applyStoredCrop(printed, rect: crop, offsetPx: printConfig.autocropOffset)
            }
            return RenderPrintResult(
                buffer: printed,
                resolvedAutocrop: armed.resolved,
                cropRect: printConfig.cropRect
            )
        }
        var printed = PhotometricPrint.process(linear: linear, processMode: mode, config: printConfig)
        printed = PhotoLab.process(printed, config: printConfig)
        if printConfig.applyPixelCrop, let crop = printConfig.cropRect {
            printed = applyStoredCrop(printed, rect: crop, offsetPx: printConfig.autocropOffset)
        }
        return RenderPrintResult(
            buffer: WorkingOETF.encode(printed),
            resolvedAutocrop: armed.resolved,
            cropRect: printConfig.cropRect
        )
    }

    /// Stored rect plus Crop Offset (preview-px, scaled to this buffer's long edge).
    private func applyStoredCrop(_ image: LinearRGBBuffer, rect: NormalizedCropRect, offsetPx: Int) -> LinearRGBBuffer {
        if offsetPx <= 0 {
            return image.cropped(normalized: rect.tuple)
        }
        let scale = Double(max(image.width, image.height)) / Autocrop.previewRenderSize
        guard let roi = LinearRGBBuffer.storedCropPixelROI(
            width: image.width,
            height: image.height,
            rect: rect.tuple
        ) else {
            return image
        }
        let inset = Autocrop.applyMargin(
            PixelROI(y1: roi.y1, y2: roi.y2, x1: roi.x1, x2: roi.x2),
            height: image.height,
            width: image.width,
            margin: Double(offsetPx) * scale
        )
        if inset.isEmpty { return image.cropped(normalized: rect.tuple) }
        let w = Double(image.width)
        let h = Double(image.height)
        return image.cropped(
            normalized: (
                Double(inset.x1) / w,
                Double(inset.y1) / h,
                Double(inset.x2) / w,
                Double(inset.y2) / h
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

    /// Full-res sRGB JPEG/TIFF. Same print config as preview; no long-edge downsample.
    public func export(
        path: String,
        destDir: String,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s8Pin,
        settings: NativeExportSettings = NativeExportSettings()
    ) throws -> (url: URL, width: Int, height: Int, format: String) {
        let buffer = try renderPrint(
            path: path,
            longEdgePx: nil,
            processMode: processMode,
            config: config
        )
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
        ImageCoding.probeDimensions(at: URL(fileURLWithPath: path))
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
