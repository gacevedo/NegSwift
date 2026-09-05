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
}
