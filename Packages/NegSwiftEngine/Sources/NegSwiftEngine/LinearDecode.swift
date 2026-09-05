import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum LinearDecodeError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case unsupported
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(url):
            "Scan not found: \(url.path)"
        case .unsupported:
            "Unsupported image format or pixel layout."
        case .decodeFailed:
            "ImageIO could not decode the scan."
        }
    }
}

/// ImageIO decode to scene-linear RGB.
///
/// Untagged 16-bit TIFF stays linear (`/ 65535`). Untagged 8-bit and JPEG apply IEC 61966-2-1
/// sRGB → linear. IR / ExtraSamples are dropped (S1).
public enum LinearDecode: Sendable {
    public static func decode(url: URL, maxLongEdge: Int? = nil) throws -> LinearRGBBuffer {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LinearDecodeError.fileNotFound(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LinearDecodeError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceShouldCache: true,
        ]
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let uti = CGImageSourceGetType(source) as String?
        let sourceDepth = sourceBitsPerComponent(properties: props)
        guard let image = try loadImage(source: source, options: options, maxLongEdge: maxLongEdge) else {
            throw LinearDecodeError.decodeFailed
        }
        // Transfer function follows the *file*, not the thumbnail. An 8-bit ImageIO
        // thumbnail of a 16-bit untagged TIFF must stay linear (`/ 255`), not sRGB.
        let transferDepth = sourceDepth ?? image.bitsPerComponent
        var buffer = try extractRGB(image)
        if shouldApplySRGBToLinear(uti: uti, bitsPerComponent: transferDepth, properties: props) {
            buffer = applySRGBToLinear(buffer)
        }
        if let maxLongEdge {
            buffer = buffer.downsampled(toLongEdge: maxLongEdge)
        }
        return buffer
    }

    public static func decode(path: String, maxLongEdge: Int? = nil) throws -> LinearRGBBuffer {
        try decode(url: URL(fileURLWithPath: path), maxLongEdge: maxLongEdge)
    }

    /// IEC 61966-2-1 sRGB electro-optical transfer (encoded → linear).
    public static func srgbToLinear(_ encoded: Float) -> Float {
        if encoded <= 0.04045 {
            return encoded / 12.92
        }
        return Foundation.pow((encoded + 0.055) / 1.055, 2.4)
    }

    static func shouldApplySRGBToLinear(
        uti: String?,
        bitsPerComponent: Int,
        properties: [CFString: Any]
    ) -> Bool {
        if let uti, uti == UTType.jpeg.identifier || uti == "public.jpeg" {
            return true
        }
        if isSRGBProfile(properties) {
            return true
        }
        return bitsPerComponent <= 8
    }

    /// ImageIO thumbnail when `maxLongEdge` is set so preview/detect do not extract 16 MP first.
    private static func loadImage(
        source: CGImageSource,
        options: [CFString: Any],
        maxLongEdge: Int?
    ) throws -> CGImage? {
        if let maxLongEdge, maxLongEdge > 0 {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
                kCGImageSourceShouldAllowFloat: true,
            ]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
                return thumb
            }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private static func sourceBitsPerComponent(properties: [CFString: Any]) -> Int? {
        if let depth = properties[kCGImagePropertyDepth] as? Int, depth > 0 {
            return depth
        }
        if let depth = properties[kCGImagePropertyDepth] as? NSNumber, depth.intValue > 0 {
            return depth.intValue
        }
        return nil
    }

    private static func isSRGBProfile(_ properties: [CFString: Any]) -> Bool {
        let name = (properties[kCGImagePropertyProfileName] as? String ?? "").lowercased()
        if name.contains("srgb") || name.contains("iec61966") {
            return true
        }
        return false
    }

    private static func applySRGBToLinear(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        LinearRGBBuffer(width: buffer.width, height: buffer.height, pixels: buffer.pixels.map(srgbToLinear))
    }

