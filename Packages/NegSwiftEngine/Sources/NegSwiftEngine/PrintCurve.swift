import Foundation

/// Asymmetric H&D print curve (toe-linear-shoulder). Mirrors NegPy `exposure/logic.py`.
public enum PrintCurve: Sendable {
    public static func defaultGradeRange() -> Double {
        ExposureConstants.autoGradeTarget
            * ExposureConstants.autoGradeNominalRatio
            * ExposureConstants.autoGradeNominalRange
    }

    public static func gradeToSlope(_ grade: Double, densityRange: Double?) -> Double {
        let rngIn = densityRange ?? defaultGradeRange()
        let er = min(max(grade, ExposureConstants.isoRMin), ExposureConstants.isoRMax) / 100
        let rng = min(max(abs(rngIn), 0.3), 3.5)
        let k = ExposureConstants.gradeContrastScale * rng / er
        return min(max(k, ExposureConstants.slopeMin), ExposureConstants.slopeMax)
    }

    public static func slopeToGrade(_ slope: Double, densityRange: Double?) -> Double {
        let rngIn = densityRange ?? defaultGradeRange()
        let rng = min(max(abs(rngIn), 0.3), 3.5)
        if slope <= 0 {
            return ExposureConstants.isoRMax
        }
        let er = ExposureConstants.gradeContrastScale * rng / slope
        return min(max(er * 100, ExposureConstants.isoRMin), ExposureConstants.isoRMax)
    }

    public static func invSoftplus(_ y: Double) -> Double {
        if y > 20 { return y }
        return log(expm1(max(y, 1e-12)))
    }

    public static func softplus(_ x: Double) -> Double {
        if x > 0 {
            return x + log1p(exp(-x))
        }
        return log1p(exp(x))
    }

    public static func fastSigmoid(_ x: Double) -> Double {
        if x >= 0 {
            let z = exp(-x)
            return 1 / (1 + z)
        }
        let z = exp(x)
        return z / (1 + z)
    }

    public static func referenceLinearValue(dMin: Double = 0, target: Double? = nil) -> Double {
        let t = target ?? ExposureConstants.anchorTargetDensity
        let dMax = ExposureConstants.dMax
        let aHL = ExposureConstants.shoulderSharpnessBase
        let aSH = ExposureConstants.toeSharpnessBase
        let v1 = dMax - invSoftplus(aSH * (dMax - t)) / aSH
        return dMin + invSoftplus(aHL * (v1 - dMin)) / aHL
    }

    public static func computePivot(
        slope: Double,
        density: Double,
        dMin: Double = 0,
        anchor: Double? = nil
    ) -> Double {
        let ref = anchor ?? ExposureConstants.assumedAnchor
        let vStar = referenceLinearValue(dMin: dMin)
        let base = ref - vStar / slope
        return base + (1 - density) * ExposureConstants.densityMultiplier
    }

    public static func effectiveGradeRange(
        autoNormalizeContrast: Bool,
        floorCeilRange: Double?,
        texturalRange: Double?
    ) -> Double? {
        if !autoNormalizeContrast {
            return floorCeilRange
        }
        guard let texturalRange, let floorCeilRange else {
            return defaultGradeRange()
        }
        let measured = abs(texturalRange)
        if measured < 1e-6 {
            return 3.5
        }
        let k = ExposureConstants.autoGradeTarget
        let q = ExposureConstants.autoGradeNominalRange / measured
        let strength = ExposureConstants.autoGradeStrength
        let factor = min(
            (1 - strength) + strength * q,
            q * ExposureConstants.autoGradeMaxOverfill
        )
        return k * abs(floorCeilRange) * factor
    }

    public static func shadowReachSlope(
        slope: Double,
        anchor: Double,
        shadowPoint: Double,
        dMin: Double = 0
    ) -> Double {
        let span = shadowPoint - anchor
        if span <= 1e-6 {
            return slope
        }
        let vBlack = referenceLinearValue(dMin: dMin, target: ExposureConstants.shadowReachDensity)
        let needed = (vBlack - referenceLinearValue(dMin: dMin)) / span
        return min(max(slope, needed), ExposureConstants.slopeMax)
    }

    public static func highlightHoldOffset(
        slope: Double,
        pivot: Double,
        highlightPoint: Double,
        dMin: Double = 0
    ) -> Double {
        let target = ExposureConstants.highlightHoldDensity
        if target <= 0 {
            return 0
        }
        let v = slope * (highlightPoint - pivot)
        let vHold = referenceLinearValue(dMin: dMin, target: target)
        if v >= vHold {
            return 0
        }
        let zHi = ExposureConstants.anchorTargetDensity + ExposureConstants.zoneDensityHighlightOffset
        let w = 1 - fastSigmoid(ExposureConstants.zoneDensitySharpness * (v - zHi))
        return min((vHold - v) / max(w, 1e-6), ExposureConstants.highlightHoldMax)
    }

