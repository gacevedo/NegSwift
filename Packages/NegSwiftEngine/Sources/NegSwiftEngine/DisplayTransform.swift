import CoreGraphics
import Foundation

public enum DisplayTransformError: Error, LocalizedError, Sendable {
    case colorSpaceUnavailable
    case convertFailed

    public var errorDescription: String? {
        switch self {
        case .colorSpaceUnavailable:
            "Adobe RGB 1998 / sRGB color spaces are unavailable."
        case .convertFailed:
            "ColorSync could not convert working-space pixels to sRGB."
        }
    }
}

/// Preview / export display transform: Adobe RGB 1998 working numbers → sRGB.
///
/// Matches NegPy `apply_display_transform(..., dst_bytes=None)` (working space → sRGB)
/// and export `apply_color_management` (relative colorimetric). Working-space buffers
/// are already OETF-encoded; this is a ColorSync hop, not another OETF.
public enum DisplayTransform: Sendable {
    /// Adobe RGB 1998 encoded `[0, 1]` → sRGB encoded `[0, 1]`.
    public static func workingToSRGB(
        _ buffer: LinearRGBBuffer,
        bitsPerComponent: Int = 8
    ) throws -> LinearRGBBuffer {
        let image = try sRGBImage(fromWorkingSpace: buffer, bitsPerComponent: bitsPerComponent)
        return try ImageCoding.buffer(from: image)
    }

    /// Adobe RGB 1998 encoded buffer as an sRGB-tagged `CGImage` (ICC follows the space).
    public static func sRGBImage(
        fromWorkingSpace buffer: LinearRGBBuffer,
        bitsPerComponent: Int = 8
    ) throws -> CGImage {
        guard let adobe = CGColorSpace(name: CGColorSpace.adobeRGB1998),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            throw DisplayTransformError.colorSpaceUnavailable
        }
        let depth = bitsPerComponent >= 16 ? 16 : 8
        guard let source = ImageCoding.cgImage(
            from: buffer,
            colorSpace: adobe,
            bitsPerComponent: depth
        ) else {
            throw DisplayTransformError.convertFailed
        }
        return try convert(source, to: srgb, bitsPerComponent: depth)
    }

    private static func convert(
        _ image: CGImage,
        to colorSpace: CGColorSpace,
        bitsPerComponent: Int
    ) throws -> CGImage {
        var bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        if bitsPerComponent >= 16 {
            bitmapInfo |= CGBitmapInfo.byteOrder16Little.rawValue
        }
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw DisplayTransformError.convertFailed
        }
        ctx.interpolationQuality = .none
        ctx.setRenderingIntent(.relativeColorimetric)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = ctx.makeImage() else {
            throw DisplayTransformError.convertFailed
        }
        return out
    }
}
