import Foundation
import NegSwiftLibRaw

/// LibRaw sensor-native linear RGB. Not ImageIO / Core Image (those apply a camera matrix).
///
/// Matches NegPy `output_color=raw`, `gamma=(1,1)`, unity white balance,
/// `adjust_maximum_thr=0`, `user_flip=0`, then bake LibRaw flip like EXIF orientation.
/// Preview/thumb decodes request ``halfSize`` (Bayer 2×2 + LINEAR). Export stays full-size AHD.
public enum RawDecode: Sendable {
    public struct Result: Sendable {
        public var buffer: LinearRGBBuffer
        public var usedHalfSize: Bool
    }
    /// LibRaw's dcraw path uses OpenMP. Concurrent unpack/process deadlocks.
    private static let librawLock = NSLock()

    public static var isAvailable: Bool {
        negswift_raw_available() != 0
    }

    public static func probe(url: URL) -> (width: Int, height: Int)? {
        guard isAvailable else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        var orientation: Int32 = 1
        librawLock.lock()
        defer { librawLock.unlock() }
        let rc = url.path.withCString { path in
            negswift_raw_probe(path, &width, &height, &orientation)
        }
        guard rc == 0, width > 0, height > 0 else { return nil }
        if ScanFormat.orientationSwapsDimensions(Int(orientation)) {
            return (Int(height), Int(width))
        }
        return (Int(width), Int(height))
    }

    public static func probe(path: String) -> (width: Int, height: Int)? {
        probe(url: URL(fileURLWithPath: path))
    }

    public static func decode(url: URL, halfSize: Bool = false) throws -> LinearRGBBuffer {
        try decodeDetailed(url: url, halfSize: halfSize).buffer
    }

    public static func decodeDetailed(url: URL, halfSize: Bool = false) throws -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LinearDecodeError.fileNotFound(url)
        }
        guard isAvailable else {
            throw LinearDecodeError.rawUnavailable
        }
        librawLock.lock()
        defer { librawLock.unlock() }
        var raw = NegSwiftRawBuffer()
        var message = [CChar](repeating: 0, count: 256)
        let rc = url.path.withCString { path in
            message.withUnsafeMutableBufferPointer { err in
                negswift_raw_decode(path, halfSize ? 1 : 0, &raw, err.baseAddress, err.count)
            }
        }
        defer { negswift_raw_free(&raw) }
        if rc != 0 {
            let text = message.withUnsafeBufferPointer { buf in
                String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            throw LinearDecodeError.rawDecodeFailed(
                text.isEmpty ? "LibRaw could not decode the camera RAW." : text
            )
        }
        guard raw.width > 0, raw.height > 0, let pointer = raw.pixels else {
            throw LinearDecodeError.rawDecodeFailed("LibRaw returned an empty buffer.")
        }
        let pixels = Array(UnsafeBufferPointer(start: pointer, count: Int(raw.count)))
        let buffer = LinearRGBBuffer(width: Int(raw.width), height: Int(raw.height), pixels: pixels)
        return Result(
            buffer: buffer.applyingExifOrientation(Int(raw.orientation)),
            usedHalfSize: raw.used_half_size != 0
        )
    }

    public static func decode(path: String, halfSize: Bool = false) throws -> LinearRGBBuffer {
        try decode(url: URL(fileURLWithPath: path), halfSize: halfSize)
    }

    /// LibRaw embedded preview. JPEG bytes only — BITMAP is reported without pixel data.
    public struct Thumb: Sendable {
        public var format: Format
        public var jpeg: Data?
        public var width: Int
        public var height: Int
        public var orientation: Int

        public enum Format: Sendable {
            case jpeg
            case bitmap
        }
    }

    public static func extractThumb(url: URL) -> Thumb? {
        guard isAvailable else { return nil }
        librawLock.lock()
        defer { librawLock.unlock() }
        var raw = NegSwiftRawThumb()
        var message = [CChar](repeating: 0, count: 256)
        let rc = url.path.withCString { path in
            message.withUnsafeMutableBufferPointer { err in
                negswift_raw_extract_thumb(path, &raw, err.baseAddress, err.count)
            }
        }
        defer { negswift_raw_free_thumb(&raw) }
        guard rc == 0 else { return nil }
        if raw.format == 1, let pointer = raw.data, raw.size > 0 {
            return Thumb(
                format: .jpeg,
                jpeg: Data(bytes: pointer, count: Int(raw.size)),
                width: Int(raw.width),
                height: Int(raw.height),
                orientation: Int(raw.orientation)
            )
        }
        if raw.format == 2 {
            return Thumb(
                format: .bitmap,
                jpeg: nil,
                width: Int(raw.width),
                height: Int(raw.height),
                orientation: Int(raw.orientation)
            )
        }
        return nil
    }

    public static func extractThumb(path: String) -> Thumb? {
        extractThumb(url: URL(fileURLWithPath: path))
    }
}
