import Foundation

/// Preview-res painted heal: `strokes_to_score` + score-weighted fill, baked on
/// decoded linear **before** geometry. Navier–Stokes hair inpaint is S10b / later.
public enum HealInpaint: Sendable {
    public static let healSizeRef: Float = 1600
    public static let detectRef: Float = 1600
    public static let scoreFloor: Float = 0.02
    public static let writeHi: Float = 0.85
    public static let writeLo: Float = 0.40
    public static let fillTau: Float = 0.15
    public static let fillScales: [Int] = [9, 5, 3]
    public static let manualZHi: Float = 8
    public static let manualZGrow: Float = 2
    public static let manualZGrowFrac: Float = 0.25
    public static let manualZMin: Float = 5
    public static let manualWinFactor: Float = 3
    public static let manualRimPx: Float = 1.5
    public static let detectPadPx: Float = 2.5
    public static let lumaR: Float = 0.2126
    public static let lumaG: Float = 0.7152
    public static let lumaB: Float = 0.0722

    public static func bake(
        _ image: LinearRGBBuffer,
        strokes: [HealStroke],
        spots: [HealSpot] = []
    ) -> LinearRGBBuffer {
        guard !strokes.isEmpty || !spots.isEmpty else { return image }
        guard let score = strokesToScore(image, strokes: strokes, spots: spots) else {
            return image
        }
        return applyScoreRepair(image, score: score)
    }

    public static func filmScale(width: Int, height: Int) -> Float {
        max(1, Float(max(width, height)) / detectRef)
    }

    public static func sizeAtRef(diameterPx: Float, width: Int, height: Int) -> Double {
        Double(diameterPx) * Double(healSizeRef) / Double(max(width, height))
    }

    /// Painted capsule is a search area: only local density outliers are repaired.
    public static func strokesToScore(
        _ image: LinearRGBBuffer,
        strokes: [HealStroke],
        spots: [HealSpot]
    ) -> [Float]? {
        var entries: [(points: [HealPoint], size: Double)] = strokes.map { ($0.points, $0.size) }
        entries += spots.map { ([HealPoint(x: $0.x, y: $0.y)], $0.size) }
        if entries.isEmpty { return nil }

        let w = image.width
        let h = image.height
        var score = [Float](repeating: 1, count: w * h)
        let scale = Float(max(w, h)) / healSizeRef
        var touched = false
        let density = densityPlane(image)

        for (points, size) in entries {
            let radius = max(1, Float(size) * scale * 0.5)
            var chain = points.map { (Float($0.x) * Float(w), Float($0.y) * Float(h)) }
            if chain.count >= 3 {
                chain = smoothPolyline(chain)
            }
            guard !chain.isEmpty else { continue }

            let win = (Int(max(3, radius * manualWinFactor)) * 2) + 1
            let pad = Int(radius) + win
            let xs = chain.map(\.0)
            let ys = chain.map(\.1)
            let x0 = max(0, Int(xs.min()!) - pad)
            let y0 = max(0, Int(ys.min()!) - pad)
            let x1 = min(w, Int(xs.max()!) + pad + 1)
            let y1 = min(h, Int(ys.max()!) + pad + 1)
            if x1 <= x0 || y1 <= y0 { continue }

            let cw = x1 - x0
            let ch = y1 - y0
            var cover = [UInt8](repeating: 0, count: cw * ch)
            let local = chain.map { (Int(($0.0 - Float(x0)).rounded()), Int(($0.1 - Float(y0)).rounded())) }
            stampStroke(&cover, width: cw, height: ch, points: local, radius: radius)
            if !cover.contains(where: { $0 != 0 }) { continue }

            var crop = [Float](repeating: 0, count: cw * ch)
            for y in 0..<ch {
                for x in 0..<cw {
                    crop[y * cw + x] = density[(y0 + y) * w + (x0 + x)]
                }
            }
            let localMean = boxBlur(crop, width: cw, height: ch, ksize: win)
            var highpass = [Float](repeating: 0, count: cw * ch)
            for i in 0..<crop.count {
                highpass[i] = crop[i] - localMean[i]
            }
            let detail = boxBlur(highpass, width: cw, height: ch, ksize: 3)
            var absDetail = [Float](repeating: 0, count: detail.count)
            for i in 0..<detail.count {
                absDetail[i] = abs(detail[i])
            }
            let sigma = max(median(absDetail) / 0.6745, 1e-9)
            var z = [Float](repeating: 0, count: detail.count)
            for i in 0..<detail.count {
                z[i] = absDetail[i] / sigma
            }

            var peak: Float = 0
            for i in 0..<cover.count where cover[i] != 0 {
                peak = max(peak, z[i])
            }
            if peak < manualZMin { continue }
            let hi = peak >= manualZHi ? manualZHi : peak * 0.9
            let lo = max(manualZGrow, hi * manualZGrowFrac)
            var strong = [Bool](repeating: false, count: cover.count)
            var grow = [UInt8](repeating: 0, count: cover.count)
            var hasStrong = false
            for i in 0..<cover.count where cover[i] != 0 {
                if z[i] >= hi {
                    strong[i] = true
                    hasStrong = true
                }
                if z[i] >= lo {
                    grow[i] = 1
                }
            }
            if !hasStrong { continue }

            let keep = seededComponents(grow, strong: strong, width: cw, height: ch)
            let padPx = detectPadPx * filmScale(width: w, height: h)
            var region = maskToScore(keep, width: cw, height: ch, padPx: padPx)
            let coverDist = distanceTransform(cover, width: cw, height: ch)
            for i in 0..<region.count {
                let alpha = min(max(coverDist[i] / manualRimPx, 0), 1)
                region[i] = 1 - alpha * (1 - region[i])
            }
            for y in 0..<ch {
                for x in 0..<cw {
                    let di = (y0 + y) * w + (x0 + x)
                    score[di] = min(score[di], region[y * cw + x])
                }
            }
            touched = true
        }
        return touched ? score : nil
    }

