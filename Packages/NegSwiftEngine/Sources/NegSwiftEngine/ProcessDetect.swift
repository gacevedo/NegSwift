/// Process-mode heuristics ported from NegPy `features/process/logic.py`.
///
/// Analysis crop is the hardcoded **0.12** centre inset (not `analysis_buffer`).
/// Lite UI maps Transparency (E-6) to Color Negative.
public enum FilmProcessMode: String, Sendable, Equatable {
    case colorNegative = "Color Negative"
    case bwNegative = "B&W Negative"
    case transparency = "Transparency"

    /// NegSwift picker: C-41 or B&W only.
    public var liteMode: FilmProcessMode {
        self == .bwNegative ? .bwNegative : .colorNegative
    }
}

public enum ProcessDetect: Sendable {
    public static let analysisBuffer: Float = 0.12
    public static let maxAnalysisDim = 256
    /// Decode long edge so a 0.12 centre crop still has ≥ `maxAnalysisDim` samples.
    public static let detectDecodeLongEdge = 512
    public static let bwCorrThreshold: Float = 0.99
    public static let c41OrangeThreshold: Float = 1.5
    public static let purpleGDeficit: Float = 0.05
    public static let purpleRBBalance: Float = 1.05

    public static func detect(_ raw: LinearRGBBuffer?) -> FilmProcessMode {
        guard let raw, raw.width > 0, raw.height > 0, raw.pixels.count >= 3 else {
            return .colorNegative
        }
        var img = raw.analysisCenterCrop(bufferRatio: analysisBuffer)
        img = img.stridedDownsample(maxDim: maxAnalysisDim)
        if img.pixels.isEmpty {
            return .colorNegative
        }
        let count = img.width * img.height
        var r = [Float](repeating: 0, count: count)
        var g = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = clamp01(img.pixels[i * 3])
            g[i] = clamp01(img.pixels[i * 3 + 1])
            b[i] = clamp01(img.pixels[i * 3 + 2])
        }

        let minCorr = min(corr(r, g), corr(g, b), corr(r, b))
        if minCorr > bwCorrThreshold {
            return .bwNegative
        }

        let rMean = mean(r)
        let bMean = mean(b)
        let rP25 = percentile(r, 25)
        let bP25 = percentile(b, 25)
        let rP98 = percentile(r, 98)
        let gP98 = percentile(g, 98)
        let bP98 = percentile(b, 98)

        let orangeScore = max(
            (rMean + 1e-6) / (bMean + 1e-6),
            (rP25 + 1e-6) / (bP25 + 1e-6),
            (rP98 + 1e-6) / (bP98 + 1e-6)
        )
        if orangeScore > c41OrangeThreshold {
            return .colorNegative
        }
        if hasPurpleMask(r: rP98, g: gP98, b: bP98) {
            return .colorNegative
        }
        return .transparency
    }

    public static func detectLite(_ raw: LinearRGBBuffer?) -> FilmProcessMode {
        detect(raw).liteMode
    }

    private static func clamp01(_ x: Float) -> Float {
        min(1, max(0, x.isFinite ? x : 0))
    }

    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func corr(_ a: [Float], _ b: [Float]) -> Float {
        let n = a.count
        guard n > 0 else { return 0 }
        let ma = mean(a)
        let mb = mean(b)
        var dot: Float = 0
        var aa: Float = 0
        var bb: Float = 0
        for i in 0..<n {
            let da = a[i] - ma
            let db = b[i] - mb
            dot += da * db
            aa += da * da
            bb += db * db
        }
        // Zero-variance channels are not evidence of B&W (numpy: 0 / 1e-12 == 0).
        if aa < 1e-8 || bb < 1e-8 {
            return 0
        }
        let denom = (aa * bb).squareRoot() + 1e-12
        return dot / denom
    }

    private static func percentile(_ values: [Float], _ p: Double) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let idx = (Double(sorted.count - 1) * p / 100.0)
        let lo = Int(idx.rounded(.down))
        let hi = min(sorted.count - 1, Int(idx.rounded(.up)))
        let t = Float(idx - Double(lo))
        return sorted[lo] * (1 - t) + sorted[hi] * t
    }

    private static func hasPurpleMask(r: Float, g: Float, b: Float) -> Bool {
        let deficit = (r + b) / 2 - g
        let balance = min(r, b) / (g + 1e-6)
        return deficit > purpleGDeficit && balance > purpleRBBalance
    }
}
