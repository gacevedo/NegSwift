import Accelerate
import Foundation

/// S13e: vImage / vDSP for extract, sRGB→linear, INTER_AREA resize, and RGB↔RGBA.
enum AccelerateConvert: Sendable {
    private static let srgbBoundary: Float = 0.04045
    private static let srgbGamma: Float = 2.4
    private static let srgbLinear: [Float] = [1 / 12.92, 0]
    private static let srgbExponential: [Float] = [1 / 1.055, 0.055 / 1.055, 0]

    // MARK: - ImageIO extract

    static func extractRGB(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bitsPerComponent: Int,
        bitsPerPixel: Int,
        littleEndian16: Bool,
        bgra: Bool
    ) throws -> LinearRGBBuffer {
        if bitsPerComponent == 16 {
            let channels = bitsPerPixel / 16
            guard channels >= 1 else { throw LinearDecodeError.unsupported }
            if littleEndian16,
               let pixels = uint16ToFloat(
                   ptr: ptr,
                   width: width,
                   height: height,
                   bytesPerRow: bytesPerRow,
                   channels: channels
               )
            {
                return LinearRGBBuffer(width: width, height: height, pixels: pixels)
            }
            return try extractUInt16Scalar(
                ptr: ptr,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                channels: channels,
                littleEndian: littleEndian16
            )
        }
        if bitsPerComponent == 8 {
            let channels = bitsPerPixel / 8
            guard channels >= 1 else { throw LinearDecodeError.unsupported }
            if let pixels = uint8ToFloat(
                ptr: ptr,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                channels: channels,
                bgra: bgra
            ) {
                return LinearRGBBuffer(width: width, height: height, pixels: pixels)
            }
            return try extractUInt8Scalar(
                ptr: ptr,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                channels: channels,
                bgra: bgra
            )
        }
        throw LinearDecodeError.unsupported
    }

