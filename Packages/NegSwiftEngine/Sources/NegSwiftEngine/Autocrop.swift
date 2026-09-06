import Foundation

/// Pixel ROI in half-open `(y1, y2, x1, x2)` — NegPy `geometry.logic`.
public struct PixelROI: Sendable, Equatable {
    public var y1: Int
    public var y2: Int
    public var x1: Int
    public var x2: Int

    public init(y1: Int, y2: Int, x1: Int, x2: Int) {
        self.y1 = y1
        self.y2 = y2
        self.x1 = x1
        self.x2 = x2
    }

    public var width: Int { x2 - x1 }
    public var height: Int { y2 - y1 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// Newly detected auto crop for the controller to freeze into the sidecar.
public struct AutocropResolved: Sendable, Equatable {
    public var rect: NormalizedCropRect
    public var key: String

    public init(rect: NormalizedCropRect, key: String) {
        self.rect = rect
        self.key = key
    }

    public var arrayValue: [Double] { rect.arrayValue }
}

public struct AutocropArmedResult: Sendable, Equatable {
    public var config: PrintConfig
    /// Non-nil only when this call ran detection and produced a new rect.
    public var resolved: AutocropResolved?

    public init(config: PrintConfig, resolved: AutocropResolved?) {
        self.config = config
        self.resolved = resolved
    }
}

/// Auto crop: detect once per edit, freeze `crop_rect` + `crop_detect_key`.
/// Mirrors NegPy `resolve_autocrop_rect` / `_resolve_armed_autocrop`.
public enum Autocrop: Sendable {
    public static let detectResolution = 1800
    public static let previewRenderSize = 1600.0
    public static let minFilmBoxCoverage = 0.25
    public static let defaultRatio = "Free"
    public static let defaultMode = "image"
    public static let filmMode = "film"

    public static let filmFormatRatios = [
        "1:1", "3:2", "2:3", "4:3", "3:4", "5:4", "4:5", "6:7", "7:6", "65:24", "24:65",
    ]

    public static func hasManualCrop(_ config: PrintConfig) -> Bool {
        config.cropRect != nil && !isArmed(config)
    }

    /// Armed = `crop_from_auto`, or `auto_crop_enabled` when no rect is stored yet.
    public static func isArmed(_ config: PrintConfig) -> Bool {
        if config.cropRect != nil {
            return config.cropFromAuto
        }
        return config.cropFromAuto || config.autoCropEnabled
    }

    /// NegPy `autocrop_detection_key`. Crop Offset is omitted — it is re-applied every render.
    public static func detectionKey(_ config: PrintConfig) -> String {
        [
            String(config.rotation),
            config.flipHorizontal ? "1" : "0",
            config.flipVertical ? "1" : "0",
            pythonRound4(Double(config.fineRotation)),
            pythonRound4(Double(config.convergeV)),
            pythonRound4(Double(config.convergeH)),
            config.autocropRatio,
            config.autocropMode,
            pythonRound4(Double(config.autocropRebateTrim)),
        ].joined(separator: "|")
    }

    /// Detect once. A matching stored key is a no-op so preview and export share one rect.
    public static func resolveArmed(
        _ image: LinearRGBBuffer,
        config: PrintConfig,
        previewSize: Double = previewRenderSize
    ) -> AutocropArmedResult {
        guard isArmed(config) else {
            return AutocropArmedResult(config: config, resolved: nil)
        }
        let key = detectionKey(config)
        if config.cropRect != nil {
            // Empty key: S6 stored rect / crop-metering sidecar — not a stale detect.
            // Non-empty mismatch: rotation/ratio/mode changed, re-detect.
            if config.cropDetectKey.isEmpty || config.cropDetectKey == key {
                return AutocropArmedResult(config: config, resolved: nil)
            }
        }
        guard let rect = resolveRect(image, config: config, previewSize: previewSize) else {
            return AutocropArmedResult(config: config, resolved: nil)
        }
        var out = config
        out.cropRect = rect
        out.cropDetectKey = key
        out.cropFromAuto = true
        out.autoCropEnabled = true
        return AutocropArmedResult(config: out, resolved: AutocropResolved(rect: rect, key: key))
    }

    /// Normalized rect in transformed-image space. Offset is not baked in.
    public static func resolveRect(
        _ image: LinearRGBBuffer,
        config: PrintConfig,
        previewSize: Double = previewRenderSize
    ) -> NormalizedCropRect? {
        let longest = max(image.width, image.height)
        guard longest >= 2 else { return nil }
        let scale = min(1.0, Double(detectResolution) / Double(longest))
        var tmp = image
        if scale < 1.0 {
            let dw = max(1, Int((Double(image.width) * scale).rounded()))
            let dh = max(1, Int((Double(image.height) * scale).rounded()))
            tmp = areaResized(image, width: dw, height: dh)
        }
        tmp = tmp.oriented(
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            fineRotation: config.fineRotation
        )
        let rh = tmp.height
        let rw = tmp.width
        if rh < 2 || rw < 2 { return nil }
        guard hasDetectableFrame(tmp) else { return nil }
        let roi = autocropCoords(
            tmp,
            offsetPx: 0,
            scaleFactor: Double(max(rh, rw)) / max(previewSize, 1),
            targetRatio: config.autocropRatio,
            mode: config.autocropMode,
            rebateTrim: Double(config.autocropRebateTrim)
        )
        if roi.height < 2 || roi.width < 2 { return nil }
        return NormalizedCropRect(
            x1: Double(roi.x1) / Double(rw),
            y1: Double(roi.y1) / Double(rh),
            x2: Double(roi.x2) / Double(rw),
            y2: Double(roi.y2) / Double(rh)
        )
    }

    public static func autocropCoords(
        _ image: LinearRGBBuffer,
        offsetPx: Int = 0,
        scaleFactor: Double = 1,
        targetRatio: String = defaultRatio,
        detectRes: Int = detectResolution,
        mode: String = defaultMode,
        rebateTrim: Double = 1
    ) -> PixelROI {
        let h = image.height
        let w = image.width
        let (det, detScale) = normalizeDetectionInput(image, detectRes: detectRes)
        var fromContours = false
        var filmROI: PixelROI
        if let found = detectFilmBounds(det) {
            filmROI = found
            fromContours = true
        } else {
            filmROI = thresholdAutocropCoords(det)
        }
        let lum = detectionLuma(det)
        filmROI = trimOpaqueBorder(lum: lum, width: det.width, height: det.height, roi: filmROI)

        var roi: PixelROI
        var rowOcc: [Float]?
        var colOcc: [Float]?
        if mode == filmMode {
            roi = filmROI
        } else if fromContours {
            let refined = refineROIToImage(det, filmROI: filmROI, lum: lum)
            roi = refined.roi
            rowOcc = refined.rowOccupancy
            colOcc = refined.colOccupancy
        } else {
            roi = trimFilmEdges(lum: lum, width: det.width, height: det.height, filmROI: filmROI)
        }

        roi = scaleROIInset(filmROI: filmROI, roi: roi, factor: rebateTrim)
        roi = scaleROI(roi, detScale: detScale, height: h, width: w)

        var ratio = targetRatio
        if ratio == defaultRatio || ratio == "Original" {
            ratio = closestStandardRatio(roi, imageHeight: h, imageWidth: w)
        }

        let margin = (2.0 + Double(offsetPx)) * scaleFactor
        roi = applyMargin(roi, height: h, width: w, margin: margin)

        if let rowOcc, let colOcc {
            return enforceRatioByOccupancy(
                roi,
                height: h,
                width: w,
                targetRatio: ratio,
                rowOccupancy: rowOcc,
                colOccupancy: colOcc,
                detScale: detScale
            )
        }
        return enforceAspectRatio(roi, height: h, width: w, targetRatio: ratio)
    }

    // MARK: - Detection

    static func normalizeDetectionInput(_ image: LinearRGBBuffer, detectRes: Int) -> (LinearRGBBuffer, Double) {
        let longest = max(image.width, image.height)
        let detScale = min(1.0, Double(detectRes) / Double(max(longest, 1)))
        if detScale >= 1 { return (image, 1) }
        let dw = max(1, Int((Double(image.width) * detScale).rounded()))
        let dh = max(1, Int((Double(image.height) * detScale).rounded()))
        return (areaResized(image, width: dw, height: dh), detScale)
    }

    static func scaleROI(_ roi: PixelROI, detScale: Double, height: Int, width: Int) -> PixelROI {
        if detScale >= 1 { return roi }
        return PixelROI(
            y1: max(0, Int((Double(roi.y1) / detScale).rounded())),
            y2: min(height, Int((Double(roi.y2) / detScale).rounded())),
            x1: max(0, Int((Double(roi.x1) / detScale).rounded())),
            x2: min(width, Int((Double(roi.x2) / detScale).rounded()))
        )
    }

    /// True when a film/holder box is visible. Full-frame threshold fallback is not a detect.
    static func hasDetectableFrame(_ image: LinearRGBBuffer) -> Bool {
        if detectFilmBounds(image) != nil { return true }
        let thr = thresholdAutocropCoords(image)
        return !(thr.y1 == 0 && thr.x1 == 0 && thr.y2 == image.height && thr.x2 == image.width)
    }

    /// Polarity-aware content box. Bright bed + dark frame, or dark holder + bright film.
    static func detectFilmBounds(_ image: LinearRGBBuffer) -> PixelROI? {
        let w = image.width
        let h = image.height
        if h < 2 || w < 2 { return nil }
        let lum = detectionLuma(image)
        let lo = percentile(lum, 2)
        let hi = percentile(lum, 98)
        guard hi - lo >= 0.04 else { return nil }

        let ring = outerRingValues(lum, width: w, height: h)
        guard !ring.isEmpty else { return nil }
        let ringMed = median(ring)
        let cy1 = Int((0.2 * Double(h)).rounded())
        let cy2 = max(cy1 + 1, Int((0.8 * Double(h)).rounded()))
        let cx1 = Int((0.2 * Double(w)).rounded())
        let cx2 = max(cx1 + 1, Int((0.8 * Double(w)).rounded()))
        var center: [Float] = []
        center.reserveCapacity((cy2 - cy1) * (cx2 - cx1))
        for y in cy1..<min(cy2, h) {
            for x in cx1..<min(cx2, w) {
                center.append(lum[y * w + x])
            }
        }
        let centerMed = median(center)
        let gate = max(0.025, 0.05 * (hi - lo))
        let darkContent: Bool
        if ringMed - centerMed > gate {
            darkContent = true
        } else if centerMed - ringMed > gate {
            darkContent = false
        } else {
            return nil
        }

        let mid = (ringMed + centerMed) * 0.5
        var minY = h
        var maxY = -1
        var minX = w
        var maxX = -1
        var count = 0
        for y in 0..<h {
            for x in 0..<w {
                let v = lum[y * w + x]
                let isContent = darkContent ? v < mid : v > mid
                if isContent {
                    count += 1
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }
        guard count > 0, maxY >= minY, maxX >= minX else { return nil }
        let roi = PixelROI(y1: minY, y2: maxY + 1, x1: minX, x2: maxX + 1)
        guard filmBoxCoversEnough(width: w, height: h, roi: roi) else { return nil }
        guard filmSurroundIsPlausible(lum: lum, width: w, height: h, roi: roi) else { return nil }
        return roi
    }

    static func thresholdAutocropCoords(_ image: LinearRGBBuffer) -> PixelROI {
        let w = image.width
        let h = image.height
        let lum = rec709Luma(image)
        let threshold: Float = 0.96
        var yLo = h
        var yHi = -1
        var xLo = w
        var xHi = -1
        var rowHits = 0
        for y in 0..<h {
            var sum: Float = 0
            for x in 0..<w {
                sum += lum[y * w + x]
            }
            if sum / Float(w) < threshold {
                rowHits += 1
                yLo = min(yLo, y)
                yHi = max(yHi, y)
            }
        }
        var colHits = 0
        for x in 0..<w {
            var sum: Float = 0
            for y in 0..<h {
                sum += lum[y * w + x]
            }
            if sum / Float(h) < threshold {
                colHits += 1
                xLo = min(xLo, x)
                xHi = max(xHi, x)
            }
        }
        if rowHits < 10 || colHits < 10 {
            return PixelROI(y1: 0, y2: h, x1: 0, x2: w)
        }
        return PixelROI(y1: yLo, y2: yHi + 1, x1: xLo, x2: xHi + 1)
    }

    static func trimOpaqueBorder(
        lum: [Float],
        width: Int,
        height: Int,
        roi: PixelROI,
        black: Float = 0.02,
        frac: Float = 0.7,
        maxTrim: Float = 0.2
    ) -> PixelROI {
        let bh = roi.height
        let bw = roi.width
        if bh < 4 || bw < 4 { return roi }
        var rowBlack = [Float](repeating: 0, count: bh)
        var colBlack = [Float](repeating: 0, count: bw)
        for y in 0..<bh {
            var n: Float = 0
            for x in 0..<bw {
                if lum[(roi.y1 + y) * width + (roi.x1 + x)] < black { n += 1 }
            }
            rowBlack[y] = n / Float(bw)
        }
        for x in 0..<bw {
            var n: Float = 0
            for y in 0..<bh {
                if lum[(roi.y1 + y) * width + (roi.x1 + x)] < black { n += 1 }
            }
            colBlack[x] = n / Float(bh)
        }
        func run(_ profile: [Float], limit: Int, fromStart: Bool) -> Int {
            var i = 0
            while i < limit {
                let v = fromStart ? profile[i] : profile[profile.count - 1 - i]
                if v < frac { break }
                i += 1
            }
            return i >= limit ? 0 : i
        }
        let ly = Int((maxTrim * Float(bh)).rounded())
        let lx = Int((maxTrim * Float(bw)).rounded())
        let top = run(rowBlack, limit: ly, fromStart: true)
        let bottom = run(rowBlack, limit: ly, fromStart: false)
        let left = run(colBlack, limit: lx, fromStart: true)
        let right = run(colBlack, limit: lx, fromStart: false)
        let ny1 = roi.y1 + top
        let ny2 = roi.y2 - bottom
        let nx1 = roi.x1 + left
        let nx2 = roi.x2 - right
        if ny2 - ny1 <= 0 || nx2 - nx1 <= 0 { return roi }
        return PixelROI(y1: ny1, y2: ny2, x1: nx1, x2: nx2)
    }

    static func trimFilmEdges(lum: [Float], width: Int, height: Int, filmROI: PixelROI) -> PixelROI {
        let bh = filmROI.height
        let bw = filmROI.width
        if bh < 16 || bw < 16 { return filmROI }
        let cap = 0.06
        let ly = max(1, Int((cap * Double(bh)).rounded()))
        let lx = max(1, Int((cap * Double(bw)).rounded()))
        let interior = boxMedian(lum: lum, width: width, roi: inset(filmROI, fraction: 0.25))
        let surround: Float
        if let ring = surroundMedian(lum: lum, width: width, height: height, roi: filmROI) {
            surround = ring
        } else {
            surround = interior
        }
        func depth(limit: Int, isRow: Bool, fromStart: Bool) -> Int {
            var i = 0
            while i < limit {
                var sum: Float = 0
                var n = 0
                if isRow {
                    let y = fromStart ? filmROI.y1 + i : filmROI.y2 - 1 - i
                    for x in filmROI.x1..<filmROI.x2 {
                        sum += lum[y * width + x]
                        n += 1
                    }
                } else {
                    let x = fromStart ? filmROI.x1 + i : filmROI.x2 - 1 - i
                    for y in filmROI.y1..<filmROI.y2 {
                        sum += lum[y * width + x]
                        n += 1
                    }
                }
                let mean = sum / Float(max(n, 1))
                if abs(mean - surround) >= abs(mean - interior) { break }
                i += 1
            }
            return i
        }
        let top = depth(limit: ly, isRow: true, fromStart: true)
        let bottom = depth(limit: ly, isRow: true, fromStart: false)
        let left = depth(limit: lx, isRow: false, fromStart: true)
        let right = depth(limit: lx, isRow: false, fromStart: false)
        let roi = PixelROI(
            y1: filmROI.y1 + top,
            y2: filmROI.y2 - bottom,
            x1: filmROI.x1 + left,
            x2: filmROI.x2 - right
        )
        if roi.height < Int(0.5 * Double(bh)) || roi.width < Int(0.5 * Double(bw)) {
            return filmROI
        }
        return roi
    }

    static func refineROIToImage(
        _ image: LinearRGBBuffer,
        filmROI: PixelROI,
        lum: [Float]
    ) -> (roi: PixelROI, rowOccupancy: [Float]?, colOccupancy: [Float]?) {
        if let tiers = refineByTiers(lum: lum, width: image.width, height: image.height, filmROI: filmROI) {
            return tiers
        }
        let walked = trimFilmEdges(lum: lum, width: image.width, height: image.height, filmROI: filmROI)
        if walked != filmROI {
            return (walked, nil, nil)
        }
        return (filmROI, nil, nil)
    }

    static func refineByTiers(
        lum: [Float],
        width: Int,
        height: Int,
        filmROI: PixelROI
    ) -> (roi: PixelROI, rowOccupancy: [Float]?, colOccupancy: [Float]?)? {
        guard let rebate = findRebateLevel(lum: lum, width: width, filmROI: filmROI) else { return nil }
        let y1 = filmROI.y1
        let y2 = filmROI.y2
        let x1 = filmROI.x1
        let x2 = filmROI.x2
        let bh = filmROI.height
        let bw = filmROI.width
        var dark: [Float] = []
        for y in y1..<y2 {
            for x in x1..<x2 {
                let v = lum[y * width + x]
                if v < rebate.level - 0.02 { dark.append(v) }
            }
        }
        if dark.count < Int(0.05 * Double(bh * bw)) { return nil }
        let imageLevel = percentile(dark, 30)
        let separation = rebate.level - imageLevel
        if separation < max(0.04, 3 * rebate.spread) { return nil }
        let threshold = max(0.5 * (rebate.level + imageLevel), rebate.level - max(0.04, 3 * rebate.spread))
        var rowOcc = [Float](repeating: 0, count: bh)
        for y in 0..<bh {
            var n: Float = 0
            for x in 0..<bw {
                if lum[(y1 + y) * width + (x1 + x)] < threshold { n += 1 }
            }
            rowOcc[y] = n / Float(bw)
        }
        guard let vrun = longestRunAbove(rowOcc, threshold: 0.55) else { return nil }
        var colOcc = [Float](repeating: 0, count: bw)
        for x in 0..<bw {
            var n: Float = 0
            let span = max(vrun.1 - vrun.0, 1)
            for y in vrun.0..<vrun.1 {
                if lum[(y1 + y) * width + (x1 + x)] < threshold { n += 1 }
            }
            colOcc[x] = n / Float(span)
        }
        guard let hrun = longestRunAbove(colOcc, threshold: 0.55) else { return nil }
        if (vrun.1 - vrun.0) < Int(0.5 * Double(bh)) || (hrun.1 - hrun.0) < Int(0.5 * Double(bw)) {
            return nil
        }
        let areaRatio = Double((vrun.1 - vrun.0) * (hrun.1 - hrun.0)) / Double(bh * bw)
        if areaRatio < 0.25 || areaRatio > 0.95 { return nil }

        var rowFull = [Float](repeating: 0, count: height)
        var colFull = [Float](repeating: 0, count: width)
        for i in 0..<bh { rowFull[y1 + i] = rowOcc[i] }
        for i in 0..<bw { colFull[x1 + i] = colOcc[i] }
        return (
            PixelROI(y1: y1 + vrun.0, y2: y1 + vrun.1, x1: x1 + hrun.0, x2: x1 + hrun.1),
            rowFull,
            colFull
        )
    }

    static func findRebateLevel(lum: [Float], width: Int, filmROI: PixelROI) -> (level: Float, spread: Float)? {
        let bh = filmROI.height
        let bw = filmROI.width
        if bh < 16 || bw < 16 { return nil }
        var all = [Float]()
        all.reserveCapacity(lum.count)
        all.append(contentsOf: lum)
        let bed = percentile(all, 99)
        var box: [Float] = []
        for y in filmROI.y1..<filmROI.y2 {
            for x in filmROI.x1..<filmROI.x2 {
                box.append(lum[y * width + x])
            }
        }
        let boxMedian = percentile(box, 50)
        let ringW = max(3, Int((0.04 * Double(min(bh, bw))).rounded()))
        var qualifying: [(Float, Float)] = []
        let sides: [(Int, Int, Int, Int)] = [
            (filmROI.y1, filmROI.y1 + ringW, filmROI.x1, filmROI.x2),
            (filmROI.y2 - ringW, filmROI.y2, filmROI.x1, filmROI.x2),
            (filmROI.y1, filmROI.y2, filmROI.x1, filmROI.x1 + ringW),
            (filmROI.y1, filmROI.y2, filmROI.x2 - ringW, filmROI.x2),
        ]
        var hit = [false, false, false, false]
        for (i, side) in sides.enumerated() {
            var vals: [Float] = []
            var total = 0
            for y in side.0..<side.1 {
                for x in side.2..<side.3 {
                    total += 1
                    let v = lum[y * width + x]
                    if v < bed - 0.05 { vals.append(v) }
                }
            }
            if vals.count < Int(0.25 * Double(max(total, 1))) { continue }
            let spread = percentile(vals, 80) - percentile(vals, 20)
            if spread > 0.10 { continue }
            let p60 = percentile(vals, 60)
            if p60 < boxMedian + 0.10 { continue }
            qualifying.append((p60, spread))
            hit[i] = true
        }
        let hasPair = (hit[0] && hit[1]) || (hit[2] && hit[3])
        if !hasPair { return nil }
        let best = qualifying.max { $0.0 < $1.0 }!
        return (best.0, best.1)
    }

    // MARK: - Geometry helpers

    public static func applyMargin(_ roi: PixelROI, height: Int, width: Int, margin: Double) -> PixelROI {
        PixelROI(
            y1: Int(max(0, Double(roi.y1) + margin)),
            y2: Int(min(Double(height), Double(roi.y2) - margin)),
            x1: Int(max(0, Double(roi.x1) + margin)),
            x2: Int(min(Double(width), Double(roi.x2) - margin))
        )
    }

    static func scaleROIInset(filmROI: PixelROI, roi: PixelROI, factor: Double) -> PixelROI {
        if factor == 1 { return roi }
        let scaled = PixelROI(
            y1: filmROI.y1 + Int(((Double(roi.y1) - Double(filmROI.y1)) * factor).rounded()),
            y2: filmROI.y2 - Int(((Double(filmROI.y2) - Double(roi.y2)) * factor).rounded()),
            x1: filmROI.x1 + Int(((Double(roi.x1) - Double(filmROI.x1)) * factor).rounded()),
            x2: filmROI.x2 - Int(((Double(filmROI.x2) - Double(roi.x2)) * factor).rounded())
        )
        if scaled.isEmpty { return roi }
        return scaled
    }

    static func resolveRatioDims(cw: Int, ch: Int, targetRatio: String) -> (Double, Double) {
        var wr = 3.0
        var hr = 2.0
        let parts = targetRatio.split(separator: ":")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
            wr = a
            hr = b
        }
        var target = wr / hr
        let isVertical = ch > cw
        if isVertical {
            if target > 1 { target = 1 / target }
        } else if target < 1 {
            target = 1 / target
        }
        let current = Double(cw) / Double(max(ch, 1))
        if current > target {
            return (Double(ch) * target, Double(ch))
        }
        return (Double(cw), Double(cw) / target)
    }

    public static func enforceAspectRatio(
        _ roi: PixelROI,
        height: Int,
        width: Int,
        targetRatio: String
    ) -> PixelROI {
        var y1 = roi.y1
        var y2 = roi.y2
        var x1 = roi.x1
        var x2 = roi.x2
        let cw = x2 - x1
        let ch = y2 - y1
        if cw <= 0 || ch <= 0 {
            return PixelROI(y1: 0, y2: height, x1: 0, x2: width)
        }
        if targetRatio == defaultRatio {
            return PixelROI(
                y1: max(0, y1),
                y2: min(height, y2),
                x1: max(0, x1),
                x2: min(width, x2)
            )
        }
        let (tw, th) = resolveRatioDims(cw: cw, ch: ch, targetRatio: targetRatio)
        if tw < Double(cw) {
            let nx1 = Double(x1) + (Double(cw) - tw) / 2
            x1 = Int(nx1)
            x2 = Int(nx1 + tw)
        } else if th < Double(ch) {
            let ny1 = Double(y1) + (Double(ch) - th) / 2
            y1 = Int(ny1)
            y2 = Int(ny1 + th)
        }
        return PixelROI(y1: max(0, y1), y2: min(height, y2), x1: max(0, x1), x2: min(width, x2))
    }

    static func placeWindowByOccupancy(
        start: Int,
        end: Int,
        targetLen: Double,
        occupancy: [Float],
        scale: Double
    ) -> Int {
        let dStart = max(0, Int((Double(start) * scale).rounded()))
        let dEnd = min(occupancy.count, Int((Double(end) * scale).rounded()))
        let dLen = max(1, Int((targetLen * scale).rounded()))
        if dLen >= dEnd - dStart { return start }
        var cs = [Double](repeating: 0, count: (dEnd - dStart) + 1)
        for i in 0..<(dEnd - dStart) {
            cs[i + 1] = cs[i] + Double(occupancy[dStart + i])
        }
        let nPos = (dEnd - dStart) - dLen + 1
        var best = -Double.greatestFiniteMagnitude
        var scores = [Double](repeating: 0, count: nPos)
        for k in 0..<nPos {
            scores[k] = cs[dLen + k] - cs[k]
            best = max(best, scores[k])
        }
        var candidates: [Int] = []
        for k in 0..<nPos where scores[k] >= best - 1e-9 {
            candidates.append(k)
        }
        let centered = Double((dEnd - dStart) - dLen) / 2
        let k = candidates.min(by: { abs(Double($0) - centered) < abs(Double($1) - centered) }) ?? 0
        let newStart = Int((Double(dStart + k) / scale).rounded())
        return min(max(start, newStart), end - Int(targetLen))
    }

    static func enforceRatioByOccupancy(
        _ roi: PixelROI,
        height: Int,
        width: Int,
        targetRatio: String,
        rowOccupancy: [Float],
        colOccupancy: [Float],
        detScale: Double
    ) -> PixelROI {
        var y1 = roi.y1
        var y2 = roi.y2
        var x1 = roi.x1
        var x2 = roi.x2
        let cw = x2 - x1
        let ch = y2 - y1
        if cw <= 0 || ch <= 0 {
            return PixelROI(y1: 0, y2: height, x1: 0, x2: width)
        }
        if targetRatio == defaultRatio {
            return PixelROI(y1: max(0, y1), y2: min(height, y2), x1: max(0, x1), x2: min(width, x2))
        }
        let (tw, th) = resolveRatioDims(cw: cw, ch: ch, targetRatio: targetRatio)
        if tw < Double(cw) {
            x1 = placeWindowByOccupancy(start: x1, end: x2, targetLen: tw, occupancy: colOccupancy, scale: detScale)
            x2 = Int((Double(x1) + tw).rounded())
        } else if th < Double(ch) {
            y1 = placeWindowByOccupancy(start: y1, end: y2, targetLen: th, occupancy: rowOccupancy, scale: detScale)
            y2 = Int((Double(y1) + th).rounded())
        }
        return PixelROI(y1: max(0, y1), y2: min(height, y2), x1: max(0, x1), x2: min(width, x2))
    }

    static func closestStandardRatio(_ roi: PixelROI, imageHeight: Int, imageWidth: Int, fallback: String = "3:2") -> String {
        let cw = roi.width
        let ch = roi.height
        if cw <= 0 || ch <= 0 { return fallback }
        let detected = Double(cw) / Double(ch)
        let isLandscape = cw >= ch
        var candidates: [(String, Double)] = []
        for ratio in filmFormatRatios {
            let parts = ratio.split(separator: ":")
            guard parts.count == 2, let wr = Double(parts[0]), let hr = Double(parts[1]), hr != 0 else { continue }
            let target = wr / hr
            let targetLandscape = target >= 1
            if isLandscape != targetLandscape, target != 1 { continue }
            candidates.append((ratio, target))
        }
        if candidates.isEmpty { return fallback }
        func logDist(_ a: Double, _ b: Double) -> Double {
            abs(log(max(a, 1e-6)) - log(max(b, 1e-6)))
        }
        var best = candidates.min(by: { logDist(detected, $0.1) < logDist(detected, $1.1) })!
        let imgRatio = Double(imageWidth) / Double(max(imageHeight, 1))
        let stretched = abs(log(max(detected, 1e-6))) > abs(log(max(imgRatio, 1e-6)))
        if stretched, logDist(imgRatio, best.1) > 0.3 {
            best = candidates.min(by: { logDist(imgRatio, $0.1) < logDist(imgRatio, $1.1) })!
        }
        return best.0
    }

    // MARK: - Image helpers

    static func rec709Luma(_ image: LinearRGBBuffer) -> [Float] {
        let n = image.width * image.height
        var lum = [Float](repeating: 0, count: n)
        for i in 0..<n {
            lum[i] = HealInpaint.lumaR * image.pixels[i * 3]
                + HealInpaint.lumaG * image.pixels[i * 3 + 1]
                + HealInpaint.lumaB * image.pixels[i * 3 + 2]
        }
        return lum
    }

    static func detectionLuma(_ image: LinearRGBBuffer) -> [Float] {
        var lum = rec709Luma(image)
        let anchor = max(percentile(lum, 99.5), 1e-6)
        for i in 0..<lum.count {
            lum[i] = min(max(lum[i] / anchor, 0), 2)
        }
        return lum
    }

    static func areaResized(_ image: LinearRGBBuffer, width: Int, height: Int) -> LinearRGBBuffer {
        if width == image.width, height == image.height { return image }
        var out = [Float](repeating: 0, count: width * height * 3)
        let srcW = image.width
        let srcH = image.height
        for y in 0..<height {
            let y0 = y * srcH / height
            let y1 = max(y0 + 1, (y + 1) * srcH / height)
            for x in 0..<width {
                let x0 = x * srcW / width
                let x1 = max(x0 + 1, (x + 1) * srcW / width)
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0
                var n: Float = 0
                for sy in y0..<min(y1, srcH) {
                    for sx in x0..<min(x1, srcW) {
                        let i = (sy * srcW + sx) * 3
                        r += image.pixels[i]
                        g += image.pixels[i + 1]
                        b += image.pixels[i + 2]
                        n += 1
                    }
                }
                let d = (y * width + x) * 3
                let inv = n > 0 ? 1 / n : 0
                out[d] = r * inv
                out[d + 1] = g * inv
                out[d + 2] = b * inv
            }
        }
        return LinearRGBBuffer(width: width, height: height, pixels: out)
    }

    static func filmBoxCoversEnough(width: Int, height: Int, roi: PixelROI) -> Bool {
        height > 0 && width > 0
            && roi.height * roi.width >= Int(minFilmBoxCoverage * Double(height * width))
    }

    static func filmSurroundIsPlausible(lum: [Float], width: Int, height: Int, roi: PixelROI) -> Bool {
        var outside: [Float] = []
        outside.reserveCapacity(max(width * height - roi.width * roi.height, 0))
        for y in 0..<height {
            for x in 0..<width {
                if y < roi.y1 || y >= roi.y2 || x < roi.x1 || x >= roi.x2 {
                    outside.append(lum[y * width + x])
                }
            }
        }
        if outside.count < Int(0.005 * Double(lum.count)) { return true }
        let outMed = median(outside)
        let outHigh = percentile(outside, 90)
        var box: [Float] = []
        for y in roi.y1..<roi.y2 {
            for x in roi.x1..<roi.x2 {
                box.append(lum[y * width + x])
            }
        }
        let boxMed = median(box)
        let bedLike = outMed >= 0.85 && outHigh >= 0.98
        let holderLike = outMed <= 0.30 && outMed <= boxMed - 0.15
        return bedLike || holderLike
    }

    static func outerRingValues(_ lum: [Float], width: Int, height: Int) -> [Float] {
        var ringW = max(2, Int((0.02 * Double(min(height, width))).rounded()))
        ringW = min(ringW, max(1, min(height, width) / 2))
        var parts: [Float] = []
        for y in 0..<ringW {
            for x in 0..<width { parts.append(lum[y * width + x]) }
        }
        for y in (height - ringW)..<height {
            for x in 0..<width { parts.append(lum[y * width + x]) }
        }
        if height > 2 * ringW {
            for y in ringW..<(height - ringW) {
                for x in 0..<ringW { parts.append(lum[y * width + x]) }
                for x in (width - ringW)..<width { parts.append(lum[y * width + x]) }
            }
        }
        return parts
    }

    static func surroundMedian(lum: [Float], width: Int, height: Int, roi: PixelROI) -> Float? {
        var vals: [Float] = []
        for y in 0..<height {
            for x in 0..<width {
                if y < roi.y1 || y >= roi.y2 || x < roi.x1 || x >= roi.x2 {
                    vals.append(lum[y * width + x])
                }
            }
        }
        if vals.isEmpty { return nil }
        return median(vals)
    }

    static func boxMedian(lum: [Float], width: Int, roi: PixelROI) -> Float {
        var vals: [Float] = []
        for y in roi.y1..<roi.y2 {
            for x in roi.x1..<roi.x2 {
                vals.append(lum[y * width + x])
            }
        }
        return median(vals)
    }

    static func inset(_ roi: PixelROI, fraction: Double) -> PixelROI {
        let dy = Int((Double(roi.height) * fraction).rounded())
        let dx = Int((Double(roi.width) * fraction).rounded())
        return PixelROI(
            y1: roi.y1 + dy,
            y2: max(roi.y1 + dy + 1, roi.y2 - dy),
            x1: roi.x1 + dx,
            x2: max(roi.x1 + dx + 1, roi.x2 - dx)
        )
    }

    static func longestRunAbove(_ profile: [Float], threshold: Float) -> (Int, Int)? {
        var bestLo = 0
        var bestHi = 0
        var lo: Int?
        for i in 0...profile.count {
            let on = i < profile.count && profile[i] >= threshold
            if on {
                if lo == nil { lo = i }
            } else if let start = lo {
                if i - start > bestHi - bestLo {
                    bestLo = start
                    bestHi = i
                }
                lo = nil
            }
        }
        if bestHi <= bestLo { return nil }
        return (bestLo, bestHi)
    }

    static func percentile(_ values: [Float], _ q: Double) -> Float {
        if values.isEmpty { return 0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let p = min(max(q, 0), 100) / 100
        let idx = p * Double(sorted.count - 1)
        let lo = Int(idx)
        let hi = min(lo + 1, sorted.count - 1)
        let t = Float(idx - Double(lo))
        return sorted[lo] * (1 - t) + sorted[hi] * t
    }

    static func median(_ values: [Float]) -> Float {
        percentile(values, 50)
    }

    static func pythonRound4(_ value: Double) -> String {
        let scaled = (value * 10_000).rounded() / 10_000
        if scaled == scaled.rounded() {
            return String(format: "%.1f", scaled)
        }
        var s = String(format: "%.4f", scaled)
        while s.last == "0" { s.removeLast() }
        return s
    }
}
