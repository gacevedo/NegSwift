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
/// Matches NegPy `embedded_preview` / `get_thumbnail_worker`: JPEG thumbs from LibRaw,
/// TIFF preview page when the thumb is BITMAP, ImageIO thumbnail for raster. Cheap
/// invert (`preview_positive`) makes C-41 strip cells read as photographs.
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

    /// Display-referred sRGB 0…1, already inverted when the frame is a negative.
    public static func cheapThumb(
        path: String,
        longEdgePx: Int,
        processMode: FilmProcessMode?
    ) throws -> LinearRGBBuffer {
        let edge = max(1, longEdgePx)
        guard let image = sourcePreview(path: path, maxLongEdge: edge) else {
            throw LinearDecodeError.decodeFailed
        }
        var buffer = try ImageCoding.buffer(from: image)
        if max(buffer.width, buffer.height) > edge {
            buffer = buffer.areaDownsampled(toLongEdge: edge)
        }
        return previewPositive(buffer, processMode: processMode)
    }

    // MARK: - Source preview

    private static func sourcePreview(path: String, maxLongEdge: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        if ScanFormat.isCameraRaw(path) {
            if let jpeg = rawJPEGThumb(path: path),
               let image = ImageCoding.cgImage(fromJPEG: jpeg)
            {
                return constrain(image, maxLongEdge: maxLongEdge)
            }
            if let embedded = imageIOThumbnail(url: url, maxLongEdge: maxLongEdge, embeddedOnly: true) {
                return embedded
            }
            return rawHalfSizePreview(path: path, maxLongEdge: maxLongEdge)
        }
        return imageIOThumbnail(url: url, maxLongEdge: maxLongEdge, embeddedOnly: false)
    }

    private static func rawJPEGThumb(path: String) -> Data? {
        guard let thumb = RawDecode.extractThumb(path: path), thumb.format == .jpeg else {
            return nil
        }
        return thumb.jpeg
    }

    /// Python `_fast_demosaic` fallback when the RAW has no safe embedded preview.
    private static func rawHalfSizePreview(path: String, maxLongEdge: Int) -> CGImage? {
        guard let buffer = try? LinearBufferCache.shared.buffer(
            path: path,
            maxLongEdge: maxLongEdge,
            analysisOversample: false
        ) else {
            return nil
        }
        return ImageCoding.sRGBDisplayImage(from: buffer)
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

    // MARK: - Cheap invert (NegPy `preview_positive`)

    /// Per-channel log-density stretch. Not the H&D print path.
    static func previewPositive(
        _ encodedSRGB: LinearRGBBuffer,
        processMode: FilmProcessMode?
    ) -> LinearRGBBuffer {
        let linear = AccelerateConvert.applySRGBToLinear(encodedSRGB)
        let mode = processMode ?? ProcessDetect.detect(linear)
        if mode == .transparency {
            return encodedSRGB
        }
        let count = linear.width * linear.height
        var density = [Float](repeating: 0, count: count * 3)
        for i in 0..<(count * 3) {
            density[i] = -log10(max(linear.pixels[i], 1e-4))
        }
        var lo: (Float, Float, Float) = (0, 0, 0)
        var hi: (Float, Float, Float) = (1, 1, 1)
        for channel in 0..<3 {
            var samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                samples[i] = density[i * 3 + channel]
            }
            samples.sort()
            let low = percentile(samples, 1)
            let high = percentile(samples, 99)
            switch channel {
            case 0: lo.0 = low; hi.0 = high
            case 1: lo.1 = low; hi.1 = high
            default: lo.2 = low; hi.2 = high
            }
        }
        var out = [Float](repeating: 0, count: count * 3)
        for i in 0..<count {
            out[i * 3] = stretch(density[i * 3], lo: lo.0, hi: hi.0)
            out[i * 3 + 1] = stretch(density[i * 3 + 1], lo: lo.1, hi: hi.1)
            out[i * 3 + 2] = stretch(density[i * 3 + 2], lo: lo.2, hi: hi.2)
        }
        return LinearRGBBuffer(width: linear.width, height: linear.height, pixels: out)
    }

    private static func stretch(_ value: Float, lo: Float, hi: Float) -> Float {
        let span = max(hi - lo, 1e-6)
        return min(1, max(0, (value - lo) / span))
    }

    private static func percentile(_ sorted: [Float], _ percent: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let t = min(1, max(0, percent / 100)) * Float(sorted.count - 1)
        let i = Int(t)
        if i >= sorted.count - 1 { return sorted[sorted.count - 1] }
        let f = t - Float(i)
        return sorted[i] * (1 - f) + sorted[i + 1] * f
    }
}
