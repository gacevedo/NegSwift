import Accelerate
import Foundation

/// Saturation, skin-chroma rein, and L* USM. Mirrors NegPy `PhotoLabProcessor`
/// (`features/lab/processor.py` + `logic.py`) at NegSwift defaults.
///
/// CLAHE, chroma denoise, glow/halation, and RL sharpen are no-ops in lite and are not ported.
public enum PhotoLab: Sendable {
    public static let defaultSaturation: Float = 1
    public static let defaultSkinProtection: Float = 0.5
    public static let defaultSharpen: Float = 0.25
    public static let defaultSharpenRadius: Float = 1
    public static let defaultSharpenMasking: Float = 0

    public static let sharpenGateLo: Float = 0.25
    public static let sharpenGateHi: Float = 0.33
    public static let sharpenOvershootLight: Float = 1
    public static let sharpenOvershootDark: Float = 2
    public static let sharpenMaskTHi: Float = 10
    /// NegPy `SHARPEN_SHADOW_FLOOR` — gain floor at paper black (Gallagher & Gindele).
    public static let sharpenShadowFloor: Float = 1.0 / 3.0
    /// NegPy `SHARPEN_SHADOW_L_HI` — full gain from this L* up.
    public static let sharpenShadowLHi: Float = 35

    /// Per-pixel sharpen gain multiplier from L*; mirrors `sharpen_shadow_gain`.
    public static func sharpenShadowGain(_ l: Float) -> Float {
        sharpenShadowFloor + (1 - sharpenShadowFloor) * smoothstep(0, sharpenShadowLHi, l)
    }

    public static let skinHueCenterDeg: Float = 52
    public static let skinHueWidthDeg: Float = 20
    public static let skinChromaFull: Float = 35
    public static let skinChromaZero: Float = 60
    public static let skinLLo: Float = 15
    public static let skinLHi: Float = 95
    public static let skinCeilAtFull: Float = 22
    public static let skinKneeStartFrac: Float = 0.6

    @_optimize(speed)
    public static func process(_ image: LinearRGBBuffer, config: PrintConfig) -> LinearRGBBuffer {
        let needsSat = config.saturation != 1 || config.skinProtection > 0
        let needsSharpen = config.sharpen > 0
        if !needsSat, !needsSharpen {
            return clip01(image)
        }
        // One RGB↔Lab hop for sat + skin + USM. Intermediate clip after sat is a no-op
        // at NegSwift defaults (sat 1, skin only pulls chroma in).
        var lab = WorkingLab.rgbToLab(image)
        if needsSat {
            if config.saturation != 1 {
                lab = gamutAwareChromaScale(lab, saturation: config.saturation)
            }
            if config.skinProtection > 0 {
                lab = skinChromaRein(lab, strength: config.skinProtection)
            }
        }
        if needsSharpen {
            lab = sharpenLab(
                lab,
                amount: config.sharpen,
                radius: config.sharpenRadius,
                masking: config.sharpenMasking
            )
        }
        return clip01(WorkingLab.labToRgb(lab))
    }

    public static func applySaturation(
        _ image: LinearRGBBuffer,
        saturation: Float,
        skinProtection: Float = 0
    ) -> LinearRGBBuffer {
        if saturation == 1, skinProtection <= 0 {
            return image
        }
        var lab = WorkingLab.rgbToLab(image)
        if saturation != 1 {
            lab = gamutAwareChromaScale(lab, saturation: saturation)
        }
        if skinProtection > 0 {
            lab = skinChromaRein(lab, strength: skinProtection)
        }
        return clip01(WorkingLab.labToRgb(lab))
    }

    public static func applyOutputSharpening(
        _ image: LinearRGBBuffer,
        amount: Float,
        radius: Float = 1,
        masking: Float = 0
    ) -> LinearRGBBuffer {
        if amount <= 0 { return image }
        let lab = sharpenLab(
            WorkingLab.rgbToLab(image),
            amount: amount,
            radius: radius,
            masking: masking
        )
        return clip01(WorkingLab.labToRgb(lab))
    }