    private static func extractRGB(_ image: CGImage) throws -> LinearRGBBuffer {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let provider = image.dataProvider,
              let cfData = provider.data
        else {
            throw LinearDecodeError.decodeFailed
        }
        let bpc = image.bitsPerComponent
        let bpp = image.bitsPerPixel
        let bytesPerRow = image.bytesPerRow
        let alpha = CGImageAlphaInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        let byteOrder = CGBitmapInfo(rawValue: image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue)
        let little16 = byteOrder.contains(.byteOrder16Little)
        let big16 = byteOrder.contains(.byteOrder16Big)
        let bgra = byteOrder.contains(.byteOrder32Little) && (alpha == .noneSkipFirst || alpha == .premultipliedFirst || alpha == .first)

        let length = CFDataGetLength(cfData)
        return try CFDataGetBytePtr(cfData).withMemoryRebound(to: UInt8.self, capacity: length) { ptr in
            var pixels = [Float](repeating: 0, count: width * height * 3)
            if bpc == 16 {
                try extractUInt16(
                    ptr: ptr,
                    width: width,
                    height: height,
                    bytesPerRow: bytesPerRow,
                    bitsPerPixel: bpp,
                    littleEndian: little16 || !big16,
                    pixels: &pixels
                )
            } else if bpc == 8 {
                try extractUInt8(
                    ptr: ptr,
                    width: width,
                    height: height,
                    bytesPerRow: bytesPerRow,
                    bitsPerPixel: bpp,
                    bgra: bgra,
                    pixels: &pixels
                )
            } else {
                throw LinearDecodeError.unsupported
            }
            return LinearRGBBuffer(width: width, height: height, pixels: pixels)
        }
    }

    private static func extractUInt16(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bitsPerPixel: Int,
        littleEndian: Bool,
        pixels: inout [Float]
    ) throws {
        let channels = bitsPerPixel / 16
        guard channels >= 1 else { throw LinearDecodeError.unsupported }
        let scale: Float = 1.0 / 65535.0
        for y in 0..<height {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixel = row.advanced(by: x * channels * 2)
                let r: UInt16
                let g: UInt16
                let b: UInt16
                if channels == 1 {
                    let v = readU16(pixel, littleEndian: littleEndian)
                    r = v
                    g = v
                    b = v
                } else {
                    r = readU16(pixel, littleEndian: littleEndian)
                    g = readU16(pixel.advanced(by: 2), littleEndian: littleEndian)
                    b = readU16(pixel.advanced(by: 4), littleEndian: littleEndian)
                }
                let o = (y * width + x) * 3
                pixels[o] = Float(r) * scale
                pixels[o + 1] = Float(g) * scale
                pixels[o + 2] = Float(b) * scale
            }
        }
    }

    private static func extractUInt8(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bitsPerPixel: Int,
        bgra: Bool,
        pixels: inout [Float]
    ) throws {
        let channels = bitsPerPixel / 8
        guard channels >= 1 else { throw LinearDecodeError.unsupported }
        let scale: Float = 1.0 / 255.0
        for y in 0..<height {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixel = row.advanced(by: x * channels)
                let r: UInt8
                let g: UInt8
                let b: UInt8
                if channels == 1 {
                    r = pixel[0]
                    g = pixel[0]
                    b = pixel[0]
                } else if bgra, channels >= 4 {
                    b = pixel[0]
                    g = pixel[1]
                    r = pixel[2]
                } else {
                    r = pixel[0]
                    g = channels > 1 ? pixel[1] : pixel[0]
                    b = channels > 2 ? pixel[2] : pixel[0]
                }
                let o = (y * width + x) * 3
                pixels[o] = Float(r) * scale
                pixels[o + 1] = Float(g) * scale
                pixels[o + 2] = Float(b) * scale
            }
        }
    }

    private static func readU16(_ ptr: UnsafePointer<UInt8>, littleEndian: Bool) -> UInt16 {
        let raw = UnsafeRawPointer(ptr).load(as: UInt16.self)
        return littleEndian ? UInt16(littleEndian: raw) : UInt16(bigEndian: raw)
    }
}