    public static func applyScoreRepair(_ image: LinearRGBBuffer, score: [Float]) -> LinearRGBBuffer {
        let w = image.width
        let h = image.height
        let factor = filmScale(width: w, height: h)
        let scales = fillSupports(longEdge: max(w, h), factor: factor)
        var bbox: (x0: Int, y0: Int, x1: Int, y1: Int)?
        for y in 0..<h {
            for x in 0..<w {
                if score[y * w + x] < 1 {
                    if var box = bbox {
                        box.x0 = min(box.x0, x)
                        box.y0 = min(box.y0, y)
                        box.x1 = max(box.x1, x + 1)
                        box.y1 = max(box.y1, y + 1)
                        bbox = box
                    } else {
                        bbox = (x, y, x + 1, y + 1)
                    }
                }
            }
        }
        guard var box = bbox else { return image }
        let pad = scales.max() ?? 9
        box.x0 = max(0, box.x0 - pad)
        box.y0 = max(0, box.y0 - pad)
        box.x1 = min(w, box.x1 + pad)
        box.y1 = min(h, box.y1 + pad)
        let cw = box.x1 - box.x0
        let ch = box.y1 - box.y0
        var cropRGB = [Float](repeating: 0, count: cw * ch * 3)
        var cropScore = [Float](repeating: 1, count: cw * ch)
        for y in 0..<ch {
            for x in 0..<cw {
                let si = ((box.y0 + y) * w + (box.x0 + x)) * 3
                let di = (y * cw + x) * 3
                cropRGB[di] = image.pixels[si]
                cropRGB[di + 1] = image.pixels[si + 1]
                cropRGB[di + 2] = image.pixels[si + 2]
                cropScore[y * cw + x] = score[(box.y0 + y) * w + (box.x0 + x)]
            }
        }
        // Painted strokes: `floor=False` → `reject_floor_mass=True` so later rungs
        // do not treat the score floor as clean-film confidence.
        var fill = scoreWeightedFill(
            rgb: cropRGB,
            score: cropScore,
            width: cw,
            height: ch,
            scales: scales,
            rejectFloorMass: true
        )
        var alpha = [Float](repeating: 0, count: cw * ch)
        blendFill(src: cropRGB, score: cropScore, fill: &fill, alpha: &alpha, width: cw, height: ch)
        var out = image.pixels
        for y in 0..<ch {
            for x in 0..<cw {
                let sci = y * cw + x
                if cropScore[sci] >= 1 { continue }
                let si = sci * 3
                let di = ((box.y0 + y) * w + (box.x0 + x)) * 3
                out[di] = max(fill[si], 0)
                out[di + 1] = max(fill[si + 1], 0)
                out[di + 2] = max(fill[si + 2], 0)
            }
        }
        return LinearRGBBuffer(width: w, height: h, pixels: out)
    }

