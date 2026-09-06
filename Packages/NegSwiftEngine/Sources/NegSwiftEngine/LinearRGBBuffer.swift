import Foundation

/// Scene-linear interleaved RGB float32 buffer in [0, 1].
public struct LinearRGBBuffer: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// `width * height * 3` samples, row-major RGB.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(width > 0 && height > 0, "LinearRGBBuffer size must be positive")
        precondition(
            pixels.count == width * height * 3,
            "LinearRGBBuffer expected \(width * height * 3) samples, got \(pixels.count)"
        )
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Mid-gray placeholder used by S0 tests.
    public static func stub(width: Int, height: Int, gray: Float = 0.5) -> LinearRGBBuffer {
        let count = width * height * 3
        return LinearRGBBuffer(width: width, height: height, pixels: [Float](repeating: gray, count: count))
    }

    public var sampleCount: Int { pixels.count }

    /// Nearest-neighbor downsample so the long edge is at most `maxEdge`.
    public func downsampled(toLongEdge maxEdge: Int) -> LinearRGBBuffer {
        let longest = max(width, height)
        guard maxEdge > 0, longest > maxEdge else { return self }
        let newWidth = max(1, Int((Double(width) * Double(maxEdge) / Double(longest)).rounded()))
        let newHeight = max(1, Int((Double(height) * Double(maxEdge) / Double(longest)).rounded()))
        var out = [Float](repeating: 0, count: newWidth * newHeight * 3)
        for y in 0..<newHeight {
            let srcY = min(height - 1, y * height / newHeight)
            for x in 0..<newWidth {
                let srcX = min(width - 1, x * width / newWidth)
                let src = (srcY * width + srcX) * 3
                let dst = (y * newWidth + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: newWidth, height: newHeight, pixels: out)
    }

    /// Center crop used by process-mode detect (`buffer_ratio` 0.12 in NegPy).
    public func analysisCenterCrop(bufferRatio: Float) -> LinearRGBBuffer {
        guard bufferRatio > 0 else { return self }
        let safe = min(max(bufferRatio, 0), 0.3)
        let cutH = Int(Float(height) * safe)
        let cutW = Int(Float(width) * safe)
        let newH = max(1, height - 2 * cutH)
        let newW = max(1, width - 2 * cutW)
        if newH == height, newW == width { return self }
        var out = [Float](repeating: 0, count: newW * newH * 3)
        for y in 0..<newH {
            let srcY = y + cutH
            for x in 0..<newW {
                let srcX = x + cutW
                let src = (srcY * width + srcX) * 3
                let dst = (y * newW + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: newW, height: newH, pixels: out)
    }

    /// Strided downsample (`step = ceil(longest / maxDim)`), matching NegPy detect.
    public func stridedDownsample(maxDim: Int) -> LinearRGBBuffer {
        let longest = max(width, height)
        guard longest > maxDim else { return self }
        let step = max(1, Int((Double(longest) / Double(maxDim)).rounded(.up)))
        let newH = max(1, (height + step - 1) / step)
        let newW = max(1, (width + step - 1) / step)
        var out = [Float](repeating: 0, count: newW * newH * 3)
        var dstY = 0
        var y = 0
        while y < height {
            var dstX = 0
            var x = 0
            while x < width {
                let src = (y * width + x) * 3
                let dst = (dstY * newW + dstX) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
                x += step
                dstX += 1
            }
            y += step
            dstY += 1
        }
        return LinearRGBBuffer(width: newW, height: newH, pixels: out)
    }

    /// Quarter-turns CCW (`np.rot90` k), then optional flips, then fine rotation.
    /// Crop is applied in this space.
    public func oriented(
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float = 0
    ) -> LinearRGBBuffer {
        var out = self
        let turns = ((rotation % 4) + 4) % 4
        if turns != 0 {
            out = out.rotatedQuarterTurnsCCW(turns)
        }
        if flipHorizontal {
            out = out.flipped(horizontal: true)
        }
        if flipVertical {
            out = out.flipped(horizontal: false)
        }
        if fineRotation != 0 {
            out = out.fineRotated(degrees: fineRotation)
        }
        return out
    }

    /// NegPy `apply_fine_rotation`: cv2 `getRotationMatrix2D` + `warpAffine`
    /// (`INTER_LINEAR`, `BORDER_REPLICATE`). Canvas size is unchanged.
    public func fineRotated(degrees: Float) -> LinearRGBBuffer {
        if degrees == 0 { return self }
        let theta = Double(degrees) * Double.pi / 180
        let alpha = cos(theta)
        let beta = sin(theta)
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        var out = [Float](repeating: 0, count: pixels.count)
        let srcW = width
        let srcH = height
        let maxX = srcW - 1
        let maxY = srcH - 1
        for y in 0..<srcH {
            let dy = Double(y) - cy
            for x in 0..<srcW {
                let dx = Double(x) - cx
                let sx = cx + alpha * dx - beta * dy
                let sy = cy + beta * dx + alpha * dy
                let x0 = Int(floor(sx))
                let y0 = Int(floor(sy))
                let fx = Float(sx - Double(x0))
                let fy = Float(sy - Double(y0))
                let x1 = x0 + 1
                let y1 = y0 + 1
                let p00 = replicatedPixel(x: x0, y: y0, maxX: maxX, maxY: maxY)
                let p10 = replicatedPixel(x: x1, y: y0, maxX: maxX, maxY: maxY)
                let p01 = replicatedPixel(x: x0, y: y1, maxX: maxX, maxY: maxY)
                let p11 = replicatedPixel(x: x1, y: y1, maxX: maxX, maxY: maxY)
                let w00 = (1 - fx) * (1 - fy)
                let w10 = fx * (1 - fy)
                let w01 = (1 - fx) * fy
                let w11 = fx * fy
                let dst = (y * srcW + x) * 3
                out[dst] = p00.0 * w00 + p10.0 * w10 + p01.0 * w01 + p11.0 * w11
                out[dst + 1] = p00.1 * w00 + p10.1 * w10 + p01.1 * w01 + p11.1 * w11
                out[dst + 2] = p00.2 * w00 + p10.2 * w10 + p01.2 * w01 + p11.2 * w11
            }
        }
        return LinearRGBBuffer(width: srcW, height: srcH, pixels: out)
    }

    private func replicatedPixel(x: Int, y: Int, maxX: Int, maxY: Int) -> (Float, Float, Float) {
        let cx = min(max(x, 0), maxX)
        let cy = min(max(y, 0), maxY)
        let i = (cy * width + cx) * 3
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    public func rotatedQuarterTurnsCCW(_ turns: Int) -> LinearRGBBuffer {
        let k = ((turns % 4) + 4) % 4
        if k == 0 { return self }
        if k == 2 {
            var pixels = self.pixels
            let n = width * height
            for i in 0..<(n / 2) {
                let j = n - 1 - i
                let a = i * 3
                let b = j * 3
                for c in 0..<3 {
                    let t = pixels[a + c]
                    pixels[a + c] = pixels[b + c]
                    pixels[b + c] = t
                }
            }
            return LinearRGBBuffer(width: width, height: height, pixels: pixels)
        }
        let srcW = width
        let srcH = height
        let dstW = srcH
        let dstH = srcW
        var out = [Float](repeating: 0, count: dstW * dstH * 3)
        for y in 0..<srcH {
            for x in 0..<srcW {
                let dx: Int
                let dy: Int
                if k == 1 {
                    dx = y
                    dy = srcW - 1 - x
                } else {
                    dx = srcH - 1 - y
                    dy = x
                }
                let src = (y * srcW + x) * 3
                let dst = (dy * dstW + dx) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: dstW, height: dstH, pixels: out)
    }

    public func flipped(horizontal: Bool) -> LinearRGBBuffer {
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let sx = horizontal ? (width - 1 - x) : x
                let sy = horizontal ? y : (height - 1 - y)
                let src = (sy * width + sx) * 3
                let dst = (y * width + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: width, height: height, pixels: out)
    }

    /// Apply NegPy `resolve_analysis_region`: optional normalized ROI, then center buffer.
    public func applyingAnalysis(buffer: Float, rect: NormalizedCropRect?) -> LinearRGBBuffer {
        var out = self
        if let rect {
            out = out.croppedToAnalysisROI(normalized: rect.tuple)
        }
        if buffer > 0 {
            out = out.analysisCenterCrop(bufferRatio: buffer)
        }
        return out
    }

    /// NegPy `resolve_analysis_region` pixel ROI (`int(y * h)`, ignore if either span < 2).
    public func croppedToAnalysisROI(normalized rect: (Double, Double, Double, Double)) -> LinearRGBBuffer {
        let y1 = Int(min(rect.1, rect.3) * Double(height))
        let y2 = Int(max(rect.1, rect.3) * Double(height))
        let x1 = Int(min(rect.0, rect.2) * Double(width))
        let x2 = Int(max(rect.0, rect.2) * Double(width))
        if y2 - y1 < 2 || x2 - x1 < 2 { return self }
        let x0 = min(max(x1, 0), width)
        let y0 = min(max(y1, 0), height)
        let x1i = min(max(x2, x0), width)
        let y1i = min(max(y2, y0), height)
        let newW = x1i - x0
        let newH = y1i - y0
        if newW <= 0 || newH <= 0 || (newW == width && newH == height) { return self }
        var out = [Float](repeating: 0, count: newW * newH * 3)
        for y in 0..<newH {
            for x in 0..<newW {
                let src = ((y0 + y) * width + (x0 + x)) * 3
                let dst = (y * newW + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: newW, height: newH, pixels: out)
    }

    /// Stored crop `[x1, y1, x2, y2]` after orientation — NegPy `get_manual_rect_coords`
    /// (`int(x * w)`, then clamp). Empty ROI is a no-op.
    public func cropped(normalized rect: (Double, Double, Double, Double)) -> LinearRGBBuffer {
        guard let roi = Self.storedCropPixelROI(width: width, height: height, rect: rect) else {
            return self
        }
        let newW = roi.x2 - roi.x1
        let newH = roi.y2 - roi.y1
        if newW == width, newH == height { return self }
        var out = [Float](repeating: 0, count: newW * newH * 3)
        for y in 0..<newH {
            for x in 0..<newW {
                let src = ((roi.y1 + y) * width + (roi.x1 + x)) * 3
                let dst = (y * newW + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return LinearRGBBuffer(width: newW, height: newH, pixels: out)
    }

    /// Pixel ROI matching NegPy `get_manual_rect_coords` + `apply_margin_to_roi(..., 0)`.
    public static func storedCropPixelROI(
        width: Int,
        height: Int,
        rect: (Double, Double, Double, Double)
    ) -> (x1: Int, y1: Int, x2: Int, y2: Int)? {
        let xs = (rect.0 * Double(width), rect.2 * Double(width))
        let ys = (rect.1 * Double(height), rect.3 * Double(height))
        let x1 = min(max(Int(min(xs.0, xs.1)), 0), width)
        let x2 = min(max(Int(max(xs.0, xs.1)), 0), width)
        let y1 = min(max(Int(min(ys.0, ys.1)), 0), height)
        let y2 = min(max(Int(max(ys.0, ys.1)), 0), height)
        if x2 - x1 <= 0 || y2 - y1 <= 0 { return nil }
        return (x1, y1, x2, y2)
    }
}
