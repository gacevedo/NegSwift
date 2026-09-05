import Foundation

/// In-process pipeline. S0 is a stub (gray buffer). Decode, normalize, and print land in later verticals.
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

    /// S0: ignore pixels; emit a gray preview so the CLI and app can write a PNG.
    public func stubPreview(longEdgePx: Int?) -> LinearRGBBuffer {
        let edge = max(32, min(longEdgePx ?? 256, 512))
        return .stub(width: edge, height: edge)
    }

    public func renderPNG(path: String, longEdgePx: Int?, to outURL: URL) throws -> (width: Int, height: Int) {
        _ = path
        let buffer = stubPreview(longEdgePx: longEdgePx)
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ImageCoding.writePNG(buffer, to: outURL)
        return (buffer.width, buffer.height)
    }

    public func probeSource(at path: String) -> (width: Int, height: Int)? {
        ImageCoding.probeDimensions(at: URL(fileURLWithPath: path))
    }
}
