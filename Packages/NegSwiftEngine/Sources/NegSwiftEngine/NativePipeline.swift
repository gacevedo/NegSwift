import Foundation

/// In-process pipeline. S1: linear decode + process detect. Normalize / print are later.
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

    public func renderPNG(path: String, longEdgePx: Int?, to outURL: URL) throws -> (width: Int, height: Int) {
        let buffer = try LinearDecode.decode(path: path, maxLongEdge: longEdgePx)
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
}
