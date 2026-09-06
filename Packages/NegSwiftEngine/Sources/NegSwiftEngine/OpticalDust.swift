import Foundation

/// Optical (visible-scan) dust: Vendor NegPy `_detect_dust_mask_jit` + score fill.
/// Preview-res first. Hair uses nearest-clean copy, not OpenCV Navier–Stokes.
public enum OpticalDust: Sendable {
    public static let defaultThreshold: Float = 0.66
    public static let defaultSize: Int = 4
    public static let proxyMinSpread: Float = 0.8
    public static let detectPadPx: Float = 2.5
    public static let proxyMin: Float = 0.15
    public static let localStdFloor: Float = 0.005
    public static let textureKnee: Float = 0.02
    public static let textureCubicGain: Float = 800
    public static let peakZ: Float = 3
    public static let strongThreshMul: Float = 2.5
    public static let strongExcess: Float = 0.25
    public static let hairMinArea: Int = 20
    public static let hairMinElong: Float = 8
    public static let detectLongEdge: Int = 1600
    public static let hairDilatePx: Int = 1

    public struct Detection: Sendable {
        public var score: [Float]?
        public var hair: [UInt8]?
        public var detectWidth: Int
        public var detectHeight: Int
    }

    public static func bake(
        _ image: LinearRGBBuffer,
        threshold: Float = defaultThreshold,
        size: Int = defaultSize
    ) -> LinearRGBBuffer {
        let found = detect(image, threshold: threshold, size: size)
        var out = image
        if let score = upsampleScore(found, width: image.width, height: image.height) {
            let factor = upsampleFactor(found, width: image.width, height: image.height)
            out = HealInpaint.applyScoreRepair(out, score: score, floor: true, factor: factor)
        }
        if let hair = upsampleMask(found.hair, fromWidth: found.detectWidth, fromHeight: found.detectHeight, width: image.width, height: image.height) {
            out = inpaintHair(out, mask: dilate(hair, width: image.width, height: image.height, radius: hairDilatePx))
        }
        return out
    }

    public static func detect(
        _ image: LinearRGBBuffer,
        threshold: Float = defaultThreshold,
        size: Int = defaultSize
    ) -> Detection {
        let small = detectionDownsample(image)
        let stats = computeStats(small, dustSize: size)
        return detectFromStats(stats, threshold: threshold, width: small.width, height: small.height)
    }

    public static func computeStats(_ image: LinearRGBBuffer, dustSize: Int) -> (proxy: [Float], mean: [Float], std: [Float], wStd: [Float]) {
        let dens = densityPlane(image)
        let (lo, spread) = proxyNorm(dens)
        var proxy = [Float](repeating: 0, count: dens.count)
        for i in 0..<dens.count {
            proxy[i] = min(max((dens[i] - lo) / spread, 0), 1)
        }
        let base = max(1, Float(dustSize))
        let vWin = (Int(max(3, base * 3)) * 2) + 1
        let wWin = (Int(max(7, base * 4)) * 2) + 1
        let (mean, std) = boxMeanStd(proxy, width: image.width, height: image.height, win: vWin)
        let (_, wStd) = boxMeanStd(proxy, width: image.width, height: image.height, win: wWin)
        return (proxy, mean, std, wStd)
    }

    public static func detectFromStats(
        _ stats: (proxy: [Float], mean: [Float], std: [Float], wStd: [Float]),
        threshold: Float,
        width: Int,
        height: Int
    ) -> Detection {
        let hit = detectMask(
            proxy: stats.proxy,
            mean: stats.mean,
            std: stats.std,
            wStd: stats.wStd,
            threshold: threshold,
            width: width,
            height: height
        )
        if !hit.contains(where: { $0 != 0 }) {
            return Detection(score: nil, hair: nil, detectWidth: width, detectHeight: height)
        }
        let (compact, hair) = splitHairs(hit, width: width, height: height)
        let score: [Float]?
        if compact.contains(where: { $0 != 0 }) {
            score = HealInpaint.maskToScore(compact, width: width, height: height, padPx: detectPadPx)
        } else {
            score = nil
        }
        return Detection(score: score, hair: hair, detectWidth: width, detectHeight: height)
    }