    @_optimize(speed)
    private static func sharpenLab(
        _ lab: LinearRGBBuffer,
        amount: Float,
        radius: Float,
        masking: Float
    ) -> LinearRGBBuffer {
        let width = lab.width
        let height = lab.height
        let count = width * height
        var lChan = [Float](repeating: 0, count: count)
        var aChan = [Float](repeating: 0, count: count)
        var bChan = [Float](repeating: 0, count: count)
        for i in 0..<count {
            lChan[i] = lab.pixels[i * 3]
            aChan[i] = lab.pixels[i * 3 + 1]
            bChan[i] = lab.pixels[i * 3 + 2]
        }

        let kernel = gaussianKernel1D(sigma: radius)
        let lBlur = sepFilter2D(lChan, width: width, height: height, kernel: kernel)
        var lNew = [Float](repeating: 0, count: count)
        let lMin = erode3(lChan, width: width, height: height)
        let lMax = dilate3(lChan, width: width, height: height)
        let edge = masking > 0 ? edgeMask(lChan, width: width, height: height, masking: masking) : nil

        for i in 0..<count {
            let l = lChan[i]
            let diff = l - lBlur[i]
            var gain = amount * 2.5 * smoothstep(sharpenGateLo, sharpenGateHi, abs(diff)) * sharpenShadowGain(l)
            if let edge {
                gain *= edge[i]
            }
            var next = l + diff * gain
            next = min(max(next, lMin[i] - sharpenOvershootDark), lMax[i] + sharpenOvershootLight)
            lNew[i] = min(max(next, 0), 100)
        }

        var outLab = lab.pixels
        for i in 0..<count {
            outLab[i * 3] = lNew[i]
            outLab[i * 3 + 1] = aChan[i]
            outLab[i * 3 + 2] = bChan[i]
        }
        return LinearRGBBuffer(width: width, height: height, pixels: outLab)
    }

    public static func gaussianKernel1D(sigma: Float) -> [Float] {
        let radius = max(1, min(255, Int(ceil(2.5 * Double(sigma)))))
        var k = [Float](repeating: 0, count: 2 * radius + 1)
        let denom = 2 * sigma * sigma
        var sum: Float = 0
        for i in 0..<k.count {
            let x = Float(i - radius)
            let v = exp(-(x * x) / denom)
            k[i] = v
            sum += v
        }
        for i in 0..<k.count {
            k[i] /= sum
        }
        return k
    }

    @_optimize(speed)
    public static func skinWeight(l: Float, a: Float, b: Float) -> Float {
        let chroma = hypot(a, b)
        if chroma < 2 { return 0 }
        let hueDeg = atan2(b, a) * (180 / Float.pi)
        // Wrap to [-180, 180] the way NegPy does (`dist - 360 * round(dist/360)`).
        var dist = hueDeg - skinHueCenterDeg
        dist -= 360 * roundedTowardEven(dist / 360)
        let x = dist / skinHueWidthDeg
        let wHue = exp(-0.5 * x * x)
        let wChroma = 1 - smoothstep(skinChromaFull, skinChromaZero, chroma)
        let wLight = smoothstep(0, skinLLo, l) * (1 - smoothstep(skinLHi, 100, l))
        return wHue * wChroma * wLight
    }

    @_optimize(speed)
    public static func skinChromaRein(_ lab: LinearRGBBuffer, strength: Float) -> LinearRGBBuffer {
        if strength <= 0 { return lab }
        let ceiling = skinCeilAtFull / strength
        let start = skinKneeStartFrac * ceiling
        let span = ceiling - start
        var out = lab.pixels
        let n = lab.width * lab.height
        for i in 0..<n {
            let o = i * 3
            let l = out[o]
            let a = out[o + 1]
            let b = out[o + 2]
            let chroma = hypot(a, b)
            var scale: Float = 1
            if chroma > start {
                let w = skinWeight(l: l, a: a, b: b)
                if w > 0 {
                    let knee = start + span * (1 - exp(-(chroma - start) / span))
                    scale = (chroma + w * (knee - chroma)) / chroma
                }
            }
            out[o + 1] = a * scale
            out[o + 2] = b * scale
        }
        return LinearRGBBuffer(width: lab.width, height: lab.height, pixels: out)
    }

    public static func gamutAwareChromaScale(
        _ lab: LinearRGBBuffer,
        saturation: Float,
        iters: Int = 10
    ) -> LinearRGBBuffer {
        var out = lab.pixels
        let n = lab.width * lab.height
        for i in 0..<n {
            let o = i * 3
            let l = out[o]
            let a = out[o + 1]
            let b = out[o + 2]
            let eff: Float
            if saturation <= 1 {
                eff = saturation
            } else if WorkingLab.inGamut(l: l, a: a * saturation, b: b * saturation) {
                eff = saturation
            } else {
                var lo: Float = 1
                var hi = saturation
                let stillOK = WorkingLab.inGamut(l: l, a: a, b: b)
                for _ in 0..<iters {
                    let mid = (lo + hi) / 2
                    if stillOK, WorkingLab.inGamut(l: l, a: a * mid, b: b * mid) {
                        lo = mid
                    } else {
                        hi = mid
                    }
                }
                var sMax = lo
                if sMax < 1 + 1e-4 {
                    sMax = 1 + 1e-4
                }
                let knee = sMax - 1
                eff = 1 + knee * (1 - exp(-(saturation - 1) / knee))
            }
            out[o + 1] = a * eff
            out[o + 2] = b * eff
        }
        return LinearRGBBuffer(width: lab.width, height: lab.height, pixels: out)
    }

