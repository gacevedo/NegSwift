import CoreGraphics
import Foundation
import ImageIO

/// Embedded-preview splash JPEG. Display-referred sRGB; not the linear look path.
public struct SplashJPEG: Sendable, Equatable {
    public var jpeg: Data
    public var width: Int
    public var height: Int
}

/// S13f: camera embedded JPEG splash and cheap strip thumbs (not H&D+Lab).
///
/// JPEG thumbs from LibRaw, TIFF preview page when the thumb is BITMAP, ImageIO
/// thumbnail for raster. Geometry + log-normalize on that 256 px buffer so the
/// strip is readable (crop, orientation, not a cyan invert) without a print.
public enum EmbeddedPreview: Sendable {
    public static let splashLongEdge = Int(Autocrop.previewRenderSize)
    public static let splashJPEGQuality = 0.85

    public static func splashJPEG(path: String) -> SplashJPEG? {
        guard ScanFormat.isCameraRaw(path) else { return nil }
        if let jpeg = rawJPEGThumb(path: path) {
            return constrainedJPEG(jpeg)
        }
        guard let image = imageIOThumbnail(
            url: URL(fileURLWithPath: path),
            maxLongEdge: splashLongEdge,
            embeddedOnly: true
        ) else {
            return nil
        }
        return jpegPayload(from: image)
    }

    /// 256 px thumb: geometry + log-normalize + invert. Not H&D / Lab / dust.
    public static func cheapThumb(
        path: String,
        longEdgePx: Int,
        processMode: FilmProcessMode?,
        config: PrintConfig = .s8Pin
    ) throws -> LinearRGBBuffer {
        let edge = max(1, longEdgePx)
        var linear = try sourceLinear(path: path, maxLongEdge: edge)
        if max(linear.width, linear.height) > edge {
            linear = linear.areaDownsampled(toLongEdge: edge)
        }
        let crop = config.cropRect ?? Autocrop.resolveRect(
            linear,
            config: config,
            previewSize: Double(max(linear.width, linear.height))
        )
        linear = linear.oriented(
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            fineRotation: config.fineRotation
        )
        if let crop {
            linear = linear.cropped(normalized: crop.tuple)
        }
        let mode = processMode ?? ProcessDetect.detect(linear)
        // S2 log-normalize is kept-polarity (neutralizes the mask, does not invert).
        // The strip needs a photograph, so invert after that — not the old per-channel
        // `preview_positive` stretch that went cyan.
        let normalized = LogNormalization.process(linear: linear, processMode: mode)
        if mode == .transparency {
            return normalized
        }
        return invertNormalized(normalized)
    }

    // MARK: - Source preview

    private static func sourceLinear(path: String, maxLongEdge: Int) throws -> LinearRGBBuffer {
        let url = URL(fileURLWithPath: path)
        if ScanFormat.isCameraRaw(path) {
            if let thumb = RawDecode.extractThumb(path: path),
               thumb.format == .jpeg,
               let jpeg = thumb.jpeg,
               let image = ImageCoding.cgImage(fromJPEG: jpeg)
            {
                let scaled = constrain(image, maxLongEdge: maxLongEdge) ?? image
                var buffer = AccelerateConvert.applySRGBToLinear(try ImageCoding.buffer(from: scaled))
                if thumb.orientation > 1, ImageCoding.jpegOrientation(jpeg) <= 1 {
                    buffer = buffer.applyingExifOrientation(thumb.orientation)
                }
                return buffer
            }
            if let embedded = imageIOThumbnail(url: url, maxLongEdge: maxLongEdge, embeddedOnly: true) {
                return AccelerateConvert.applySRGBToLinear(try ImageCoding.buffer(from: embedded))
            }
            return try LinearBufferCache.shared.buffer(
                path: path,
                maxLongEdge: maxLongEdge,
                analysisOversample: false
            )
        }
        guard let image = imageIOThumbnail(url: url, maxLongEdge: maxLongEdge, embeddedOnly: false) else {
            throw LinearDecodeError.decodeFailed
        }
        let buffer = try ImageCoding.buffer(from: image)
        if ScanFormat.pathExtension(of: path) == "jpg" || ScanFormat.pathExtension(of: path) == "jpeg" {
            return AccelerateConvert.applySRGBToLinear(buffer)
        }
        return buffer
    }

    private static func rawJPEGThumb(path: String) -> Data? {
        guard let thumb = RawDecode.extractThumb(path: path), thumb.format == .jpeg else {
            return nil
        }
        return thumb.jpeg
    }

    static func imageIOThumbnail(url: URL, maxLongEdge: Int, embeddedOnly: Bool) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCache: false,
        ]
        if maxLongEdge > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxLongEdge
        }
        if embeddedOnly {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = false
            options[kCGImageSourceCreateThumbnailFromImageAlways] = false
        } else {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        }
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return constrain(thumb, maxLongEdge: maxLongEdge)
        }
        if embeddedOnly { return nil }
        guard let full = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return constrain(full, maxLongEdge: maxLongEdge)
    }

    // MARK: - Splash encode

    private static func constrainedJPEG(_ jpeg: Data) -> SplashJPEG? {
        guard let dims = ImageCoding.jpegDimensions(jpeg) else { return nil }
        if max(dims.width, dims.height) <= splashLongEdge {
            return SplashJPEG(jpeg: jpeg, width: dims.width, height: dims.height)
        }
        guard let image = ImageCoding.cgImage(fromJPEG: jpeg),
              let scaled = constrain(image, maxLongEdge: splashLongEdge)
        else {
            return SplashJPEG(jpeg: jpeg, width: dims.width, height: dims.height)
        }
        return jpegPayload(from: scaled)
    }

    private static func jpegPayload(from image: CGImage) -> SplashJPEG? {
        let scaled = constrain(image, maxLongEdge: splashLongEdge) ?? image
        guard let buffer = try? ImageCoding.buffer(from: scaled),
              let data = try? ImageCoding.jpegData(from: buffer, quality: splashJPEGQuality)
        else {
            return nil
        }
        return SplashJPEG(jpeg: data, width: scaled.width, height: scaled.height)
    }

    private static func constrain(_ image: CGImage, maxLongEdge: Int) -> CGImage? {
        guard maxLongEdge > 0 else { return image }
        let longest = max(image.width, image.height)
        guard longest > maxLongEdge else { return image }
        let scale = Double(maxLongEdge) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func invertNormalized(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        var pixels = buffer.pixels
        for i in pixels.indices {
            pixels[i] = min(1, max(0, 1 - pixels[i]))
        }
        return LinearRGBBuffer(width: buffer.width, height: buffer.height, pixels: pixels)
    }

}
