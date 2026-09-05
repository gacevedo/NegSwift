import Foundation

public struct NeutralAxisRefs: Sendable {
    public var midtone: (Double, Double, Double)
    public var shadow: (Double, Double, Double)
    public var highlight: (Double, Double, Double)?
    public var confidence: Double
}

/// Cast-removal meters from NegPy `normalization.py` (shadow refs + neutral axis).
public enum CastMetering: Sendable {
    public static func analysisGrid(
        linear: LinearRGBBuffer,
        analysisBuffer: Float,
        analysisRect: NormalizedCropRect? = nil
    ) -> LinearRGBBuffer {
        var imgLog = LogNormalization.toLogDensity(linear)
        imgLog = imgLog.applyingAnalysis(buffer: analysisBuffer, rect: analysisRect)
        return LogNormalization.blockMedianGrid(imgLog)
    }

    public static func shadowRefs(_ grid: LinearRGBBuffer) -> (Double, Double, Double) {
        let sorted = sortedChannels(grid)
        let p = ExposureConstants.shadowNeutralPercentile
        return (
            LogNormalization.percentileFromSorted(sorted[0], q: p),
            LogNormalization.percentileFromSorted(sorted[1], q: p),
            LogNormalization.percentileFromSorted(sorted[2], q: p)
        )
    }

    public static func normalizeRefs(
        _ refs: (Double, Double, Double),
        bounds: LogNegativeBounds
    ) -> (Double, Double, Double) {
        func ch(_ r: Double, _ f: Double, _ c: Double) -> Double {
            var denom = c - f
            if abs(denom) < 1e-6 {
                denom = denom >= 0 ? 1e-6 : -1e-6
            }
            return (r - f) / denom
        }
        return (
            ch(refs.0, bounds.floors.0, bounds.ceils.0),
            ch(refs.1, bounds.floors.1, bounds.ceils.1),
            ch(refs.2, bounds.floors.2, bounds.ceils.2)
        )
    }

    public static func measureNeutralAxis(
        grid: LinearRGBBuffer,
        bounds: LogNegativeBounds
    ) -> NeutralAxisRefs? {
        let norm = LogNormalization.normalizeLogImage(grid, bounds: bounds)
        let n = grid.width * grid.height
        var luma = [Double](repeating: 0, count: n)
        var chroma = [Double](repeating: 0, count: n)
        var logR = [Double](repeating: 0, count: n)
        var logG = [Double](repeating: 0, count: n)
        var logB = [Double](repeating: 0, count: n)
        var nr = [Double](repeating: 0, count: n)
        var ng = [Double](repeating: 0, count: n)
        var nb = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let r = Double(norm.pixels[i * 3])
            let g = Double(norm.pixels[i * 3 + 1])
            let b = Double(norm.pixels[i * 3 + 2])
            nr[i] = r
            ng[i] = g
            nb[i] = b
            logR[i] = Double(grid.pixels[i * 3])
            logG[i] = Double(grid.pixels[i * 3 + 1])
            logB[i] = Double(grid.pixels[i * 3 + 2])
            luma[i] = ExposureConstants.lumaR * r + ExposureConstants.lumaG * g + ExposureConstants.lumaB * b
            chroma[i] = rmsChroma(r, g, b)
        }

        func bandRefs(lo: Double, hi: Double, chromaVals: [Double], cap: Double) -> (refs: (Double, Double, Double), chroma: Double, count: Int)? {
            var bandIdx: [Int] = []
            for i in 0..<n where luma[i] >= lo && luma[i] <= hi {
                bandIdx.append(i)
            }
            if bandIdx.count < ExposureConstants.neutralAxisMinPixels {
                return nil
            }
            let bandChroma = bandIdx.map { chromaVals[$0] }
            let thr = LogNormalization.percentileFromSorted(bandChroma.sorted(), q: ExposureConstants.neutralAxisChromaQuantile * 100)
            var keep: [Int] = []
            var keptChroma: [Double] = []
            for (j, idx) in bandIdx.enumerated() where bandChroma[j] <= thr {
                keep.append(idx)
                keptChroma.append(bandChroma[j])
            }
            let near = keptChroma.isEmpty ? cap : median(keptChroma)
            if keep.count < ExposureConstants.neutralAxisMinPixels || near > cap {
                return nil
            }
            let refs = (
                median(keep.map { logR[$0] }),
                median(keep.map { logG[$0] }),
                median(keep.map { logB[$0] })
            )
            return (refs, near, keep.count)
        }