    public static func clip01(_ image: LinearRGBBuffer) -> LinearRGBBuffer {
        var pixels = image.pixels
        vDSP.clip(pixels, to: 0...1, result: &pixels)
        return LinearRGBBuffer(width: image.width, height: image.height, pixels: pixels)
    }

    public static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Banker's rounding — NumPy `np.round` / Python `round` on `.0` ties.
    private static func roundedTowardEven(_ value: Float) -> Float {
        let rounded = value.rounded(.toNearestOrEven)
        return rounded
    }

    @_optimize(speed)
    private static func sepFilter2D(_ src: [Float], width: Int, height: Int, kernel: [Float]) -> [Float] {
        let radius = kernel.count / 2
        var tmp = [Float](repeating: 0, count: src.count)
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    let sx = reflect101(x + k - radius, count: width)
                    acc += src[y * width + sx] * kernel[k]
                }
                tmp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in 0..<kernel.count {
                    let sy = reflect101(y + k - radius, count: height)
                    acc += tmp[sy * width + x] * kernel[k]
                }
                out[y * width + x] = acc
            }
        }
        return out
    }

    /// OpenCV `BORDER_REFLECT_101`: `gfedcb|abcdefgh|gfedcba`.
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

    private static func erode3(_ src: [Float], width: Int, height: Int) -> [Float] {
        neighborhoodExtrema(src, width: width, height: height, wantMin: true)
    }

    private static func dilate3(_ src: [Float], width: Int, height: Int) -> [Float] {
        neighborhoodExtrema(src, width: width, height: height, wantMin: false)
    }

    @_optimize(speed)
    private static func neighborhoodExtrema(
        _ src: [Float],
        width: Int,
        height: Int,
        wantMin: Bool
    ) -> [Float] {
        var input = src
        var out = [Float](repeating: 0, count: src.count)
        let err = input.withUnsafeMutableBufferPointer { srcPtr in
            out.withUnsafeMutableBufferPointer { dstPtr in
                var srcBuf = vImage_Buffer(
                    data: srcPtr.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.stride
                )
                var dstBuf = vImage_Buffer(
                    data: dstPtr.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.stride
                )
                if wantMin {
                    return vImageMin_PlanarF(&srcBuf, &dstBuf, nil, 0, 0, 3, 3, vImage_Flags(kvImageEdgeExtend))
                }
                return vImageMax_PlanarF(&srcBuf, &dstBuf, nil, 0, 0, 3, 3, vImage_Flags(kvImageEdgeExtend))
            }
        }
        if err == kvImageNoError {
            return out
        }
        for y in 0..<height {
            for x in 0..<width {
                var extremum = wantMin ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude
                for dy in -1...1 {
                    let yy = min(max(y + dy, 0), height - 1)
                    for dx in -1...1 {
                        let xx = min(max(x + dx, 0), width - 1)
                        let v = src[yy * width + xx]
                        if wantMin {
                            if v < extremum { extremum = v }
                        } else if v > extremum {
                            extremum = v
                        }
                    }
                }
                out[y * width + x] = extremum
            }
        }
        return out
    }

    private static func edgeMask(_ lChan: [Float], width: Int, height: Int, masking: Float) -> [Float] {
        var grad = [Float](repeating: 0, count: lChan.count)
        for y in 0..<height {
            for x in 0..<width {
                let xm = min(max(x - 1, 0), width - 1)
                let xp = min(max(x + 1, 0), width - 1)
                let ym = min(max(y - 1, 0), height - 1)
                let yp = min(max(y + 1, 0), height - 1)
                let gx = (lChan[y * width + xp] - lChan[y * width + xm]) * 0.5
                let gy = (lChan[yp * width + x] - lChan[ym * width + x]) * 0.5
                grad[y * width + x] = hypot(gx, gy)
            }
        }
        // cv2.blur 3x3, BORDER_REPLICATE — box mean.
        var blurred = [Float](repeating: 0, count: grad.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for dy in -1...1 {
                    let yy = min(max(y + dy, 0), height - 1)
                    for dx in -1...1 {
                        let xx = min(max(x + dx, 0), width - 1)
                        acc += grad[yy * width + xx]
                    }
                }
                blurred[y * width + x] = acc / 9
            }
        }
        let t = sharpenMaskTHi * masking
        return blurred.map { smoothstep(0.5 * t, t, $0) }
    }
}
