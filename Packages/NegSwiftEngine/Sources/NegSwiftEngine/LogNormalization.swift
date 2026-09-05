import Foundation

/// Per-channel log-density D-min / D-max. Unclamped stretch; rolloff is S4.
public struct LogNegativeBounds: Sendable {
    public var floors: (Double, Double, Double)
    public var ceils: (Double, Double, Double)

    public init(floors: (Double, Double, Double), ceils: (Double, Double, Double)) {
        self.floors = floors
        self.ceils = ceils
    }

    public func floor(_ channel: Int) -> Double {
        switch channel {
        case 0: floors.0
        case 1: floors.1
        default: floors.2
        }
    }

    public func ceil(_ channel: Int) -> Double {
        switch channel {
        case 0: ceils.0
        case 1: ceils.1
        default: ceils.2
        }
    }
}

/// Kept polarity path from NegPy `features/exposure/normalization.py`.
///
/// Linear → log10 → block-median percentile bounds → unclamped per-channel stretch.
/// No invert, H&D, autos, or cast (those are later verticals).
public enum LogNormalization: Sendable {
    public static let epsilon: Float = 1e-6
    public static let defaultAnalysisBuffer: Float = 0.05
    public static let defaultLumaRangeClip = 0.0
    public static let defaultColorRangeClip = 1.0
    public static let analysisGrid = 1024
    public static let baseLumaClip = 0.01

    static let lumaR = 0.2126
    static let lumaG = 0.7152
    static let lumaB = 0.0722
    static let colorBoundsBandWidth = 4.0
    static let chromaQuantile = 0.30
    static let chromaCap = 0.29
    static let firstPassChromaCap = 0.55
    static let minNeutralPixels = 64

    /// Analysis log: `log10(clamp(x, eps, 1))`.
    public static func toLogDensity(_ image: LinearRGBBuffer) -> LinearRGBBuffer {
        log10(image, clampHigh: true)
    }

    /// Stretch-domain log: low-side clamp only, matching `NormalizationProcessor`.
    public static func toLogDensityUnclampedHigh(_ image: LinearRGBBuffer) -> LinearRGBBuffer {
        log10(image, clampHigh: false)
    }

    public static func blockMedianGrid(_ imgLog: LinearRGBBuffer, analysisGrid grid: Int = analysisGrid) -> LinearRGBBuffer {
        let h = imgLog.height
        let w = imgLog.width
        let b = Int(ceil(Double(max(h, w)) / Double(grid)))
        if b <= 1 || h < b || w < b {
            return imgLog
        }
        let hb = (h / b) * b
        let wb = (w / b) * b
        let outH = hb / b
        let outW = wb / b
        var out = [Float](repeating: 0, count: outH * outW * 3)
        if b == 2 {
            for gy in 0..<outH {
                for gx in 0..<outW {
                    let y0 = gy * 2
                    let x0 = gx * 2
                    for ch in 0..<3 {
                        let p00 = imgLog.pixels[(y0 * w + x0) * 3 + ch]
                        let p01 = imgLog.pixels[(y0 * w + x0 + 1) * 3 + ch]
                        let p10 = imgLog.pixels[((y0 + 1) * w + x0) * 3 + ch]
                        let p11 = imgLog.pixels[((y0 + 1) * w + x0 + 1) * 3 + ch]
                        let s = Double(p00) + Double(p01) + Double(p10) + Double(p11)
                        let mn = min(p00, p01, p10, p11)
                        let mx = max(p00, p01, p10, p11)
                        out[(gy * outW + gx) * 3 + ch] = Float((s - Double(mn) - Double(mx)) * 0.5)
                    }
                }
            }
        } else {
            var block = [Double](repeating: 0, count: b * b)
            for gy in 0..<outH {
                for gx in 0..<outW {
                    for ch in 0..<3 {
                        var i = 0
                        for by in 0..<b {
                            for bx in 0..<b {
                                let srcY = gy * b + by
                                let srcX = gx * b + bx
                                block[i] = Double(imgLog.pixels[(srcY * w + srcX) * 3 + ch])
                                i += 1
                            }
                        }
                        out[(gy * outW + gx) * 3 + ch] = Float(median(block))
                    }
                }
            }
        }
        return LinearRGBBuffer(width: outW, height: outH, pixels: out)
    }

