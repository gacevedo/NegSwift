import Foundation
import Testing
@testable import NegSwiftEngine

struct OpticalDustTests {
    @Test func detectFindsDarkSpeck() {
        let image = dustySource(width: 160, height: 160)
        let found = OpticalDust.detect(image, threshold: 0.66, size: 4)
        #expect(found.hair == nil)
        guard let score = found.score else {
            Issue.record("expected a speck score")
            return
        }
        var speckMax: Float = 0
        var xs: [Double] = []
        var ys: [Double] = []
        for y in 0..<160 {
            for x in 0..<160 {
                let s = score[y * 160 + x]
                if y >= 80, y < 83, x >= 80, x < 83 {
                    speckMax = max(speckMax, s)
                }
                if s < 1 {
                    xs.append(Double(x))
                    ys.append(Double(y))
                }
            }
        }
        #expect(speckMax < 1)
        #expect(!xs.isEmpty)
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        #expect(abs(mx - 81.5) < 5)
        #expect(abs(my - 81.5) < 5)
    }

    @Test func detectIsExposureInvariant() {
        let image = dustySource(width: 160, height: 160, grain: false)
        let a = OpticalDust.detect(image, threshold: 0.66, size: 4).score
        let bright = scale(image, 4)
        let b = OpticalDust.detect(bright, threshold: 0.66, size: 4).score
        #expect(a != nil && b != nil)
        #expect(a == b)
    }

    @Test func cleanFrameIsEmpty() {
        let image = LinearRGBBuffer(
            width: 160,
            height: 160,
            pixels: grainy(width: 160, height: 160, level: 0.18, sigma: 0.02, seed: 9)
        )
        let found = OpticalDust.detect(image, threshold: 0.66, size: 4)
        #expect(found.score == nil)
        #expect(found.hair == nil)
    }

    @Test func detectedSpeckRepairs() {
        let image = dustySource(width: 160, height: 160, grain: false)
        let out = OpticalDust.bake(image, threshold: 0.66, size: 4)
        var mean: Float = 0
        var n: Float = 0
        for y in 80..<83 {
            for x in 80..<83 {
                let i = (y * 160 + x) * 3
                mean += out.pixels[i]
                n += 1
            }
        }
        mean /= n
        #expect(mean > 0.1)
    }

    @Test func dustOffLeavesConfigDefault() {
        let image = dustySource(width: 160, height: 160)
        #expect(OpticalDust.bake(image, threshold: 0.66, size: 4).pixels != image.pixels)
        #expect(PrintConfig.s8Pin.dustRemove == false)
    }

    @Test func mergingReadsDustKeys() {
        let merged = PrintConfig.s8Pin.merging([
            "dust_remove": true,
            "dust_threshold": 0.55,
            "dust_size": 5,
        ])
        #expect(merged.dustRemove == true)
        #expect(abs(merged.dustThreshold - 0.55) < 1e-5)
        #expect(merged.dustSize == 5)
    }

    @Test func lowerThresholdMarksMore() {
        var pixels = grainy(width: 200, height: 200, level: 0.18, sigma: 0.02, seed: 42)
        stampSpeck(&pixels, width: 200, x0: 100, y0: 40, size: 3, level: 0.005)
        stampSpeck(&pixels, width: 200, x0: 100, y0: 100, size: 3, level: 0.06)
        stampSpeck(&pixels, width: 200, x0: 100, y0: 160, size: 3, level: 0.11)
        let image = LinearRGBBuffer(width: 200, height: 200, pixels: pixels)
        let loose = markedCount(image, threshold: 0.3)
        let mid = markedCount(image, threshold: 0.66)
        let tight = markedCount(image, threshold: 0.9)
        #expect(loose >= mid)
        #expect(mid >= tight)
        #expect(tight > 0)
        #expect(markedIn(image, threshold: 0.9, x0: 100, y0: 40, size: 3))
    }