    public static func gradeCoupledShape(slopeG: Double, toe: Double, shoulder: Double) -> (Double, Double) {
        var slopeNorm = (slopeG - ExposureConstants.slopeMin)
            / (ExposureConstants.slopeMax - ExposureConstants.slopeMin)
        slopeNorm = min(max(slopeNorm, 0), 1)
        let toeEff = toe + ExposureConstants.toeGradeStrength * slopeNorm
        let shoulderEff = shoulder + ExposureConstants.shoulderGradeStrength * slopeNorm
        return (toeEff, shoulderEff)
    }

    public static func gradeTrimMult(grade: Double, trim: Double) -> Double {
        let r0 = min(max(grade, ExposureConstants.isoRMin), ExposureConstants.isoRMax)
        let r1 = min(max(r0 + trim, ExposureConstants.isoRMin), ExposureConstants.isoRMax)
        return r0 / r1
    }

    public static func splitGradeDeltas(
        grade: Double,
        shadowGrade: Double,
        highlightGrade: Double
    ) -> ((Double, Double, Double), (Double, Double, Double)) {
        func triple(_ g: Double) -> (Double, Double, Double) {
            let m = gradeTrimMult(grade: grade, trim: g) - 1
            return (m, m, m)
        }
        return (triple(shadowGrade), triple(highlightGrade))
    }

    public static func luminanceDensityRange(_ bounds: LogNegativeBounds) -> Double {
        let rr = abs(bounds.ceils.0 - bounds.floors.0)
        let rg = abs(bounds.ceils.1 - bounds.floors.1)
        let rb = abs(bounds.ceils.2 - bounds.floors.2)
        return ExposureConstants.lumaR * rr + ExposureConstants.lumaG * rg + ExposureConstants.lumaB * rb
    }

    /// Scene-linear reflectance after the H&D curve. OETF is applied by the caller.
    public static func apply(
        _ image: LinearRGBBuffer,
        pivots: (Double, Double, Double),
        slopes: (Double, Double, Double),
        curvatures: (Double, Double, Double) = (0, 0, 0),
        toe: Double = 0,
        toeWidth: Double = 2.5,
        shoulder: Double = 0,
        shoulderWidth: Double = 2.5,
        dMin: Double = 0,
        midtoneGamma: Double = ExposureConstants.paperMidtoneGamma,
        bpc: Bool = false,
        shadowDensity: Double = 0,
        highlightDensity: Double = 0,
        shadowGradeDeltas: (Double, Double, Double) = (0, 0, 0),
        highlightGradeDeltas: (Double, Double, Double) = (0, 0, 0),
        cmyOffsets: (Double, Double, Double) = (0, 0, 0)
    ) -> LinearRGBBuffer {
        let ts = ExposureConstants.toeShoulderStrength
        let toe3 = (toe * ts, toe * ts, toe * ts)
        let sh3 = (shoulder * ts, shoulder * ts, shoulder * ts)
        let tw = (toeWidth, toeWidth, toeWidth)
        let sw = (shoulderWidth, shoulderWidth, shoulderWidth)
        return applyKernel(
            image,
            pivots: pivots,
            slopes: slopes,
            curvatures: curvatures,
            toe: toe3,
            shoulder: sh3,
            toeWidth: tw,
            shoulderWidth: sw,
            dMinRGB: (dMin, dMin, dMin),
            midtoneGamma: (midtoneGamma, midtoneGamma, midtoneGamma),
            bpc: bpc,
            shadowDensity: shadowDensity,
            highlightDensity: highlightDensity,
            shadowGrade: shadowGradeDeltas,
            highlightGrade: highlightGradeDeltas,
            cmyOffsets: cmyOffsets
        )
    }

