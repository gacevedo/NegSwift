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

        var offManual = PrintConfig.s4aPin
        offManual.dustRemove = false
        var onManual = PrintConfig.s4aPin
        onManual.dustRemove = true
        onManual.dustThreshold = 0.66
        onManual.dustSize = 4
        let c = try pipeline.renderPrint(path: url.path, longEdgePx: nil, processMode: .colorNegative, config: offManual)
        let d = try pipeline.renderPrint(path: url.path, longEdgePx: nil, processMode: .colorNegative, config: onManual)
        #expect(speckMean(d, width: c.width) < speckMean(c, width: c.width))
    }

    @Test func detectBarIsMonotonic() {
        #expect(OpticalDust.detectBar(0) < OpticalDust.detectBar(0.5))
        #expect(OpticalDust.detectBar(0.5) < OpticalDust.detectBar(1))
    }

    @Test func detectCoversTheSpeckFootprint() {
        var pixels = [Float](repeating: 0.18, count: 160 * 160 * 3)
        stampSpeck(&pixels, width: 160, x0: 80, y0: 80, size: 7, level: 0.005)
        let image = LinearRGBBuffer(width: 160, height: 160, pixels: pixels)
        let found = OpticalDust.detect(image, threshold: 0.66, size: 4)
        guard let score = found.score else {
            Issue.record("expected a speck score")
            return
        }
        var marked = 0
        for y in 80..<87 {
            for x in 80..<87 where score[y * 160 + x] < HealInpaint.writeHi {
                marked += 1
            }
        }
        #expect(Double(marked) / 49 >= 0.9)
    }

    @Test func detectJoinsAHairIntoOneComponent() {
        var pixels = grainy(width: 200, height: 200, level: 0.18, sigma: 0.02, seed: 42)
        for y in 100..<102 {
            for x in 40..<120 {
                let i = (y * 200 + x) * 3
                pixels[i] = 0.02
                pixels[i + 1] = 0.02
                pixels[i + 2] = 0.02
            }
        }
        let image = LinearRGBBuffer(width: 200, height: 200, pixels: pixels)
        let found = OpticalDust.detect(image, threshold: 0.66, size: 4)
        guard let hair = found.hair else {
            Issue.record("expected an 80 px hair")
            return
        }
        var covered = 0
        for y in 100..<102 {
            for x in 45..<115 where hair[y * 200 + x] != 0 {
                covered += 1
            }
        }
        #expect(covered == 2 * 70)
        if let score = found.score {
            for y in 100..<102 {
                for x in 40..<120 {
                    #expect(score[y * 200 + x] >= 1)
                }
            }
        }
    }

    @Test func textureProtectsACompactMarkButNotAHair() {
        var pixels = grainy(width: 200, height: 200, level: 0.18, sigma: 0.02, seed: 42)
        var rng = DustSplitMix64(seed: 5)
        for by in 0..<25 {
            for bx in 0..<13 {
                let gain = 0.85 + rng.nextUnit() * (1.18 - 0.85)
                for dy in 0..<8 {
                    for dx in 0..<8 {
                        let x = 100 + bx * 8 + dx
                        let y = by * 8 + dy
                        if x >= 200 || y >= 200 { continue }
                        let i = (y * 200 + x) * 3
                        pixels[i] *= gain
                        pixels[i + 1] *= gain
                        pixels[i + 2] *= gain
                    }
                }
            }
        }
        stampSpeck(&pixels, width: 200, x0: 40, y0: 60, size: 5, level: 0.05)
        stampSpeck(&pixels, width: 200, x0: 150, y0: 60, size: 5, level: 0.05)
        for y in 140..<142 {
            for x in 110..<190 {
                let i = (y * 200 + x) * 3
                pixels[i] = 0.005
                pixels[i + 1] = 0.005
                pixels[i + 2] = 0.005
            }
        }
        let image = LinearRGBBuffer(width: 200, height: 200, pixels: pixels)
        let mark = markedPlane(image, threshold: 0.66)
        #expect(markedIn(image, threshold: 0.66, x0: 40, y0: 60, size: 5))
        #expect(!markedIn(image, threshold: 0.66, x0: 145, y0: 55, size: 15))
        var hairHits = 0
        var hairN = 0
        for y in 140..<142 {
            for x in 120..<180 {
                hairN += 1
                if mark[y * 200 + x] { hairHits += 1 }
            }
        }
        #expect(Double(hairHits) / Double(hairN) > 0.8)
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

private func markedPlane(_ image: LinearRGBBuffer, threshold: Float) -> [Bool] {
    let found = OpticalDust.detect(image, threshold: threshold, size: 4)
    var mark = [Bool](repeating: false, count: image.width * image.height)
    if let score = found.score {
        for i in 0..<score.count where score[i] < HealInpaint.writeHi {
            mark[i] = true
        }
    }
    if let hair = found.hair {
        for i in 0..<hair.count where hair[i] != 0 {
            mark[i] = true
        }
    }
    return mark
}

private func markedIn(_ image: LinearRGBBuffer, threshold: Float, x0: Int, y0: Int, size: Int) -> Bool {
    let mark = markedPlane(image, threshold: threshold)
    for y in y0..<(y0 + size) {
        for x in x0..<(x0 + size) {
            if mark[y * image.width + x] { return true }
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

    mutating func nextUnit() -> Float {
        Float(next() >> 11) / Float(1 << 53)
    }

    mutating func nextGaussian() -> Float {
        let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
        let u2 = Double(next() >> 11) / Double(1 << 53)
        return Float(sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2))
    }
}
