import Foundation
import Testing
@testable import NegSwiftEngine

/// Ports of NegPy `test_luma_range_margin`, `test_color_luma_split`, and `test_same_pixel_bounds`.
struct NormalizationBoundsTests {
    @Test func zeroClipSamplesRobustExtremes() {
        let img = gradient(size: 100)
        let bounds = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0
        )
        let log = LogNormalization.toLogDensity(img)
        let sorted = (0..<3).map { ch in channel(log, ch).sorted() }
        for ch in 0..<3 {
            let floor = LogNormalization.percentileFromSorted(sorted[ch], q: LogNormalization.baseLumaClip)
            let ceil = LogNormalization.percentileFromSorted(sorted[ch], q: 100 - LogNormalization.baseLumaClip)
            #expect(abs(bounds.floor(ch) - floor) < 1e-4)
            #expect(abs(bounds.ceil(ch) - ceil) < 1e-4)
        }
    }

    @Test func negativeClipExpandsOutwardC41() {
        let img = gradient(size: 100)
        let base = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0
        )
        let ext = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: -0.5,
            colorRangeClip: 0
        )
        for ch in 0..<3 {
            #expect(abs(ext.floor(ch) - (base.floor(ch) - 0.5)) < 1e-5)
            #expect(abs(ext.ceil(ch) - (base.ceil(ch) + 0.5)) < 1e-5)
        }
    }

    @Test func positiveClipPullsBoundsInward() {
        let img = gradient(size: 100)
        let base = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0
        )
        let clipped = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 1,
            colorRangeClip: 0
        )
        for ch in 0..<3 {
            #expect(clipped.floor(ch) > base.floor(ch))
            #expect(clipped.ceil(ch) < base.ceil(ch))
        }
    }

    @Test func negativeClipExpandsOutwardE6() {
        let img = gradient(size: 100)
        let base = LogNormalization.analyzeBounds(
            linear: img,
            processMode: .transparency,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0
        )
        let ext = LogNormalization.analyzeBounds(
            linear: img,
            processMode: .transparency,
            analysisBuffer: 0,
            lumaRangeClip: -0.5,
            colorRangeClip: 0
        )
        for ch in 0..<3 {
            #expect(abs(ext.floor(ch) - (base.floor(ch) + 0.5)) < 1e-5)
            #expect(abs(ext.ceil(ch) - (base.ceil(ch) - 0.5)) < 1e-5)
        }
    }

    @Test func lumaDrivesMeanCenterAndSpan() {
        let img = offsetGradient()
        let a = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0.6,
            colorRangeClip: 5
        )
        let b = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0.6,
            colorRangeClip: 0.5
        )
        #expect(abs(mean3(a.floors) - mean3(b.floors)) < 1e-5)
        #expect(abs(mean3(a.ceils) - mean3(b.ceils)) < 1e-5)
        #expect(abs(mean3(a.ceils) - mean3(a.floors) - (mean3(b.ceils) - mean3(b.floors))) < 1e-5)
    }

    @Test func colorPassOrdersCastByChannelGain() {
        let bounds = LogNormalization.analyzeBounds(
            linear: offsetGradient(),
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 5
        )
        #expect(bounds.floors.1 < bounds.floors.2)
        #expect(bounds.floors.2 < bounds.floors.0)
    }

    @Test func monoImageHasNoCast() {
        let img = gradient(size: 100)
        let a = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0.3,
            colorRangeClip: 10
        )
        let b = LogNormalization.analyzeBounds(
            linear: img,
            analysisBuffer: 0,
            lumaRangeClip: 0.3,
            colorRangeClip: 0.01
        )
        for ch in 0..<3 {
            #expect(abs(a.floor(ch) - b.floor(ch)) < 1e-6)
            #expect(abs(a.ceil(ch) - b.ceil(ch)) < 1e-6)
            #expect(abs(a.floor(ch) - a.floors.0) < 1e-6)
        }
    }

    @Test func coloredDenseContentNoLongerReadsAsCast() {
        var log = densityRamp()
        let blockW = Int(0.08 * Double(log.width))
        for y in 0..<log.height {
            for x in 0..<blockW {
                setPixel(&log, x: x, y: y, r: Float(base.0 - 0.95), g: Float(base.1 - 0.20), b: Float(base.2 - 0.20))
            }
        }
        let bounds = analyzeLog(log)
        let newErr = maxAbsDev(dev(bounds.floors), dev(base))
        #expect(newErr < 0.02)

        let old = oldColorRecombined(log)
        let oldErr = maxAbsDev(dev((old.0[0], old.0[1], old.0[2])), dev(base))
        #expect(oldErr > 0.10)
    }

    @Test func neutralFrameMatchesPercentilePass() {
        let log = densityRamp()
        let bounds = analyzeLog(log)
        let old = oldColorRecombined(log)
        let got = dev(bounds.floors)
        let exp = dev((old.0[0], old.0[1], old.0[2]))
        #expect(maxAbsDev(got, exp) < 5e-3)
    }

    @Test func noNeutralDenseEndFallsBackBitExact() {
        var log = densityRamp()
        let dense = Int(0.90 * Double(log.height))
        for y in dense..<log.height {
            for x in 0..<log.width {
                let i = (y * log.width + x) * 3
                if x % 2 == 0 {
                    log.pixels[i] -= 0.65
                    log.pixels[i + 2] += 0.65
                } else {
                    log.pixels[i] += 0.65
                    log.pixels[i + 2] -= 0.65
                }
            }
        }
        let bounds = analyzeLog(log)
        let old = oldColorRecombined(log)
        for ch in 0..<3 {
            #expect(abs(bounds.floor(ch) - old.0[ch]) < 1e-9)
            #expect(abs(bounds.ceil(ch) - old.1[ch]) < 1e-9)
        }
    }

    @Test func e6GatedToPercentilePass() {
        var log = densityRamp()
        let blockW = Int(0.08 * Double(log.width))
        for y in 0..<log.height {
            for x in 0..<blockW {
                log.pixels[(y * log.width + x) * 3] = Float(base.0 - 0.95)
            }
        }
        let bounds = analyzeLog(log, mode: .transparency)
        let old = oldColorRecombined(log, mode: .transparency)
        for ch in 0..<3 {
            #expect(abs(bounds.floor(ch) - old.0[ch]) < 1e-9)
            #expect(abs(bounds.ceil(ch) - old.1[ch]) < 1e-9)
        }
    }

    @Test func thinEndStaysPercentileBased() {
        var log = densityRamp()
        let blockW = Int(0.08 * Double(log.width))
        for y in 0..<log.height {
            for x in 0..<blockW {
                log.pixels[(y * log.width + x) * 3] = Float(base.0 - 0.95)
            }
        }
        let bounds = analyzeLog(log)
        let old = oldColorRecombined(log)
        for ch in 0..<3 {
            #expect(abs(bounds.ceil(ch) - old.1[ch]) < 1e-9)
        }
    }

    private let base: (Double, Double, Double) = (-0.10, -0.22, -0.32)
    private let gamma = 0.7

    private func analyzeLog(_ log: LinearRGBBuffer, mode: FilmProcessMode = .colorNegative) -> LogNegativeBounds {
        LogNormalization.analyzeFromLogGrid(
            log,
            processMode: mode,
            lumaRangeClip: 0,
            colorRangeClip: 1,
            e6Normalize: true
        )
    }

    private func densityRamp() -> LinearRGBBuffer {
        let height = 400
        let width = 300
        var pixels = [Float](repeating: 0, count: width * height * 3)
        let denom = Double(height - 1)
        for y in 0..<height {
            let e = Double(y) / denom
            for x in 0..<width {
                let i = (y * width + x) * 3
                pixels[i] = Float(base.0 - gamma * e)
                pixels[i + 1] = Float(base.1 - gamma * e)
                pixels[i + 2] = Float(base.2 - gamma * e)
            }
        }
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    private func oldColorRecombined(
        _ imgLog: LinearRGBBuffer,
        mode: FilmProcessMode = .colorNegative
    ) -> ([Double], [Double]) {
        let n = imgLog.width * imgLog.height
        var sorted = [
            [Double](repeating: 0, count: n),
            [Double](repeating: 0, count: n),
            [Double](repeating: 0, count: n),
        ]
        for i in 0..<n {
            sorted[0][i] = Double(imgLog.pixels[i * 3])
            sorted[1][i] = Double(imgLog.pixels[i * 3 + 1])
            sorted[2][i] = Double(imgLog.pixels[i * 3 + 2])
        }
        for ch in 0..<3 { sorted[ch].sort() }

        func sample(clip: Double, baseClip: Double) -> ([Double], [Double]) {
            let c = min(50, max(0.00001, clip + baseClip))
            var pLow = c
            var pHigh = 100 - c
            if mode == .transparency {
                swap(&pLow, &pHigh)
            }
            let floors = (0..<3).map { LogNormalization.percentileFromSorted(sorted[$0], q: pLow) }
            let ceils = (0..<3).map { LogNormalization.percentileFromSorted(sorted[$0], q: pHigh) }
            return (floors, ceils)
        }

        let luma = sample(clip: 0, baseClip: LogNormalization.baseLumaClip)
        let color = sample(clip: 1, baseClip: 0)
        let meanLF = luma.0.reduce(0, +) / 3
        let meanLC = luma.1.reduce(0, +) / 3
        let meanCF = color.0.sorted()[1]
        let meanCC = color.1.sorted()[1]
        let floors = (0..<3).map { meanLF + (color.0[$0] - meanCF) }
        let ceils = (0..<3).map { meanLC + (color.1[$0] - meanCC) }
        return (floors, ceils)
    }

    private func gradient(size: Int) -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: size * size * 3)
        let n = size * size
        for i in 0..<n {
            let t = Float(i) / Float(n - 1)
            let v = 0.01 + 0.99 * t
            pixels[i * 3] = v
            pixels[i * 3 + 1] = v
            pixels[i * 3 + 2] = v
        }
        return LinearRGBBuffer(width: size, height: size, pixels: pixels)
    }

    private func offsetGradient() -> LinearRGBBuffer {
        var pixels = [Float](repeating: 0, count: 100 * 100 * 3)
        for i in 0..<(100 * 100) {
            let v = 0.02 + 0.98 * Float(i) / Float(100 * 100 - 1)
            pixels[i * 3] = v
            pixels[i * 3 + 1] = v * 0.7
            pixels[i * 3 + 2] = v * 0.85
        }
        return LinearRGBBuffer(width: 100, height: 100, pixels: pixels)
    }

    private func channel(_ buffer: LinearRGBBuffer, _ ch: Int) -> [Double] {
        let n = buffer.width * buffer.height
        return (0..<n).map { Double(buffer.pixels[$0 * 3 + ch]) }
    }

    private func mean3(_ t: (Double, Double, Double)) -> Double {
        (t.0 + t.1 + t.2) / 3
    }

    private func dev(_ t: (Double, Double, Double)) -> (Double, Double, Double) {
        let m = mean3(t)
        return (t.0 - m, t.1 - m, t.2 - m)
    }

    private func maxAbsDev(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }

    private func setPixel(_ buffer: inout LinearRGBBuffer, x: Int, y: Int, r: Float, g: Float, b: Float) {
        let i = (y * buffer.width + x) * 3
        buffer.pixels[i] = r
        buffer.pixels[i + 1] = g
        buffer.pixels[i + 2] = b
    }
}