    static func applyKernel(
        _ image: LinearRGBBuffer,
        pivots: (Double, Double, Double),
        slopes: (Double, Double, Double),
        curvatures: (Double, Double, Double),
        toe: (Double, Double, Double),
        shoulder: (Double, Double, Double),
        toeWidth: (Double, Double, Double),
        shoulderWidth: (Double, Double, Double),
        dMinRGB: (Double, Double, Double),
        midtoneGamma: (Double, Double, Double),
        bpc: Bool,
        shadowDensity: Double,
        highlightDensity: Double,
        shadowGrade: (Double, Double, Double),
        highlightGrade: (Double, Double, Double),
        cmyOffsets: (Double, Double, Double)
    ) -> LinearRGBBuffer {
        let dMax = ExposureConstants.dMax
        let aToeBase = ExposureConstants.toeSharpnessBase
        let aShBase = ExposureConstants.shoulderSharpnessBase
        let widthRef = ExposureConstants.toeShoulderWidthRef
        let toeHeight = ExposureConstants.toeHeight
        let shHeight = ExposureConstants.shoulderHeight
        let zoneCenter = ExposureConstants.anchorTargetDensity
        let zoneShCenter = zoneCenter + ExposureConstants.zoneDensityShadowOffset
        let zoneHiCenter = zoneCenter + ExposureConstants.zoneDensityHighlightOffset
        let zoneK = ExposureConstants.zoneDensitySharpness
        let vStar = referenceLinearValue(dMin: dMinRGB.0)
        let gammaWidth = ExposureConstants.paperGammaWidth
        let eps = 1e-6

        let pivotA = [pivots.0, pivots.1, pivots.2]
        let slopeA = [slopes.0, slopes.1, slopes.2]
        let curvA = [curvatures.0, curvatures.1, curvatures.2]
        let toeA = [toe.0, toe.1, toe.2]
        let shA = [shoulder.0, shoulder.1, shoulder.2]
        let twA = [toeWidth.0, toeWidth.1, toeWidth.2]
        let swA = [shoulderWidth.0, shoulderWidth.1, shoulderWidth.2]
        let dMinA = [dMinRGB.0, dMinRGB.1, dMinRGB.2]
        let gammaA = [midtoneGamma.0, midtoneGamma.1, midtoneGamma.2]
        let sgA = [shadowGrade.0, shadowGrade.1, shadowGrade.2]
        let hgA = [highlightGrade.0, highlightGrade.1, highlightGrade.2]
        let cmyA = [cmyOffsets.0, cmyOffsets.1, cmyOffsets.2]

        var aHL = [Double](repeating: 0, count: 3)
        var aSH = [Double](repeating: 0, count: 3)
        var dMinEff = [Double](repeating: 0, count: 3)
        var dMaxEff = [Double](repeating: 0, count: 3)
        var bpcBlack = [Double](repeating: 0, count: 3)
        for ch in 0..<3 {
            aHL[ch] = aShBase * widthRef / max(swA[ch], eps)
            let aShW = aToeBase * widthRef / max(twA[ch], eps)
            let tCh = toeA[ch]
            let dMaxBase: Double
            if tCh >= 0 {
                dMaxBase = dMax - tCh * toeHeight
                aSH[ch] = aShW
            } else {
                dMaxBase = dMax
                aSH[ch] = aShW * (1 - tCh * 4)
            }
            var dmn = dMinA[ch] + shA[ch] * shHeight
            if dmn < 0 { dmn = 0 }
            var dmx = dMaxBase
            if dmx < dmn + 0.1 { dmx = dmn + 0.1 }
            dMinEff[ch] = dmn
            dMaxEff[ch] = dmx
            var db = dMax
            if tCh < 0 {
                db = dMax + tCh * toeHeight
            }
            bpcBlack[ch] = pow(10, -db)
        }

        let useSplit = sgA.contains(where: { $0 != 0 }) || hgA.contains(where: { $0 != 0 })
        let useZone = shadowDensity != 0 || highlightDensity != 0

        var out = image.pixels
        let n = image.width * image.height
        for i in 0..<n {
            var dens = [Double](repeating: 0, count: 3)
            for ch in 0..<3 {
                let val = Double(image.pixels[i * 3 + ch]) + cmyA[ch]
                var v = slopeA[ch] * (val - pivotA[ch]) + curvA[ch] * val * val
                if gammaA[ch] != 0 {
                    v += gammaA[ch] * gammaWidth * tanh((v - vStar) / gammaWidth)
                }
                if useSplit {
                    let wGsh = fastSigmoid(zoneK * (v - zoneShCenter))
                    let wGhi = 1 - fastSigmoid(zoneK * (v - zoneHiCenter))
                    v += sgA[ch] * wGsh * (v - zoneShCenter) + hgA[ch] * wGhi * (v - zoneHiCenter)
                }
                if useZone {
                    let wZsh = fastSigmoid(zoneK * (v - zoneShCenter))
                    let wZhi = 1 - fastSigmoid(zoneK * (v - zoneHiCenter))
                    v += shadowDensity * wZsh + highlightDensity * wZhi
                }
                let v1 = dMinEff[ch] + softplus(aHL[ch] * (v - dMinEff[ch])) / aHL[ch]
                dens[ch] = dMaxEff[ch] - softplus(aSH[ch] * (dMaxEff[ch] - v1)) / aSH[ch]
            }
            for ch in 0..<3 {
                var t = pow(10, -dens[ch])
                if bpc {
                    t = (t - bpcBlack[ch]) / (1 - bpcBlack[ch])
                }
                if t < 0 { t = 0 }
                if t > 1 { t = 1 }
                out[i * 3 + ch] = Float(t)
            }
        }
        return LinearRGBBuffer(width: image.width, height: image.height, pixels: out)
    }
}