    static func applySRGBToLinear(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        var pixels = buffer.pixels
        let ok = pixels.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return false }
            var buf = vImage_Buffer(
                data: base,
                height: vImagePixelCount(buffer.height),
                width: vImagePixelCount(buffer.width * 3),
                rowBytes: buffer.width * 3 * MemoryLayout<Float>.stride
            )
            return vImagePiecewiseGamma_PlanarF(
                &buf,
                &buf,
                srgbExponential,
                srgbGamma,
                srgbLinear,
                srgbBoundary,
                vImage_Flags(kvImageNoFlags)
            ) == kvImageNoError
        }
        if ok {
            return LinearRGBBuffer(width: buffer.width, height: buffer.height, pixels: pixels)
        }
        return LinearRGBBuffer(
            width: buffer.width,
            height: buffer.height,
            pixels: buffer.pixels.map(LinearDecode.srgbToLinear)
        )
    }

    // MARK: - Metal swizzle

    static func rgbToRGBA(_ rgb: [Float], width: Int, height: Int) -> [Float] {
        var src = rgb
        var dest = [Float](repeating: 1, count: width * height * 4)
        let err = src.withUnsafeMutableBufferPointer { srcPtr in
            dest.withUnsafeMutableBufferPointer { dstPtr in
                guard let s = srcPtr.baseAddress, let d = dstPtr.baseAddress else {
                    return kvImageNullPointerArgument
                }
                var rgbBuf = vImage_Buffer(
                    data: s,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 3 * MemoryLayout<Float>.stride
                )
                var rgbaBuf = vImage_Buffer(
                    data: d,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4 * MemoryLayout<Float>.stride
                )
                return vImageConvert_RGBFFFtoRGBAFFFF(
                    &rgbBuf,
                    nil,
                    1,
                    &rgbaBuf,
                    false,
                    vImage_Flags(kvImageNoFlags)
                )
            }
        }
        if err == kvImageNoError {
            return dest
        }
        let n = width * height
        for i in 0..<n {
            dest[i * 4] = rgb[i * 3]
            dest[i * 4 + 1] = rgb[i * 3 + 1]
            dest[i * 4 + 2] = rgb[i * 3 + 2]
        }
        return dest
    }

    static func rgbaToRGB(_ rgba: [Float], width: Int, height: Int) -> [Float] {
        var src = rgba
        var dest = [Float](repeating: 0, count: width * height * 3)
        let err = src.withUnsafeMutableBufferPointer { srcPtr in
            dest.withUnsafeMutableBufferPointer { dstPtr in
                guard let s = srcPtr.baseAddress, let d = dstPtr.baseAddress else {
                    return kvImageNullPointerArgument
                }
                var rgbaBuf = vImage_Buffer(
                    data: s,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4 * MemoryLayout<Float>.stride
                )
                var rgbBuf = vImage_Buffer(
                    data: d,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 3 * MemoryLayout<Float>.stride
                )
                return vImageConvert_RGBAFFFFtoRGBFFF(&rgbaBuf, &rgbBuf, vImage_Flags(kvImageNoFlags))
            }
        }
        if err == kvImageNoError {
            return dest
        }
        let n = width * height
        for i in 0..<n {
            dest[i * 3] = rgba[i * 4]
            dest[i * 3 + 1] = rgba[i * 4 + 1]
            dest[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return dest
    }

    // MARK: - INTER_AREA (NegPy / OpenCV box average)

    static func areaResized(_ image: LinearRGBBuffer, width dstW: Int, height dstH: Int) -> LinearRGBBuffer? {
        let srcW = image.width
        let srcH = image.height
        guard dstW > 0, dstH > 0, srcW > 0, srcH > 0 else { return nil }
        var out = [Float](repeating: 0, count: dstW * dstH * 3)
        var rowAcc = [Float](repeating: 0, count: srcW * 3)
        let rowSamples = srcW * 3
        let ok = image.pixels.withUnsafeBufferPointer { srcPtr in
            out.withUnsafeMutableBufferPointer { dstPtr in
                rowAcc.withUnsafeMutableBufferPointer { accPtr -> Bool in
                    guard let src = srcPtr.baseAddress,
                          let dst = dstPtr.baseAddress,
                          let acc = accPtr.baseAddress
                    else { return false }
                    for y in 0..<dstH {
                        let y0 = y * srcH / dstH
                        let y1 = min(srcH, max(y0 + 1, (y + 1) * srcH / dstH))
                        let nY = y1 - y0
                        acc.update(from: src.advanced(by: y0 * rowSamples), count: rowSamples)
                        if nY > 1 {
                            for sy in (y0 + 1)..<y1 {
                                vDSP_vadd(
                                    acc,
                                    1,
                                    src.advanced(by: sy * rowSamples),
                                    1,
                                    acc,
                                    1,
                                    vDSP_Length(rowSamples)
                                )
                            }
                        }
                        let invY = 1 / Float(nY)
                        for x in 0..<dstW {
                            let x0 = x * srcW / dstW
                            let x1 = min(srcW, max(x0 + 1, (x + 1) * srcW / dstW))
                            let nX = x1 - x0
                            var r: Float = 0
                            var g: Float = 0
                            var b: Float = 0
                            vDSP_sve(acc.advanced(by: x0 * 3), 3, &r, vDSP_Length(nX))
                            vDSP_sve(acc.advanced(by: x0 * 3 + 1), 3, &g, vDSP_Length(nX))
                            vDSP_sve(acc.advanced(by: x0 * 3 + 2), 3, &b, vDSP_Length(nX))
                            let inv = invY / Float(nX)
                            let d = (y * dstW + x) * 3
                            dst[d] = r * inv
                            dst[d + 1] = g * inv
                            dst[d + 2] = b * inv
                        }
                    }
                    return true
                }
            }
        }
        return ok ? LinearRGBBuffer(width: dstW, height: dstH, pixels: out) : nil
    }

    // MARK: - 16-bit / 8-bit → float RGB

    private static func uint16ToFloat(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        channels: Int
    ) -> [Float]? {
        guard channels == 1 || channels == 3 || channels == 4 else { return nil }
        let samples = width * channels
        var floats = [Float](repeating: 0, count: height * samples)
        let converted = floats.withUnsafeMutableBufferPointer { dstPtr in
            guard let dest = dstPtr.baseAddress else { return false }
            var src = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: ptr),
                height: vImagePixelCount(height),
                width: vImagePixelCount(samples),
                rowBytes: bytesPerRow
            )
            var dst = vImage_Buffer(
                data: dest,
                height: vImagePixelCount(height),
                width: vImagePixelCount(samples),
                rowBytes: samples * MemoryLayout<Float>.stride
            )
            return vImageConvert_16UToF(&src, &dst, 0, 1 / 65535, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
        guard converted else { return nil }
        return compactToRGB(floats, width: width, height: height, channels: channels, bgra: false)
    }

    private static func uint8ToFloat(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        channels: Int,
        bgra: Bool
    ) -> [Float]? {
        guard channels == 1 || channels == 3 || channels == 4 else { return nil }
        let samples = width * channels
        var floats = [Float](repeating: 0, count: height * samples)
        let converted = floats.withUnsafeMutableBufferPointer { dstPtr in
            guard let dest = dstPtr.baseAddress else { return false }
            var src = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: ptr),
                height: vImagePixelCount(height),
                width: vImagePixelCount(samples),
                rowBytes: bytesPerRow
            )
            var dst = vImage_Buffer(
                data: dest,
                height: vImagePixelCount(height),
                width: vImagePixelCount(samples),
                rowBytes: samples * MemoryLayout<Float>.stride
            )
            return vImageConvert_Planar8toPlanarF(&src, &dst, 1, 0, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
        guard converted else { return nil }
        return compactToRGB(floats, width: width, height: height, channels: channels, bgra: bgra)
    }

    private static func compactToRGB(
        _ samples: [Float],
        width: Int,
        height: Int,
        channels: Int,
        bgra: Bool
    ) -> [Float]? {
        if channels == 3 { return samples }
        if channels == 1 {
            return planarToRGB(samples, width: width, height: height)
        }
        var src = samples
        var dest = [Float](repeating: 0, count: width * height * 3)
        let err = src.withUnsafeMutableBufferPointer { srcPtr in
            dest.withUnsafeMutableBufferPointer { dstPtr in
                guard let s = srcPtr.baseAddress, let d = dstPtr.baseAddress else {
                    return kvImageNullPointerArgument
                }
                var four = vImage_Buffer(
                    data: s,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4 * MemoryLayout<Float>.stride
                )
                var three = vImage_Buffer(
                    data: d,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 3 * MemoryLayout<Float>.stride
                )
                if bgra {
                    return vImageConvert_BGRAFFFFtoRGBFFF(&four, &three, vImage_Flags(kvImageNoFlags))
                }
                return vImageConvert_RGBAFFFFtoRGBFFF(&four, &three, vImage_Flags(kvImageNoFlags))
            }
        }
        return err == kvImageNoError ? dest : nil
    }

    private static func planarToRGB(_ planar: [Float], width: Int, height: Int) -> [Float]? {
        var plane = planar
        var dest = [Float](repeating: 0, count: width * height * 3)
        let err = plane.withUnsafeMutableBufferPointer { srcPtr in
            dest.withUnsafeMutableBufferPointer { dstPtr in
                guard let s = srcPtr.baseAddress, let d = dstPtr.baseAddress else {
                    return kvImageNullPointerArgument
                }
                var gray = vImage_Buffer(
                    data: s,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.stride
                )
                var rgb = vImage_Buffer(
                    data: d,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 3 * MemoryLayout<Float>.stride
                )
                return vImageConvert_PlanarFtoRGBFFF(&gray, &gray, &gray, &rgb, vImage_Flags(kvImageNoFlags))
            }
        }
        return err == kvImageNoError ? dest : nil
    }

    // MARK: - Scalar fallbacks (look-identical)

    private static func extractUInt16Scalar(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        channels: Int,
        littleEndian: Bool
    ) throws -> LinearRGBBuffer {
        let scale: Float = 1 / 65535
        var pixels = [Float](repeating: 0, count: width * height * 3)
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
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    private static func extractUInt8Scalar(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        channels: Int,
        bgra: Bool
    ) throws -> LinearRGBBuffer {
        let scale: Float = 1 / 255
        var pixels = [Float](repeating: 0, count: width * height * 3)
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
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    private static func readU16(_ ptr: UnsafePointer<UInt8>, littleEndian: Bool) -> UInt16 {
        let raw = UnsafeRawPointer(ptr).load(as: UInt16.self)
        return littleEndian ? UInt16(littleEndian: raw) : UInt16(bigEndian: raw)
    }
}
