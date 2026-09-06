import Accelerate
import Foundation

/// Working-space output transform: Adobe RGB (1998) TRC.
///
/// A pure `563/256` power (`≈ 2.19921875`) with **no linear segment**. Mirrors NegPy
/// `working_oetf_encode` / `working_oetf_decode`. S3 ships the function; S4a applies it
/// as the last encode. Scan preview stays log-normalized until then.
public enum WorkingOETF: Sendable {
    /// Adobe RGB (1998) gamma: `563/256`.
    public static let gamma: Float = 563.0 / 256.0
    /// `256/563` — encode exponent. Matches NegPy `float32(1 / (563/256))`.
    public static let invGamma: Float = 256.0 / 563.0

    public static func encode(_ linear: Float) -> Float {
        pow(min(1, max(0, linear)), invGamma)
    }

    public static func decode(_ encoded: Float) -> Float {
        pow(max(0, encoded), gamma)
    }

    /// Scene-linear → display-encoded code values in `[0, 1]`.
    public static func encode(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        LinearRGBBuffer(
            width: buffer.width,
            height: buffer.height,
            pixels: applyPower(buffer.pixels, exponent: invGamma, clampHigh: true)
        )
    }

    /// Inverse of `encode`. Low side is clamped; high side is left open (NegPy).
    public static func decode(_ buffer: LinearRGBBuffer) -> LinearRGBBuffer {
        LinearRGBBuffer(
            width: buffer.width,
            height: buffer.height,
            pixels: applyPower(buffer.pixels, exponent: gamma, clampHigh: false)
        )
    }

    /// Neutral horizontal ramp in `[0, 1]`, left = 0, right = 1.
    public static func linearRamp(width: Int, height: Int) -> LinearRGBBuffer {
        precondition(width > 0 && height > 0, "OETF ramp size must be positive")
        var pixels = [Float](repeating: 0, count: width * height * 3)
        let denom = Float(max(width - 1, 1))
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x) / denom
                let i = (y * width + x) * 3
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            }
        }
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    @_optimize(speed)
    private static func applyPower(_ pixels: [Float], exponent: Float, clampHigh: Bool) -> [Float] {
        var x = pixels
        if clampHigh {
            vDSP.clip(x, to: 0...1, result: &x)
        } else {
            vDSP.threshold(x, to: 0, with: .clampToThreshold, result: &x)
        }
        let exponents = [Float](repeating: exponent, count: x.count)
        var out = [Float](repeating: 0, count: x.count)
        vForce.pow(bases: x, exponents: exponents, result: &out)
        return out
    }
}
