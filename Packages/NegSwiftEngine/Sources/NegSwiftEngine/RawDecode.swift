import Foundation
import NegSwiftLibRaw

/// LibRaw sensor-native linear RGB. Not ImageIO / Core Image (those apply a camera matrix).
///
/// Matches NegPy `output_color=raw`, `gamma=(1,1)`, unity white balance,
/// `adjust_maximum_thr=0`, `user_flip=0`, then bake LibRaw flip like EXIF orientation.
public enum RawDecode: Sendable {
    public static var isAvailable: Bool {
        negswift_raw_available() != 0
    }

    public static func probe(url: URL) -> (width: Int, height: Int)? {
        guard isAvailable else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        var orientation: Int32 = 1
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

    public static func decode(url: URL) throws -> LinearRGBBuffer {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LinearDecodeError.fileNotFound(url)
        }
        guard isAvailable else {
            throw LinearDecodeError.rawUnavailable
        }
        var raw = NegSwiftRawBuffer()
        var message = [CChar](repeating: 0, count: 256)
        let rc = url.path.withCString { path in
            message.withUnsafeMutableBufferPointer { err in
                negswift_raw_decode(path, &raw, err.baseAddress, err.count)
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
        return buffer.applyingExifOrientation(Int(raw.orientation))
    }

    public static func decode(path: String) throws -> LinearRGBBuffer {
        try decode(url: URL(fileURLWithPath: path))
    }
}