    public static func normalizeLogImage(_ imgLog: LinearRGBBuffer, bounds: LogNegativeBounds) -> LinearRGBBuffer {
        var out = imgLog.pixels
        let n = imgLog.width * imgLog.height
        for i in 0..<n {
            for ch in 0..<3 {
                let f = Float(bounds.floor(ch))
                let c = Float(bounds.ceil(ch))
                var denom = c - f
                if abs(denom) < epsilon {
                    denom = denom >= 0 ? epsilon : -epsilon
                }
                out[i * 3 + ch] = (imgLog.pixels[i * 3 + ch] - f) / denom
            }
        }
        return LinearRGBBuffer(width: imgLog.width, height: imgLog.height, pixels: out)
    }

    public static func analyzeBounds(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode = .colorNegative,
        analysisBuffer: Float = defaultAnalysisBuffer,
        lumaRangeClip: Double = defaultLumaRangeClip,
        colorRangeClip: Double = defaultColorRangeClip,
        e6Normalize: Bool = true
    ) -> LogNegativeBounds {
        var imgLog = toLogDensity(linear)
        if analysisBuffer > 0 {
            imgLog = imgLog.analysisCenterCrop(bufferRatio: analysisBuffer)
        }
        imgLog = blockMedianGrid(imgLog)
        return analyzeFromLogGrid(
            imgLog,
            processMode: processMode,
            lumaRangeClip: lumaRangeClip,
            colorRangeClip: colorRangeClip,
            e6Normalize: e6Normalize
        )
    }

    /// Full S2 pass: analyze defaults, then stretch the unclamped-high log image.
    public static func process(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode = .colorNegative,
        analysisBuffer: Float = defaultAnalysisBuffer,
        lumaRangeClip: Double = defaultLumaRangeClip,
        colorRangeClip: Double = defaultColorRangeClip,
        bounds: LogNegativeBounds? = nil
    ) -> LinearRGBBuffer {
        let resolved = bounds ?? analyzeBounds(
            linear: linear,
            processMode: processMode,
            analysisBuffer: analysisBuffer,
            lumaRangeClip: lumaRangeClip,
            colorRangeClip: colorRangeClip
        )
        return normalizeLogImage(toLogDensityUnclampedHigh(linear), bounds: resolved)
    }

    static func percentileFromSorted(_ sorted: [Double], q: Double) -> Double {
        let n = sorted.count
        guard n > 0 else { return 0 }
        if n == 1 { return sorted[0] }
        let virtual = Double(n - 1) * (q / 100.0)
        let lo = min(max(Int(floor(virtual)), 0), n - 1)
        let hi = min(lo + 1, n - 1)
        let t = virtual - Double(lo)
        let a = sorted[lo]
        let b = sorted[hi]
        let diff = b - a
        return t >= 0.5 ? b - diff * (1 - t) : a + diff * t
    }

    static func analyzeFromLogGrid(
        _ imgLog: LinearRGBBuffer,
        processMode: FilmProcessMode,
        lumaRangeClip: Double,
        colorRangeClip: Double,
        e6Normalize: Bool
    ) -> LogNegativeBounds {
        let sorted = sortedChannelGrid(imgLog)
        var (floors, ceils) = sampleLogBounds(
            sorted: sorted,
            percentileClip: lumaRangeClip,
            base: baseLumaClip,
            processMode: processMode,
            e6Normalize: e6Normalize
        )
        var (colorFloors, colorCeils) = sampleLogBounds(
            sorted: sorted,
            percentileClip: colorRangeClip,
            base: 0,
            processMode: processMode,
            e6Normalize: e6Normalize
        )
        if processMode != .transparency, colorRangeClip >= 0,
           let shared = samePixelColorFloorRefs(
               imgLog,
               lumaFloors: floors,
               lumaCeils: ceils,
               baseRefs: (colorCeils[0], colorCeils[1], colorCeils[2]),
               colorClip: colorRangeClip
           )
        {
            colorFloors = [shared.0, shared.1, shared.2]
        }
        let meanLF = (floors[0] + floors[1] + floors[2]) / 3
        let meanLC = (ceils[0] + ceils[1] + ceils[2]) / 3
        let meanCF = colorFloors.sorted()[1]
        let meanCC = colorCeils.sorted()[1]
        floors = (0..<3).map { meanLF + (colorFloors[$0] - meanCF) }
        ceils = (0..<3).map { meanLC + (colorCeils[$0] - meanCC) }
        return LogNegativeBounds(
            floors: (floors[0], floors[1], floors[2]),
            ceils: (ceils[0], ceils[1], ceils[2])
        )
    }