    static func fillSupports(longEdge: Int, factor: Float) -> [Int] {
        let fine = fillScales.map { Int((Float($0) * factor).rounded()) | 1 }
        let film = max(factor, Float(longEdge) / detectRef)
        let coarse = Int((Float(fillScales[0]) * film).rounded()) | 1
        var seen = Set<Int>()
        var out: [Int] = []
        for k in [coarse] + fine where seen.insert(k).inserted {
            out.append(max(k, 1))
        }
        return out
    }

    private static func densityPlane(_ image: LinearRGBBuffer) -> [Float] {
        let n = image.width * image.height
        var dens = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let r = image.pixels[i * 3]
            let g = image.pixels[i * 3 + 1]
            let b = image.pixels[i * 3 + 2]
            let luma = max(lumaR * r + lumaG * g + lumaB * b, 1e-6)
            dens[i] = -log10(luma)
        }
        return dens
    }

    private static func stampStroke(
        _ cover: inout [UInt8],
        width: Int,
        height: Int,
        points: [(Int, Int)],
        radius: Float
    ) {
        let r = max(1, Int(radius.rounded()))
        if points.count > 1 {
            let densified = densify(points)
            for (cx, cy) in densified {
                fillCircle(&cover, width: width, height: height, cx: cx, cy: cy, radius: r)
            }
        }
        for (cx, cy) in points {
            fillCircle(&cover, width: width, height: height, cx: cx, cy: cy, radius: r)
        }
    }

    private static func densify(_ points: [(Int, Int)]) -> [(Int, Int)] {
        guard points.count >= 2 else { return points }
        var out: [(Int, Int)] = []
        for i in 0..<(points.count - 1) {
            let (x0, y0) = points[i]
            let (x1, y1) = points[i + 1]
            let steps = max(1, Int(hypot(Double(x1 - x0), Double(y1 - y0)).rounded()))
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                out.append((
                    Int((Double(x0) + t * Double(x1 - x0)).rounded()),
                    Int((Double(y0) + t * Double(y1 - y0)).rounded())
                ))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    private static func fillCircle(
        _ cover: inout [UInt8],
        width: Int,
        height: Int,
        cx: Int,
        cy: Int,
        radius: Int
    ) {
        let r2 = radius * radius
        let y0 = max(0, cy - radius)
        let y1 = min(height - 1, cy + radius)
        let x0 = max(0, cx - radius)
        let x1 = min(width - 1, cx + radius)
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = x - cx
                let dy = y - cy
                if dx * dx + dy * dy <= r2 {
                    cover[y * width + x] = 1
                }
            }
        }
    }

    /// Open Catmull-Rom, matching NegPy `smooth_polyline(..., closed=False, samples_per_seg=16)`.
    static func smoothPolyline(_ pts: [(Float, Float)]) -> [(Float, Float)] {
        let n = pts.count
        if n < 3 { return pts }
        let samples = 16
        var out: [(Float, Float)] = []
        out.reserveCapacity((n - 1) * samples + 1)
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, n - 1)]
            for s in 0..<samples {
                let t = Float(s) / Float(samples)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * (
                    2 * p1.0
                        + (p2.0 - p0.0) * t
                        + (2 * p0.0 - 5 * p1.0 + 4 * p2.0 - p3.0) * t2
                        + (-p0.0 + 3 * p1.0 - 3 * p2.0 + p3.0) * t3
                )
                let y = 0.5 * (
                    2 * p1.1
                        + (p2.1 - p0.1) * t
                        + (2 * p0.1 - 5 * p1.1 + 4 * p2.1 - p3.1) * t2
                        + (-p0.1 + 3 * p1.1 - 3 * p2.1 + p3.1) * t3
                )
                out.append((x, y))
            }
        }
        out.append(pts[n - 1])
        return out
    }

    private static func seededComponents(
        _ grow: [UInt8],
        strong: [Bool],
        width: Int,
        height: Int
    ) -> [UInt8] {
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
                if grow[i] == 0 { continue }
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0, dy == 0 { continue }
                        let nx = x + dx
                        let ny = y + dy
                        if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                        let j = ny * width + nx
                        if grow[j] != 0 {
                            join(i, j)
                        }
                    }
                }
            }
        }
        var seeded = Set<Int>()
        for i in 0..<n where strong[i] && grow[i] != 0 {
            seeded.insert(find(i))
        }
        var keep = [UInt8](repeating: 0, count: n)
        for i in 0..<n where grow[i] != 0 && seeded.contains(find(i)) {
            keep[i] = 1
        }
        return keep
    }

    static func maskToScore(_ mask: [UInt8], width: Int, height: Int, padPx: Float) -> [Float] {
        var clean = [UInt8](repeating: 0, count: mask.count)
        for i in 0..<mask.count {
            clean[i] = mask[i] == 0 ? 1 : 0
        }
        let dist = distanceTransform(clean, width: width, height: height)
        let denom = max(padPx, 1e-3)
        var score = [Float](repeating: 0, count: mask.count)
        for i in 0..<mask.count {
            let t = min(max(dist[i] / denom, 0), 1)
            let s = t * t * (3 - 2 * t)
            score[i] = scoreFloor + (1 - scoreFloor) * s
        }
        return score
    }

    /// Two-pass 3-4 chamfer (approx. `cv2.DIST_L2` mask=3).
    static func distanceTransform(_ feature: [UInt8], width: Int, height: Int) -> [Float] {
        let inf: Float = 1e6
        let diag: Float = sqrt(2)
        var d = [Float](repeating: inf, count: width * height)
        for i in 0..<feature.count where feature[i] == 0 {
            d[i] = 0
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var v = d[i]
                if y > 0 { v = min(v, d[(y - 1) * width + x] + 1) }
                if x > 0 { v = min(v, d[y * width + (x - 1)] + 1) }
                if y > 0, x > 0 { v = min(v, d[(y - 1) * width + (x - 1)] + diag) }
                if y > 0, x + 1 < width { v = min(v, d[(y - 1) * width + (x + 1)] + diag) }
                d[i] = v
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                var v = d[i]
                if y + 1 < height { v = min(v, d[(y + 1) * width + x] + 1) }
                if x + 1 < width { v = min(v, d[y * width + (x + 1)] + 1) }
                if y + 1 < height, x + 1 < width { v = min(v, d[(y + 1) * width + (x + 1)] + diag) }
                if y + 1 < height, x > 0 { v = min(v, d[(y + 1) * width + (x - 1)] + diag) }
                d[i] = v
            }
        }
        return d
    }

    static func boxBlur(_ src: [Float], width: Int, height: Int, ksize: Int) -> [Float] {
        let k = max(1, ksize | 1)
        let radius = k / 2
        let inv = 1 / Float(k)
        var tmp = [Float](repeating: 0, count: src.count)
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for t in -radius...radius {
                    acc += src[y * width + reflect101(x + t, count: width)]
                }
                tmp[y * width + x] = acc * inv
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for t in -radius...radius {
                    acc += tmp[reflect101(y + t, count: height) * width + x]
                }
                out[y * width + x] = acc * inv
            }
        }
        return out
    }

    private static func reflect101(_ i: Int, count: Int) -> Int {
        if count <= 1 { return 0 }
        var x = i
        let last = count - 1
        while x < 0 || x > last {
            if x < 0 {
                x = -x
            } else {
                x = 2 * last - x
            }
        }
        return x
    }

    private static func median(_ values: [Float]) -> Float {
        if values.isEmpty { return 0 }
        var sorted = values
        sorted.sort()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return 0.5 * (sorted[mid - 1] + sorted[mid])
        }
        return sorted[mid]
    }

    private static func scoreWeightedFill(
        rgb: [Float],
        score: [Float],
        width: Int,
        height: Int,
        scales: [Int],
        rejectFloorMass: Bool
    ) -> [Float] {
        let n = width * height
        var weighted = [Float](repeating: 0, count: n * 3)
        for i in 0..<n {
            let s = score[i]
            weighted[i * 3] = rgb[i * 3] * s
            weighted[i * 3 + 1] = rgb[i * 3 + 1] * s
            weighted[i * 3 + 2] = rgb[i * 3 + 2] * s
        }
        var fill = [Float](repeating: 0, count: n * 3)
        for (rung, k) in scales.enumerated() {
            let last = rung == scales.count - 1
            let num: [Float]
            let den: [Float]
            if last {
                let kernel = PhotoLab.gaussianKernel1D(sigma: max(Float(k) / 6, 0.5))
                num = sepFilterRGB(weighted, width: width, height: height, kernel: kernel)
                den = sepFilter(score, width: width, height: height, kernel: kernel)
            } else {
                num = boxBlurRGB(weighted, width: width, height: height, ksize: k)
                den = boxBlur(score, width: width, height: height, ksize: k)
            }
            for i in 0..<n {
                let d = max(den[i], 1e-6)
                if rung == 0 {
                    fill[i * 3] = num[i * 3] / d
                    fill[i * 3 + 1] = num[i * 3 + 1] / d
                    fill[i * 3 + 2] = num[i * 3 + 2] / d
                } else {
                    let mass: Float
                    if rejectFloorMass {
                        mass = (den[i] - scoreFloor) / (1 - scoreFloor)
                    } else {
                        mass = den[i]
                    }
                    let conf = min(max(mass / fillTau, 0), 1)
                    let keep = 1 - conf
                    fill[i * 3] = fill[i * 3] * keep + (num[i * 3] / d) * conf
                    fill[i * 3 + 1] = fill[i * 3 + 1] * keep + (num[i * 3 + 1] / d) * conf
                    fill[i * 3 + 2] = fill[i * 3 + 2] * keep + (num[i * 3 + 2] / d) * conf
                }
            }
        }
        return fill
    }

    private static func blendFill(
        src: [Float],
        score: [Float],
        fill: inout [Float],
        alpha: inout [Float],
        width: Int,
        height: Int
    ) {
        let span = writeHi - writeLo
        let n = width * height
        for i in 0..<n {
            var a = min(max((writeHi - score[i]) / span, 0), 1)
            a = a * a * (3 - 2 * a)
            alpha[i] = a
            let keep = 1 - a
            fill[i * 3] = src[i * 3] * keep + fill[i * 3] * a
            fill[i * 3 + 1] = src[i * 3 + 1] * keep + fill[i * 3 + 1] * a
            fill[i * 3 + 2] = src[i * 3 + 2] * keep + fill[i * 3 + 2] * a
        }
    }

    private static func boxBlurRGB(_ src: [Float], width: Int, height: Int, ksize: Int) -> [Float] {
        var r = [Float](repeating: 0, count: width * height)
        var g = [Float](repeating: 0, count: width * height)
        var b = [Float](repeating: 0, count: width * height)
        let n = width * height
        for i in 0..<n {
            r[i] = src[i * 3]
            g[i] = src[i * 3 + 1]
            b[i] = src[i * 3 + 2]
        }
        r = boxBlur(r, width: width, height: height, ksize: ksize)
        g = boxBlur(g, width: width, height: height, ksize: ksize)
        b = boxBlur(b, width: width, height: height, ksize: ksize)
        var out = [Float](repeating: 0, count: n * 3)
        for i in 0..<n {
            out[i * 3] = r[i]
            out[i * 3 + 1] = g[i]
            out[i * 3 + 2] = b[i]
        }
        return out
    }

    private static func sepFilter(_ src: [Float], width: Int, height: Int, kernel: [Float]) -> [Float] {
        let radius = kernel.count / 2
        var tmp = [Float](repeating: 0, count: src.count)
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    acc += src[y * width + reflect101(x + k - radius, count: width)] * kernel[k]
                }
                tmp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    acc += tmp[reflect101(y + k - radius, count: height) * width + x] * kernel[k]
                }
                out[y * width + x] = acc
            }
        }
        return out
    }

    private static func sepFilterRGB(_ src: [Float], width: Int, height: Int, kernel: [Float]) -> [Float] {
        var r = [Float](repeating: 0, count: width * height)
        var g = [Float](repeating: 0, count: width * height)
        var b = [Float](repeating: 0, count: width * height)
        let n = width * height
        for i in 0..<n {
            r[i] = src[i * 3]
            g[i] = src[i * 3 + 1]
            b[i] = src[i * 3 + 2]
        }
        r = sepFilter(r, width: width, height: height, kernel: kernel)
        g = sepFilter(g, width: width, height: height, kernel: kernel)
        b = sepFilter(b, width: width, height: height, kernel: kernel)
        var out = [Float](repeating: 0, count: n * 3)
        for i in 0..<n {
            out[i * 3] = r[i]
            out[i * 3 + 1] = g[i]
            out[i * 3 + 2] = b[i]
        }
        return out
    }
}
