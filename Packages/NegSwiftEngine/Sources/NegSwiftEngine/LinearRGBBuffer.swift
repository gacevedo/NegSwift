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

    /// Quarter-turns CCW (`np.rot90` k), then optional flips. Crop is applied in this space.
    public func oriented(rotation: Int, flipHorizontal: Bool, flipVertical: Bool) -> LinearRGBBuffer {
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
        return out
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

    /// Normalized crop `[x1, y1, x2, y2]` in current-buffer space (after orientation).
    public func cropped(normalized rect: (Float, Float, Float, Float)) -> LinearRGBBuffer {
        let x1 = min(max(Double(rect.0), 0), 1)
        let y1 = min(max(Double(rect.1), 0), 1)
        let x2 = min(max(Double(rect.2), 0), 1)
        let y2 = min(max(Double(rect.3), 0), 1)
        let left = min(x1, x2)
        let top = min(y1, y2)
        let right = max(x1, x2)
        let bottom = max(y1, y2)
        if right - left < 1e-6 || bottom - top < 1e-6 { return self }
        if left <= 1e-6, top <= 1e-6, right >= 1 - 1e-6, bottom >= 1 - 1e-6 { return self }
        let x0 = min(max(Int((left * Double(width)).rounded(.down)), 0), width - 1)
        let y0 = min(max(Int((top * Double(height)).rounded(.down)), 0), height - 1)
        let x1i = min(max(Int((right * Double(width)).rounded(.up)), x0 + 1), width)
        let y1i = min(max(Int((bottom * Double(height)).rounded(.up)), y0 + 1), height)
        let newW = x1i - x0
        let newH = y1i - y0
        if newW == width, newH == height { return self }
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
}
