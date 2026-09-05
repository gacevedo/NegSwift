import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodingError: Error, LocalizedError, Sendable {
    case encodeFailed
    case invalidBuffer
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Could not encode image data."
        case .invalidBuffer:
            "Linear RGB buffer is empty or inconsistent."
        case let .writeFailed(url):
            "Could not write image to \(url.path)."
        }
    }
}

/// ImageIO encode/probe helpers. Working-space math stays explicit; this is I/O only.
public enum ImageCoding: Sendable {
    public static func probeDimensions(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            return nil
        }
        return (width, height)
    }

    public static func pngData(from buffer: LinearRGBBuffer) throws -> Data {
        try encode(buffer, type: UTType.png.identifier as CFString, quality: nil)
    }

    public static func jpegData(from buffer: LinearRGBBuffer, quality: Double = 0.9) throws -> Data {
        try encode(buffer, type: UTType.jpeg.identifier as CFString, quality: quality)
    }

    public static func writePNG(_ buffer: LinearRGBBuffer, to url: URL) throws {
        let data = try pngData(from: buffer)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodingError.writeFailed(url)
        }
    }

    private static func encode(_ buffer: LinearRGBBuffer, type: CFString, quality: Double?) throws -> Data {
        guard buffer.width > 0, buffer.height > 0, !buffer.pixels.isEmpty else {
            throw ImageCodingError.invalidBuffer
        }
        guard let image = cgImage(from: buffer) else {
            throw ImageCodingError.encodeFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw ImageCodingError.encodeFailed
        }
        var options: [CFString: Any] = [:]
        if let quality {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCodingError.encodeFailed
        }
        return data as Data
    }

    private static func cgImage(from buffer: LinearRGBBuffer) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = buffer.width * bytesPerPixel
        var rgba = [UInt8](repeating: 255, count: buffer.width * buffer.height * bytesPerPixel)
        for i in 0..<(buffer.width * buffer.height) {
            let r = buffer.pixels[i * 3]
            let g = buffer.pixels[i * 3 + 1]
            let b = buffer.pixels[i * 3 + 2]
            rgba[i * 4] = Self.quantize(r)
            rgba[i * 4 + 1] = Self.quantize(g)
            rgba[i * 4 + 2] = Self.quantize(b)
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func quantize(_ sample: Float) -> UInt8 {
        let clamped = min(1, max(0, sample))
        return UInt8((clamped * 255).rounded())
    }
}
