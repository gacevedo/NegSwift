import Foundation

/// In-process pipeline. S10b: optical dust + heal on linear, then Lab / crop / OETF.
public struct NativePipeline: Sendable {
    public init() {}

    public func infoJSON() -> [String: Any] {
        [
            "protocol_version": EngineVersion.protocolVersion,
            "negswift_version": EngineVersion.packageVersion,
            "negpy_version": EngineVersion.oracleLabel,
            "python": "n/a",
            "gpu_available": false,
            "gpu_backend": NSNull(),
            "backend": EngineVersion.backendName,
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

    /// S10b print: optical dust + heal on decoded linear → orient → normalize → H&D + autos → Lab → crop → OETF.
    /// Matches NegPy `DarkroomEngine` order (dust/heals before geometry; Lab before pixel crop).
    /// Meters on the oriented full frame (`analysis_rect` / buffer), then crops pixels unless
    /// ``PrintConfig.applyPixelCrop`` is false (`crop_preview_full`). Preview-size decodes
    /// oversample so Analysis Buffer still sees film/holder edges.
    public func renderPrint(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin
    ) throws -> LinearRGBBuffer {
        var linear = try decodeForPrint(path: path, longEdgePx: longEdgePx)
        if config.dustRemove {
            linear = OpticalDust.bake(linear, threshold: config.dustThreshold, size: config.dustSize)
        }
        linear = HealInpaint.bake(linear, strokes: config.healStrokes, spots: config.dustSpots)
        linear = linear.oriented(
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            fineRotation: config.fineRotation
        )
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        var printed = PhotometricPrint.process(linear: linear, processMode: mode, config: config)
        printed = PhotoLab.process(printed, config: config)
        if config.applyPixelCrop, let crop = config.cropRect {
            printed = printed.cropped(normalized: crop.tuple)
        }
        return WorkingOETF.encode(printed)
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