    /// Vendor `_detect_dust_mask_jit`: local-contrast peaks on the density proxy.
    @_optimize(speed)
    public static func detectMask(
        proxy: [Float],
        mean: [Float],
        std: [Float],
        wStd: [Float],
        threshold: Float,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var hit = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let lCurr = proxy[i]
                let lMean = mean[i]
                let localS = max(localStdFloor, std[i])
                let wS = max(0, wStd[i] - textureKnee)
                let widePenalty = (wS * wS * wS) * textureCubicGain
                let thresh = (threshold * 0.4) + localS + widePenalty
                let excess = lCurr - lMean
                if excess > thresh, lCurr > proxyMin, excess / localS > peakZ {
                    let isStrong = excess > (thresh * strongThreshMul) || excess > strongExcess
                    if y > 0, y < height - 1, x > 0, x < width - 1 {
                        var isMax = true
                        dyLoop: for dy in -1...1 {
                            for dx in -1...1 {
                                if dx == 0, dy == 0 { continue }
                                if proxy[(y + dy) * width + (x + dx)] >= lCurr {
                                    isMax = false
                                    break dyLoop
                                }
                            }
                        }
                        if isMax || isStrong {
                            hit[i] = 1
                        }
                    } else {
                        hit[i] = 1
                    }
                }
            }
        }
        return hit
    }

    static func splitHairs(_ mask: [UInt8], width: Int, height: Int) -> (compact: [UInt8], hair: [UInt8]?) {
        let labeled = labeledComponents(mask, width: width, height: height)
        var compact = [UInt8](repeating: 0, count: mask.count)
        var hair = [UInt8](repeating: 0, count: mask.count)
        var hasHair = false
        for comp in labeled.components {
            var sub = [UInt8](repeating: 0, count: comp.width * comp.height)
            for y in 0..<comp.height {
                for x in 0..<comp.width {
                    let gi = (comp.y0 + y) * width + (comp.x0 + x)
                    if labeled.label[gi] == comp.id {
                        sub[y * comp.width + x] = 1
                    }
                }
            }
            if isHair(sub, width: comp.width, height: comp.height, area: comp.area) {
                hasHair = true
                for y in 0..<comp.height {
                    for x in 0..<comp.width {
                        if sub[y * comp.width + x] != 0 {
                            hair[(comp.y0 + y) * width + (comp.x0 + x)] = 1
                        }
                    }
                }
            } else {
                for y in 0..<comp.height {
                    for x in 0..<comp.width {
                        if sub[y * comp.width + x] != 0 {
                            compact[(comp.y0 + y) * width + (comp.x0 + x)] = 1
                        }
                    }
                }
            }
        }
        return (compact, hasHair ? hair : nil)
    }

    static func isHair(_ labelsSub: [UInt8], width: Int, height: Int, area: Int) -> Bool {
        if area < hairMinArea { return false }
        let pw = width + 2
        let ph = height + 2
        var padded = [UInt8](repeating: 0, count: pw * ph)
        for y in 0..<height {
            for x in 0..<width {
                padded[(y + 1) * pw + (x + 1)] = labelsSub[y * width + x]
            }
        }
        let dist = HealInpaint.distanceTransform(padded, width: pw, height: ph)
        var maxD: Float = 0
        for y in 0..<ph {
            for x in 0..<pw {
                if padded[y * pw + x] != 0 {
                    maxD = max(maxD, dist[y * pw + x])
                }
            }
        }
        let thickness = 2 * maxD
        return Float(area) / max(thickness * thickness, 1e-6) >= hairMinElong
    }

    static func detectionDownsample(_ image: LinearRGBBuffer) -> LinearRGBBuffer {
        let long = max(image.width, image.height)
        if long <= detectLongEdge { return image }
        let scale = Float(detectLongEdge) / Float(long)
        let nw = max(1, Int((Float(image.width) * scale).rounded()))
        let nh = max(1, Int((Float(image.height) * scale).rounded()))
        var out = [Float](repeating: 0, count: nw * nh * 3)
        for y in 0..<nh {
            let y0 = y * image.height / nh
            let y1 = max(y0 + 1, (y + 1) * image.height / nh)
            for x in 0..<nw {
                let x0 = x * image.width / nw
                let x1 = max(x0 + 1, (x + 1) * image.width / nw)
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0
                var n: Float = 0
                for sy in y0..<y1 {
                    for sx in x0..<x1 {
                        let i = (sy * image.width + sx) * 3
                        r += image.pixels[i]
                        g += image.pixels[i + 1]
                        b += image.pixels[i + 2]
                        n += 1
                    }
                }
                let di = (y * nw + x) * 3
                let inv = 1 / max(n, 1)
                out[di] = r * inv
                out[di + 1] = g * inv
                out[di + 2] = b * inv
            }
        }
        return LinearRGBBuffer(width: nw, height: nh, pixels: out)
    }

    static func upsampleScore(_ found: Detection, width: Int, height: Int) -> [Float]? {
        guard let score = found.score else { return nil }
        if found.detectWidth == width, found.detectHeight == height { return score }
        return bilinear(score, sw: found.detectWidth, sh: found.detectHeight, dw: width, dh: height)
    }

    static func upsampleFactor(_ found: Detection, width: Int, height: Int) -> Float {
        if found.detectWidth == width, found.detectHeight == height { return 1 }
        return max(Float(height) / Float(found.detectHeight), Float(width) / Float(found.detectWidth))
    }

    static func upsampleMask(_ mask: [UInt8]?, fromWidth: Int, fromHeight: Int, width: Int, height: Int) -> [UInt8]? {
        guard let mask else { return nil }
        if fromWidth == width, fromHeight == height { return mask }
        let plane = mask.map { Float($0) }
        let up = bilinear(plane, sw: fromWidth, sh: fromHeight, dw: width, dh: height)
        return up.map { $0 > 0.5 ? 1 : 0 }
    }

    /// Preview-res hair fill: copy the nearest clean pixel. Non-masked stays identical.
    static func inpaintHair(_ image: LinearRGBBuffer, mask: [UInt8]) -> LinearRGBBuffer {
        if !mask.contains(where: { $0 != 0 }) { return image }
        let w = image.width
        let h = image.height
        let nearest = nearestClean(mask, width: w, height: h)
        var out = image.pixels
        for i in 0..<mask.count where mask[i] != 0 {
            let src = nearest[i]
            out[i * 3] = image.pixels[src * 3]
            out[i * 3 + 1] = image.pixels[src * 3 + 1]
            out[i * 3 + 2] = image.pixels[src * 3 + 2]
        }
        return LinearRGBBuffer(width: w, height: h, pixels: out)
    }

    static func dilate(_ mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        if radius <= 0 { return mask }
        let r2 = radius * radius
        var out = mask
        for y in 0..<height {
            for x in 0..<width {
                if mask[y * width + x] == 0 { continue }
                let y0 = max(0, y - radius)
                let y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                for yy in y0...y1 {
                    for xx in x0...x1 {
                        let dx = xx - x
                        let dy = yy - y
                        if dx * dx + dy * dy <= r2 {
                            out[yy * width + xx] = 1
                        }
                    }
                }
            }
        }
        return out
    }

    static func densityPlane(_ image: LinearRGBBuffer) -> [Float] {
        let n = image.width * image.height
        var dens = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let r = image.pixels[i * 3]
            let g = image.pixels[i * 3 + 1]
            let b = image.pixels[i * 3 + 2]
            let luma = max(HealInpaint.lumaR * r + HealInpaint.lumaG * g + HealInpaint.lumaB * b, 1e-6)
            dens[i] = -log10(luma)
        }
        return dens
    }

    static func proxyNorm(_ dens: [Float]) -> (Float, Float) {
        let lo = percentile(dens, 0.5)
        let hi = percentile(dens, 99.5)
        return (lo, max(hi - lo, proxyMinSpread))
    }

    static func percentile(_ values: [Float], _ p: Double) -> Float {
        if values.isEmpty { return 0 }
        var sorted = values
        sorted.sort()
        let n = Double(sorted.count)
        let idx = (n - 1) * (p / 100)
        let lo = Int(idx)
        let hi = min(lo + 1, sorted.count - 1)
        let t = Float(idx - Double(lo))
        return sorted[lo] * (1 - t) + sorted[hi] * t
    }

    static func boxMeanStd(_ plane: [Float], width: Int, height: Int, win: Int) -> ([Float], [Float]) {
        let mean = HealInpaint.boxBlur(plane, width: width, height: height, ksize: win)
        var sq = [Float](repeating: 0, count: plane.count)
        for i in 0..<plane.count {
            sq[i] = plane[i] * plane[i]
        }
        let meanSq = HealInpaint.boxBlur(sq, width: width, height: height, ksize: win)
        var std = [Float](repeating: 0, count: plane.count)
        for i in 0..<plane.count {
            std[i] = sqrt(max(meanSq[i] - mean[i] * mean[i], 0))
        }
        return (mean, std)
    }

    static func bilinear(_ src: [Float], sw: Int, sh: Int, dw: Int, dh: Int) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh)
        let sxScale = Float(sw) / Float(dw)
        let syScale = Float(sh) / Float(dh)
        for y in 0..<dh {
            let fy = (Float(y) + 0.5) * syScale - 0.5
            let y0 = min(max(Int(floor(fy)), 0), sh - 1)
            let y1 = min(y0 + 1, sh - 1)
            let ty = fy - Float(y0)
            for x in 0..<dw {
                let fx = (Float(x) + 0.5) * sxScale - 0.5
                let x0 = min(max(Int(floor(fx)), 0), sw - 1)
                let x1 = min(x0 + 1, sw - 1)
                let tx = fx - Float(x0)
                let v00 = src[y0 * sw + x0]
                let v01 = src[y0 * sw + x1]
                let v10 = src[y1 * sw + x0]
                let v11 = src[y1 * sw + x1]
                let v0 = v00 + (v01 - v00) * tx
                let v1 = v10 + (v11 - v10) * tx
                out[y * dw + x] = v0 + (v1 - v0) * ty
            }
        }
        return out
    }

    private struct Component {
        var id: Int
        var area: Int
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
    }

    private struct Labeled {
        var label: [Int]
        var components: [Component]
    }

    private static func labeledComponents(_ mask: [UInt8], width: Int, height: Int) -> Labeled {
        let n = width * height
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func join(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if mask[i] == 0 { continue }
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0, dy == 0 { continue }
                        let nx = x + dx
                        let ny = y + dy
                        if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                        let j = ny * width + nx
                        if mask[j] != 0 {
                            join(i, j)
                        }
                    }
                }
            }
        }
        var roots: [Int: Component] = [:]
        var label = [Int](repeating: 0, count: n)
        var nextID = 1
        var idByRoot: [Int: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if mask[i] == 0 { continue }
                let r = find(i)
                if idByRoot[r] == nil {
                    idByRoot[r] = nextID
                    roots[nextID] = Component(id: nextID, area: 0, x0: x, y0: y, x1: x + 1, y1: y + 1)
                    nextID += 1
                }
                let id = idByRoot[r]!
                label[i] = id
                var c = roots[id]!
                c.area += 1
                c.x0 = min(c.x0, x)
                c.y0 = min(c.y0, y)
                c.x1 = max(c.x1, x + 1)
                c.y1 = max(c.y1, y + 1)
                roots[id] = c
            }
        }
        return Labeled(label: label, components: roots.values.sorted { $0.id < $1.id })
    }

    /// Two-pass chamfer that also stores the nearest clean (mask==0) pixel index.
    static func nearestClean(_ mask: [UInt8], width: Int, height: Int) -> [Int] {
        let inf: Float = 1e6
        let diag: Float = sqrt(2)
        var d = [Float](repeating: inf, count: width * height)
        var src = Array(0..<(width * height))
        for i in 0..<mask.count where mask[i] == 0 {
            d[i] = 0
            src[i] = i
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var v = d[i]
                var s = src[i]
                func consider(_ j: Int, _ add: Float) {
                    let cand = d[j] + add
                    if cand < v {
                        v = cand
                        s = src[j]
                    }
                }
                if y > 0 { consider((y - 1) * width + x, 1) }
                if x > 0 { consider(y * width + (x - 1), 1) }
                if y > 0, x > 0 { consider((y - 1) * width + (x - 1), diag) }
                if y > 0, x + 1 < width { consider((y - 1) * width + (x + 1), diag) }
                d[i] = v
                src[i] = s
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                var v = d[i]
                var s = src[i]
                func consider(_ j: Int, _ add: Float) {
                    let cand = d[j] + add
                    if cand < v {
                        v = cand
                        s = src[j]
                    }
                }
                if y + 1 < height { consider((y + 1) * width + x, 1) }
                if x + 1 < width { consider(y * width + (x + 1), 1) }
                if y + 1 < height, x + 1 < width { consider((y + 1) * width + (x + 1), diag) }
                if y + 1 < height, x > 0 { consider((y + 1) * width + (x - 1), diag) }
                d[i] = v
                src[i] = s
            }
        }
        return src
    }
}
