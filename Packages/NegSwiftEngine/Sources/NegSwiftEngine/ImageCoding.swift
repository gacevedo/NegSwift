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

    public static func profileName(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }
        return props[kCGImagePropertyProfileName] as? String
    }

    public static func pngData(from buffer: LinearRGBBuffer) throws -> Data {
        try encode(buffer, type: UTType.png.identifier as CFString, quality: nil)
    }

    public static func jpegData(from buffer: LinearRGBBuffer, quality: Double = 0.9) throws -> Data {
        try encode(buffer, type: UTType.jpeg.identifier as CFString, quality: quality)
    }

    public static func jpegDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            return nil
        }
        return (width, height)
    }

    public static func cgImage(fromJPEG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Display-referred sRGB buffer as a tagged `CGImage` (no working-space hop).
    public static func sRGBDisplayImage(from buffer: LinearRGBBuffer) -> CGImage? {
        cgImage(from: buffer)
    }

    public static func tiffData(from buffer: LinearRGBBuffer, bitsPerComponent: Int = 8) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = cgImage(from: buffer, colorSpace: space, bitsPerComponent: bitsPerComponent)
        else {
            throw ImageCodingError.encodeFailed
        }
        return try encode(image, type: UTType.tiff.identifier as CFString, quality: nil)
    }

    /// Preview JPEG: working-space OETF buffer → sRGB → JPEG.
    public static func jpegDataFromWorkingSpace(
        _ buffer: LinearRGBBuffer,
        quality: Double = 0.9
    ) throws -> Data {
        let image = try DisplayTransform.sRGBImage(fromWorkingSpace: buffer, bitsPerComponent: 8)
        return try encode(image, type: UTType.jpeg.identifier as CFString, quality: quality)
    }

    /// Preview PNG: working-space OETF buffer → sRGB → PNG.
    public static func pngDataFromWorkingSpace(_ buffer: LinearRGBBuffer) throws -> Data {
        let image = try DisplayTransform.sRGBImage(fromWorkingSpace: buffer, bitsPerComponent: 8)
        return try encode(image, type: UTType.png.identifier as CFString, quality: nil)
    }

    /// Export TIFF: working-space OETF buffer → sRGB (8 or 16-bit).
    public static func tiffDataFromWorkingSpace(
        _ buffer: LinearRGBBuffer,
        bitsPerComponent: Int = 16
    ) throws -> Data {
        let depth = bitsPerComponent >= 16 ? 16 : 8
        let image = try DisplayTransform.sRGBImage(fromWorkingSpace: buffer, bitsPerComponent: depth)
        return try encode(image, type: UTType.tiff.identifier as CFString, quality: nil)
    }

    public static func writePNG(_ buffer: LinearRGBBuffer, to url: URL) throws {
        let data = try pngData(from: buffer)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodingError.writeFailed(url)
        }
    }

    public static func writeData(_ data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodingError.writeFailed(url)
        }
    }

    private static func encode(_ buffer: LinearRGBBuffer, type: CFString, quality: Double?) throws -> Data {
        guard let image = cgImage(from: buffer) else {
            throw ImageCodingError.encodeFailed
        }
        return try encode(image, type: type, quality: quality)
    }

    static func encode(_ image: CGImage, type: CFString, quality: Double?) throws -> Data {
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

    static func cgImage(from buffer: LinearRGBBuffer) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return cgImage(from: buffer, colorSpace: space, bitsPerComponent: 8)
    }

    static func cgImage(
        from buffer: LinearRGBBuffer,
        colorSpace: CGColorSpace,
        bitsPerComponent: Int
    ) -> CGImage? {
        guard buffer.width > 0, buffer.height > 0, !buffer.pixels.isEmpty else {
            return nil
        }
        if bitsPerComponent >= 16 {
            return cgImage16(from: buffer, colorSpace: colorSpace)
        }
        return cgImage8(from: buffer, colorSpace: colorSpace)
    }

    static func buffer(from image: CGImage) throws -> LinearRGBBuffer {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw ImageCodingError.invalidBuffer
        }
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &rgba,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            throw ImageCodingError.encodeFailed
        }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            pixels[i * 3] = Float(rgba[i * 4]) / 255
            pixels[i * 3 + 1] = Float(rgba[i * 4 + 1]) / 255
            pixels[i * 3 + 2] = Float(rgba[i * 4 + 2]) / 255
        }
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    @_optimize(speed)
    private static func cgImage8(from buffer: LinearRGBBuffer, colorSpace: CGColorSpace) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = buffer.width * bytesPerPixel
        var rgba = [UInt8](repeating: 255, count: buffer.width * buffer.height * bytesPerPixel)
        for i in 0..<(buffer.width * buffer.height) {
            let r = buffer.pixels[i * 3]
            let g = buffer.pixels[i * 3 + 1]
            let b = buffer.pixels[i * 3 + 2]
            rgba[i * 4] = quantize8(r)
            rgba[i * 4 + 1] = quantize8(g)
            rgba[i * 4 + 2] = quantize8(b)
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else {
            return nil
        }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .relativeColorimetric
        )
    }

    @_optimize(speed)
    private static func cgImage16(from buffer: LinearRGBBuffer, colorSpace: CGColorSpace) -> CGImage? {
        let bytesPerPixel = 8
        let bytesPerRow = buffer.width * bytesPerPixel
        var rgba = [UInt16](repeating: 65_535, count: buffer.width * buffer.height * 4)
        for i in 0..<(buffer.width * buffer.height) {
            rgba[i * 4] = quantize16(buffer.pixels[i * 3])
            rgba[i * 4 + 1] = quantize16(buffer.pixels[i * 3 + 1])
            rgba[i * 4 + 2] = quantize16(buffer.pixels[i * 3 + 2])
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .relativeColorimetric
        )
    }

    @_optimize(speed)
    private static func quantize8(_ sample: Float) -> UInt8 {
        let clamped = min(1, max(0, sample))
        return UInt8((clamped * 255).rounded())
    }

    @_optimize(speed)
    private static func quantize16(_ sample: Float) -> UInt16 {
        let clamped = min(1, max(0, sample))
        return UInt16((clamped * 65_535).rounded())
    }
}