    private static func log10(_ image: LinearRGBBuffer, clampHigh: Bool) -> LinearRGBBuffer {
        var pixels = image.pixels
        let eps = epsilon
        for i in pixels.indices {
            var v = pixels[i]
            if v.isNaN || (v.isInfinite && v < 0) {
                v = eps
            } else if v.isInfinite && v > 0 {
                v = 1
            }
            if v < eps { v = eps }
            if clampHigh, v > 1 { v = 1 }
            pixels[i] = v
        }
        for i in pixels.indices {
            pixels[i] = Darwin.log10(pixels[i])
        }
        return LinearRGBBuffer(width: image.width, height: image.height, pixels: pixels)
    }

    private static func sortedChannelGrid(_ img: LinearRGBBuffer) -> [[Double]] {
        let n = img.width * img.height
        var channels = [
            [Double](repeating: 0, count: n),
            [Double](repeating: 0, count: n),
            [Double](repeating: 0, count: n),
        ]
        for i in 0..<n {
            channels[0][i] = Double(img.pixels[i * 3])
            channels[1][i] = Double(img.pixels[i * 3 + 1])
            channels[2][i] = Double(img.pixels[i * 3 + 2])
        }
        for ch in 0..<3 {
            channels[ch].sort()
        }
        return channels
    }

    private static func sampleLogBounds(
        sorted: [[Double]],
        percentileClip: Double,
        base: Double,
        processMode: FilmProcessMode,
        e6Normalize: Bool
    ) -> (floors: [Double], ceils: [Double]) {
        let clip: Double
        let margin: Double
        if percentileClip >= 0 {
            clip = min(50, max(0.00001, percentileClip + base))
            margin = 0
        } else {
            clip = base
            margin = -percentileClip
        }
        var pLow = clip
        var pHigh = 100 - clip
        var fixedRange = 3.0
        if processMode == .transparency {
            swap(&pLow, &pHigh)
            fixedRange = -3
        }
        func pct(_ p: Double) -> [Double] {
            (0..<3).map { percentileFromSorted(sorted[$0], q: p) }
        }
        var floors = pct(pLow)
        let ceils: [Double]
        if processMode != .transparency || e6Normalize {
            ceils = pct(pHigh)
        } else {
            ceils = floors.map { $0 + fixedRange }
        }
        var outCeils = ceils
        if margin > 0 {
            for ch in 0..<3 {
                if outCeils[ch] >= floors[ch] {
                    floors[ch] -= margin
                    outCeils[ch] += margin
                } else {
                    floors[ch] += margin
                    outCeils[ch] -= margin
                }
            }
        }
        return (floors, outCeils)
    }