        let mb = ExposureConstants.neutralAxisMidBand
        let sb = ExposureConstants.neutralAxisShadowBand
        let hb = ExposureConstants.neutralAxisHighlightBand
        guard let mid1 = bandRefs(lo: mb.0, hi: mb.1, chromaVals: chroma, cap: ExposureConstants.neutralAxisFirstPassCap),
              let sh1 = bandRefs(lo: sb.0, hi: sb.1, chromaVals: chroma, cap: ExposureConstants.neutralAxisFirstPassCap)
        else {
            return nil
        }

        let nm = normalizeRefs(mid1.refs, bounds: bounds)
        let ns = normalizeRefs(sh1.refs, bounds: bounds)
        var chroma2 = [Double](repeating: 0, count: n)
        var cr = nr
        var cb = nb
        for ch in [0, 2] {
            let uM = ch == 0 ? nm.0 : nm.2
            let uS = ch == 0 ? ns.0 : ns.2
            let du = uM - uS
            let a: Double
            let b: Double
            if abs(du) < 1e-6 {
                a = 1
                b = nm.1 - uM
            } else {
                a = (nm.1 - ns.1) / du
                b = nm.1 - a * uM
            }
            if ch == 0 {
                for i in 0..<n { cr[i] = a * nr[i] + b }
            } else {
                for i in 0..<n { cb[i] = a * nb[i] + b }
            }
        }
        for i in 0..<n {
            chroma2[i] = rmsChroma(cr[i], ng[i], cb[i])
        }

        guard let mid = bandRefs(lo: mb.0, hi: mb.1, chromaVals: chroma2, cap: ExposureConstants.neutralAxisChromaCap),
              let shadow = bandRefs(lo: sb.0, hi: sb.1, chromaVals: chroma2, cap: ExposureConstants.neutralAxisChromaCap)
        else {
            return nil
        }
        let highlight = bandRefs(lo: hb.0, hi: hb.1, chromaVals: chroma2, cap: ExposureConstants.neutralAxisChromaCap)

        let cap = ExposureConstants.neutralAxisChromaCap
        let tight = min(max(1 - max(mid.chroma, shadow.chroma) / cap, 0), 1)
        let sizeTerm = Double(mid.count) / (Double(mid.count) + ExposureConstants.neutralAxisConfidenceN0)
        let dm = normalizeRefs(mid.refs, bounds: bounds)
        let ds = normalizeRefs(shadow.refs, bounds: bounds)
        let spread = max(abs((dm.0 - dm.1) - (ds.0 - ds.1)), abs((dm.2 - dm.1) - (ds.2 - ds.1)))
        let agree = 1 - min(max(spread - ExposureConstants.neutralAxisAgreementDeadzone, 0) / ExposureConstants.neutralAxisAgreementScale, 1)
        let confidence = min(max(tight * sizeTerm * agree, 0), 1)
        return NeutralAxisRefs(
            midtone: mid.refs,
            shadow: shadow.refs,
            highlight: highlight?.refs,
            confidence: confidence
        )
    }

    public static func effectiveStrength(_ slider: Double, confidence: Double?) -> Double {
        if let confidence {
            return confidence * slider
        }
        return slider
    }

    private static func rmsChroma(_ r: Double, _ g: Double, _ b: Double) -> Double {
        sqrt(((r - g) * (r - g) + (g - b) * (g - b) + (r - b) * (r - b)) / 3)
    }

    private static func sortedChannels(_ img: LinearRGBBuffer) -> [[Double]] {
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
