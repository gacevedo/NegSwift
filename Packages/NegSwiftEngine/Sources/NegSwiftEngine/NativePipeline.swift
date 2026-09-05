import Foundation

/// In-process pipeline. S4a: log-normalize → H&D print + cast + BPC → OETF.
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
        let linear = try LinearDecode.decode(path: path, maxLongEdge: longEdgePx)
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        return normalize(linear, processMode: mode, analysisBuffer: analysisBuffer)
    }

    /// S4a print: normalize → H&D + cast + BPC → working OETF.
    /// Autos follow ``PrintConfig``; ``s4aPin`` leaves them off.
    public func renderPrint(
        path: String,
        longEdgePx: Int?,
        processMode: FilmProcessMode? = nil,
        config: PrintConfig = .s4aPin
    ) throws -> LinearRGBBuffer {
        var linear = try LinearDecode.decode(path: path, maxLongEdge: longEdgePx)
        linear = linear.oriented(
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical
        )
        if let crop = config.cropRect {
            linear = linear.cropped(normalized: crop.tuple)
        }
        let mode = processMode ?? ProcessDetect.detectLite(linear)
        return PhotometricPrint.process(linear: linear, processMode: mode, config: config)
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
        try ImageCoding.writePNG(buffer, to: outURL)
        return (buffer.width, buffer.height)
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