    @Test func pipelineDustToggleChangesPixels() throws {
        let w = 160
        let h = 160
        var samples = [UInt16](repeating: 12_000, count: w * h * 3)
        for y in 80..<83 {
            for x in 80..<83 {
                let i = (y * w + x) * 3
                samples[i] = 300
                samples[i + 1] = 300
                samples[i + 2] = 300
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s10b-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: w, height: h, samples: samples, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = NativePipeline()
        let linear = try pipeline.decode(path: url.path)
        let baked = OpticalDust.bake(linear, threshold: 0.66, size: 4)
        #expect(speckMean(baked, width: w) > speckMean(linear, width: w))

        var off = PrintConfig.s8Pin
        off.dustRemove = false
        var on = PrintConfig.s8Pin
        on.dustRemove = true
        on.dustThreshold = 0.66
        on.dustSize = 4
        let a = try pipeline.renderPrint(path: url.path, longEdgePx: nil, processMode: .colorNegative, config: off)
        let b = try pipeline.renderPrint(path: url.path, longEdgePx: nil, processMode: .colorNegative, config: on)
        #expect(speckMean(b, width: a.width) != speckMean(a, width: a.width))
    }

    @Test func hairInpaintLeavesOutsideUntouched() {
        let w = 60
        let h = 60
        var pixels = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let v = 0.2 + 0.6 * Float(x) / Float(w - 1)
                let i = (y * w + x) * 3
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            }
        }
        let clean = LinearRGBBuffer(width: w, height: h, pixels: pixels)
        for y in 10..<50 {
            let i = (y * w + 30) * 3
            pixels[i] = 0.95
            pixels[i + 1] = 0.95
            pixels[i + 2] = 0.95
        }
        let hair = LinearRGBBuffer(width: w, height: h, pixels: pixels)
        var mask = [UInt8](repeating: 0, count: w * h)
        for y in 10..<50 {
            mask[y * w + 30] = 1
        }
        let out = OpticalDust.inpaintHair(hair, mask: mask)
        for y in 0..<h {
            for x in 0..<w {
                if mask[y * w + x] != 0 { continue }
                let i = (y * w + x) * 3
                #expect(out.pixels[i] == hair.pixels[i])
            }
        }
        let mid = 30 * w + 30
        #expect(abs(out.pixels[mid * 3] - clean.pixels[mid * 3]) < 0.05)
    }
}

private func dustySource(width: Int, height: Int, grain: Bool = true) -> LinearRGBBuffer {
    var pixels: [Float]
    if grain {
        pixels = grainy(width: width, height: height, level: 0.18, sigma: 0.02, seed: 42)
    } else {
        pixels = [Float](repeating: 0.18, count: width * height * 3)
    }
    stampSpeck(&pixels, width: width, x0: width / 2, y0: height / 2, size: 3, level: 0.005)
    return LinearRGBBuffer(width: width, height: height, pixels: pixels)
}

private func stampSpeck(_ pixels: inout [Float], width: Int, x0: Int, y0: Int, size: Int, level: Float) {
    for y in y0..<(y0 + size) {
        for x in x0..<(x0 + size) {
            let i = (y * width + x) * 3
            pixels[i] = level
            pixels[i + 1] = level
            pixels[i + 2] = level
        }
    }
}

private func scale(_ image: LinearRGBBuffer, _ gain: Float) -> LinearRGBBuffer {
    LinearRGBBuffer(width: image.width, height: image.height, pixels: image.pixels.map { $0 * gain })
}

private func markedCount(_ image: LinearRGBBuffer, threshold: Float) -> Int {
    let found = OpticalDust.detect(image, threshold: threshold, size: 4)
    guard let score = found.score else { return 0 }
    return score.filter { $0 < HealInpaint.writeHi }.count
}

private func speckMean(_ image: LinearRGBBuffer, width: Int, x0: Int = 80, y0: Int = 80, size: Int = 3) -> Float {
    var sum: Float = 0
    var n: Float = 0
    for y in y0..<(y0 + size) {
        for x in x0..<(x0 + size) {
            let i = (y * width + x) * 3
            sum += image.pixels[i]
            n += 1
        }
    }
    return sum / max(n, 1)
}

private func markedIn(_ image: LinearRGBBuffer, threshold: Float, x0: Int, y0: Int, size: Int) -> Bool {
    let found = OpticalDust.detect(image, threshold: threshold, size: 4)
    guard let score = found.score else { return false }
    for y in y0..<(y0 + size) {
        for x in x0..<(x0 + size) {
            if score[y * image.width + x] < HealInpaint.writeHi { return true }
        }
    }
    return false
}

private func grainy(width: Int, height: Int, level: Float, sigma: Float, seed: UInt64) -> [Float] {
    var rng = DustSplitMix64(seed: seed)
    var pixels = [Float](repeating: level, count: width * height * 3)
    for i in 0..<pixels.count {
        pixels[i] = level + rng.nextGaussian() * sigma
    }
    return pixels
}

private struct DustSplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextGaussian() -> Float {
        let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
        let u2 = Double(next() >> 11) / Double(1 << 53)
        return Float(sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2))
    }
}
