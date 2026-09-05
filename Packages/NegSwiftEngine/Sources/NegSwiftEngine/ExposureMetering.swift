import Foundation

/// Auto Density / Auto Grade meters from NegPy `normalization.py`.
public enum ExposureMetering: Sendable {
    public static func measureAnchorFromLog(
        _ imgLog: LinearRGBBuffer,
        bounds: LogNegativeBounds,
        analysisBuffer: Float = 0
    ) -> Double {
        let lum = texturedNormLuma(prefiltered(imgLog, analysisBuffer: analysisBuffer), bounds: bounds)
        let clip = ExposureConstants.anchorTrimClip
        let lo = percentile(lum, clip)
        let hi = percentile(lum, 100 - clip)
        let inner = lum.filter { $0 >= lo && $0 <= hi }
        let mean = inner.isEmpty ? 0.5 * (lo + hi) : inner.reduce(0, +) / Double(inner.count)
        let measured = 0.5 * (mean + 0.5 * (lo + hi))
        let assumed = ExposureConstants.assumedAnchor
        let strength = ExposureConstants.anchorMeterStrength
        let band = ExposureConstants.anchorMeterBand
        let anchor = assumed + strength * (measured - assumed)
        return min(max(anchor, assumed - band), assumed + band)
    }

    public static func measureTexturalRangeFromLog(
        _ imgLog: LinearRGBBuffer,
        analysisBuffer: Float = 0
    ) -> Double {
        let grid = prefiltered(imgLog, analysisBuffer: analysisBuffer)
        let n = grid.width * grid.height
        var luma = [Double](repeating: 0, count: n)
        for i in 0..<n {
            luma[i] = ExposureConstants.lumaR * Double(grid.pixels[i * 3])
                + ExposureConstants.lumaG * Double(grid.pixels[i * 3 + 1])
                + ExposureConstants.lumaB * Double(grid.pixels[i * 3 + 2])
        }
        let lum = texturedCells(luma, width: grid.width, height: grid.height)
        let clip = ExposureConstants.texturalRangeClip
        return abs(percentile(lum, 100 - clip) - percentile(lum, clip))
    }

    public static func measureShadowPointFromLog(
        _ imgLog: LinearRGBBuffer,
        bounds: LogNegativeBounds,
        analysisBuffer: Float = 0
    ) -> Double {
        let lum = texturedNormLuma(prefiltered(imgLog, analysisBuffer: analysisBuffer), bounds: bounds)
        return percentile(lum, ExposureConstants.shadowReachPercentile)
    }

    public static func measureHighlightPointFromLog(
        _ imgLog: LinearRGBBuffer,
        bounds: LogNegativeBounds,
        analysisBuffer: Float = 0
    ) -> Double {
        let lum = texturedNormLuma(prefiltered(imgLog, analysisBuffer: analysisBuffer), bounds: bounds)
        return percentile(lum, ExposureConstants.highlightHoldPercentile)
    }

    static func texturedNormLuma(_ grid: LinearRGBBuffer, bounds: LogNegativeBounds) -> [Double] {
        let n = grid.width * grid.height
        var luma = [Double](repeating: 0, count: n)
        let eps = 1e-6
        for i in 0..<n {
            func norm(_ v: Double, _ f: Double, _ c: Double) -> Double {
                var denom = c - f
                if abs(denom) < eps {
                    denom = denom >= 0 ? eps : -eps
                }
                return (v - f) / denom
            }
            let r = norm(Double(grid.pixels[i * 3]), bounds.floors.0, bounds.ceils.0)
            let g = norm(Double(grid.pixels[i * 3 + 1]), bounds.floors.1, bounds.ceils.1)
            let b = norm(Double(grid.pixels[i * 3 + 2]), bounds.floors.2, bounds.ceils.2)
            luma[i] = ExposureConstants.lumaR * r + ExposureConstants.lumaG * g + ExposureConstants.lumaB * b
        }
        return texturedCells(luma, width: grid.width, height: grid.height)
    }

    /// Sectors of 2×2 `activity_block` cells (Boyack & Juenger). Falls back to every cell.
    static func texturedCells(_ lum: [Double], width: Int, height: Int) -> [Double] {
        let b = ExposureConstants.activityBlock
        let hs = (height / (2 * b)) * 2 * b
        let ws = (width / (2 * b)) * 2 * b
        if hs == 0 || ws == 0 {
            return lum
        }
        let blocksY = hs / b
        let blocksX = ws / b
        var blockMean = [Double](repeating: 0, count: blocksY * blocksX)
        let inv = 1.0 / Double(b * b)
        for by in 0..<blocksY {
            for bx in 0..<blocksX {
                var sum = 0.0
                for dy in 0..<b {
                    let row = (by * b + dy) * width
                    for dx in 0..<b {
                        sum += lum[row + bx * b + dx]
                    }
                }
                blockMean[by * blocksX + bx] = sum * inv
            }
        }
        let sectorsY = blocksY / 2
        let sectorsX = blocksX / 2
        var active = [Bool](repeating: false, count: sectorsY * sectorsX)
        var activeCount = 0
        for sy in 0..<sectorsY {
            for sx in 0..<sectorsX {
                let i00 = (sy * 2) * blocksX + sx * 2
                let i01 = i00 + 1
                let i10 = i00 + blocksX
                let i11 = i10 + 1
                let mx = max(blockMean[i00], max(blockMean[i01], max(blockMean[i10], blockMean[i11])))
                let mn = min(blockMean[i00], min(blockMean[i01], min(blockMean[i10], blockMean[i11])))
                let on = (mx - mn) > ExposureConstants.activityGateDensity
                active[sy * sectorsX + sx] = on
                if on { activeCount += 1 }
            }
        }
        if Double(activeCount) / Double(active.count) < ExposureConstants.activityMinFraction {
            return lum
        }
        var out: [Double] = []
        out.reserveCapacity(hs * ws)
        let span = 2 * b
        for y in 0..<hs {
            let sy = y / span
            let row = y * width
            for x in 0..<ws {
                if active[sy * sectorsX + x / span] {
                    out.append(lum[row + x])
                }
            }
        }
        return out
    }

    private static func prefiltered(_ imgLog: LinearRGBBuffer, analysisBuffer: Float) -> LinearRGBBuffer {
        var log = imgLog
        if analysisBuffer > 0 {
            log = log.analysisCenterCrop(bufferRatio: analysisBuffer)
        }
        return LogNormalization.blockMedianGrid(log)
    }

    private static func percentile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        return LogNormalization.percentileFromSorted(values.sorted(), q: q)
    }
}
