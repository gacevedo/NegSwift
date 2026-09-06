import Foundation

/// CIELAB in the Adobe RGB (1998) working space (D65). Linear RGB in, no OETF.
///
/// Mirrors NegPy `rgb_to_lab_working` / `lab_to_rgb_working` (`kernel/image/logic.py`).
public enum WorkingLab: Sendable {
    /// Adobe RGB (1998) → XYZ D65.
    public static let workingToXYZ: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (
        0.5767309, 0.1855540, 0.1881852,
        0.2973769, 0.6273491, 0.0752741,
        0.0270343, 0.0706872, 0.9911085
    )
    /// XYZ D65 → Adobe RGB (1998).
    public static let xyzToWorking: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (
        2.0413690, -0.5649464, -0.3446944,
        -0.9692660, 1.8760108, 0.0415560,
        0.0134474, -0.1183897, 1.0154096
    )
    public static let whiteX: Float = 0.95047
    public static let whiteY: Float = 1.00000
    public static let whiteZ: Float = 1.08883
    public static let eps: Float = 0.008856
    public static let kappa: Float = 7.787
    public static let linearOffset: Float = 16.0 / 116.0

    @_optimize(speed)
    public static func rgbToLab(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        var out = buffer.pixels
        let n = buffer.width * buffer.height
        let m = workingToXYZ
        for i in 0..<n {
            let o = i * 3
            let lab = rgbToLab(
                r: max(buffer.pixels[o], 0),
                g: max(buffer.pixels[o + 1], 0),
                b: max(buffer.pixels[o + 2], 0),
                m: m
            )
            out[o] = lab.0
            out[o + 1] = lab.1
            out[o + 2] = lab.2
        }
        return LinearRGBBuffer(width: buffer.width, height: buffer.height, pixels: out)
    }

    @_optimize(speed)
    public static func labToRgb(_ lab: LinearRGBBuffer) -> LinearRGBBuffer {
        var out = lab.pixels
        let n = lab.width * lab.height
        let m = xyzToWorking
        for i in 0..<n {
            let o = i * 3
            let rgb = labToRgb(l: lab.pixels[o], a: lab.pixels[o + 1], b: lab.pixels[o + 2], m: m)
            out[o] = rgb.0
            out[o + 1] = rgb.1
            out[o + 2] = rgb.2
        }
        return LinearRGBBuffer(width: lab.width, height: lab.height, pixels: out)
    }

    public static func rgbToLab(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        rgbToLab(r: max(r, 0), g: max(g, 0), b: max(b, 0), m: workingToXYZ)
    }

    public static func labToRgb(l: Float, a: Float, b: Float) -> (Float, Float, Float) {
        labToRgb(l: l, a: a, b: b, m: xyzToWorking)
    }

    /// Whether `(L, a, b)` decodes to linear working RGB within `[0, 1]` (±1e-4).
    public static func inGamut(l: Float, a: Float, b: Float) -> Bool {
        let rgb = labToRgb(l: l, a: a, b: b)
        let tol: Float = 1e-4
        return rgb.0 >= -tol && rgb.0 <= 1 + tol
            && rgb.1 >= -tol && rgb.1 <= 1 + tol
            && rgb.2 >= -tol && rgb.2 <= 1 + tol
    }

    @_optimize(speed)
    private static func rgbToLab(
        r: Float,
        g: Float,
        b: Float,
        m: (Float, Float, Float, Float, Float, Float, Float, Float, Float)
    ) -> (Float, Float, Float) {
        let xr = (m.0 * r + m.1 * g + m.2 * b) / whiteX
        let yr = (m.3 * r + m.4 * g + m.5 * b) / whiteY
        let zr = (m.6 * r + m.7 * g + m.8 * b) / whiteZ
        let fx = labF(xr)
        let fy = labF(yr)
        let fz = labF(zr)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    @_optimize(speed)
    private static func labToRgb(
        l: Float,
        a: Float,
        b: Float,
        m: (Float, Float, Float, Float, Float, Float, Float, Float, Float)
    ) -> (Float, Float, Float) {
        let fy = (l + 16) / 116
        let fx = a / 500 + fy
        let fz = fy - b / 200
        let xr = labFInv(fx) * whiteX
        let yr = labFInv(fy) * whiteY
        let zr = labFInv(fz) * whiteZ
        let r = m.0 * xr + m.1 * yr + m.2 * zr
        let g = m.3 * xr + m.4 * yr + m.5 * zr
        let bl = m.6 * xr + m.7 * yr + m.8 * zr
        return (max(r, 0), max(g, 0), max(bl, 0))
    }

    @_optimize(speed)
    private static func labF(_ t: Float) -> Float {
        t > eps ? cbrt(t) : kappa * t + linearOffset
    }

    @_optimize(speed)
    private static func labFInv(_ f: Float) -> Float {
        let f3 = f * f * f
        return f3 > eps ? f3 : (f - linearOffset) / kappa
    }
}