    private static func samePixelColorFloorRefs(
        _ imgLog: LinearRGBBuffer,
        lumaFloors: [Double],
        lumaCeils: [Double],
        baseRefs: (Double, Double, Double),
        colorClip: Double
    ) -> (Double, Double, Double)? {
        let n = imgLog.width * imgLog.height
        guard n > 0 else { return nil }
        var flatR = [Double](repeating: 0, count: n)
        var flatG = [Double](repeating: 0, count: n)
        var flatB = [Double](repeating: 0, count: n)
        var luma = [Double](repeating: 0, count: n)
        let base = [baseRefs.0, baseRefs.1, baseRefs.2]
        let eps = Double(epsilon)
        for i in 0..<n {
            let r = Double(imgLog.pixels[i * 3])
            let g = Double(imgLog.pixels[i * 3 + 1])
            let b = Double(imgLog.pixels[i * 3 + 2])
            flatR[i] = r
            flatG[i] = g
            flatB[i] = b
            var nr = r - lumaFloors[0]
            var ng = g - lumaFloors[1]
            var nb = b - lumaFloors[2]
            var dr = lumaCeils[0] - lumaFloors[0]
            var dg = lumaCeils[1] - lumaFloors[1]
            var db = lumaCeils[2] - lumaFloors[2]
            if abs(dr) < eps { dr = dr >= 0 ? eps : -eps }
            if abs(dg) < eps { dg = dg >= 0 ? eps : -eps }
            if abs(db) < eps { db = db >= 0 ? eps : -eps }
            nr /= dr
            ng /= dg
            nb /= db
            luma[i] = lumaR * nr + lumaG * ng + lumaB * nb
        }
        let clip = min(50 - colorBoundsBandWidth, max(0.00001, colorClip))
        let lumaSorted = luma.sorted()
        let lo = percentileFromSorted(lumaSorted, q: clip)
        let hi = percentileFromSorted(lumaSorted, q: clip + colorBoundsBandWidth)
        var bandIdx: [Int] = []
        bandIdx.reserveCapacity(n / 8)
        for i in 0..<n where luma[i] >= lo && luma[i] <= hi {
            bandIdx.append(i)
        }
        if bandIdx.count < minNeutralPixels {
            return nil
        }
        let dR = bandIdx.map { flatR[$0] - base[0] }
        let dG = bandIdx.map { flatG[$0] - base[1] }
        let dB = bandIdx.map { flatB[$0] - base[2] }

        func select(gamma: [Double]) -> (mask: [Bool], medianChroma: Double)? {
            var g = gamma
            for i in 0..<3 where abs(g[i]) < eps {
                g[i] = eps
            }
            var chroma = [Double](repeating: 0, count: dR.count)
            for i in 0..<dR.count {
                let r = dR[i] / g[0]
                let gv = dG[i] / g[1]
                let b = dB[i] / g[2]
                chroma[i] = rmsChroma(r: r, g: gv, b: b)
            }
            let thr = percentileFromSorted(chroma.sorted(), q: chromaQuantile * 100)
            var keep = [Bool](repeating: false, count: chroma.count)
            var keptChroma: [Double] = []
            for i in 0..<chroma.count where chroma[i] <= thr {
                keep[i] = true
                keptChroma.append(chroma[i])
            }
            if keptChroma.count < minNeutralPixels {
                return nil
            }
            return (keep, median(keptChroma))
        }

        let spans = [
            lumaFloors[0] - baseRefs.0,
            lumaFloors[1] - baseRefs.1,
            lumaFloors[2] - baseRefs.2,
        ]
        guard let first = select(gamma: spans), first.medianChroma <= firstPassChromaCap else {
            return nil
        }
        let provisional = medianChannels(dR: dR, dG: dG, dB: dB, mask: first.mask)
        if abs(provisional[0]) < eps || abs(provisional[1]) < eps || abs(provisional[2]) < eps {
            return nil
        }
        guard let second = select(gamma: provisional), second.medianChroma <= chromaCap else {
            return nil
        }
        let delta = medianChannels(dR: dR, dG: dG, dB: dB, mask: second.mask)
        return (base[0] + delta[0], base[1] + delta[1], base[2] + delta[2])
    }

    private static func rmsChroma(r: Double, g: Double, b: Double) -> Double {
        sqrt(((r - g) * (r - g) + (g - b) * (g - b) + (r - b) * (r - b)) / 3)
    }

    private static func medianChannels(dR: [Double], dG: [Double], dB: [Double], mask: [Bool]) -> [Double] {
        var r: [Double] = []
        var g: [Double] = []
        var b: [Double] = []
        r.reserveCapacity(mask.count)
        for i in 0..<mask.count where mask[i] {
            r.append(dR[i])
            g.append(dG[i])
            b.append(dB[i])
        }
        return [median(r), median(g), median(b)]
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        guard n > 0 else { return 0 }
        if n % 2 == 1 {
            return sorted[n / 2]
        }
        return 0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
    }
}
