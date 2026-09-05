import Foundation

/// Photometric print: H&D + density/grade + zone + CMY + cast + BPC.
/// Auto Density / Auto Grade run when ``PrintConfig`` flags are on (app default).
/// ``PrintConfig.s4aPin`` leaves them off for the MAE gate.
public enum PhotometricPrint: Sendable {
    public struct CurveParams: Sendable {
        public var slopes: (Double, Double, Double)
        public var pivots: (Double, Double, Double)
        public var curvatures: (Double, Double, Double)
    }

    public static func process(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        config: PrintConfig = .s4aPin
    ) -> LinearRGBBuffer {
        let bounds = LogNormalization.analyzeBounds(
            linear: linear,
            processMode: processMode,
            analysisBuffer: config.analysisBuffer
        )
        let normalized = LogNormalization.process(
            linear: linear,
            processMode: processMode,
            analysisBuffer: config.analysisBuffer,
            bounds: bounds
        )
        return applyPrint(normalized: normalized, linear: linear, bounds: bounds, processMode: processMode, config: config)
    }

    public static func applyPrint(
        normalized: LinearRGBBuffer,
        linear: LinearRGBBuffer,
        bounds: LogNegativeBounds,
        processMode: FilmProcessMode,
        config: PrintConfig
    ) -> LinearRGBBuffer {
        let lumRange = PrintCurve.luminanceDensityRange(bounds)
        let grid = CastMetering.analysisGrid(linear: linear, analysisBuffer: config.analysisBuffer)
        var strength = Double(config.castRemovalStrength)
        var shadowNorm: (Double, Double, Double)?
        var axis: NeutralAxisRefs?
        if processMode != .bwNegative, strength > 0 {
            let refs = CastMetering.shadowRefs(grid)
            shadowNorm = CastMetering.normalizeRefs(refs, bounds: bounds)
            axis = CastMetering.measureNeutralAxis(grid: grid, bounds: bounds)
            strength = CastMetering.effectiveStrength(strength, confidence: axis?.confidence)
        }
        if processMode == .bwNegative {
            strength = 0
            shadowNorm = nil
            axis = nil
        }

        let meteredAnchor = config.autoExposure
            ? ExposureMetering.measureAnchorFromLog(grid, bounds: bounds)
            : nil
        let texturalRange = config.autoNormalizeContrast
            ? ExposureMetering.measureTexturalRangeFromLog(grid)
            : nil
        let shadowPoint = config.autoNormalizeContrast
            ? ExposureMetering.measureShadowPointFromLog(grid, bounds: bounds)
            : nil
        let highlightPoint = config.autoNormalizeContrast
            ? ExposureMetering.measureHighlightPointFromLog(grid, bounds: bounds)
            : nil

        let params = perChannelCurveParams(
            grade: Double(config.grade),
            density: Double(config.density),
            lumRange: lumRange,
            strength: strength,
            shadowRefsNorm: shadowNorm,
            axis: axis,
            bounds: bounds,
            dMin: config.dMin,
            autoNormalizeContrast: config.autoNormalizeContrast,
            texturalRange: texturalRange,
            anchor: meteredAnchor,
            shadowPoint: shadowPoint
        )
        let (toeEff, shEff) = PrintCurve.gradeCoupledShape(
            slopeG: params.slopes.1,
            toe: Double(config.toe),
            shoulder: Double(config.shoulder)
        )
        let (sg, hg) = PrintCurve.splitGradeDeltas(
            grade: Double(config.grade),
            shadowGrade: Double(config.shadowGrade),
            highlightGrade: Double(config.highlightGrade)
        )
        let highlightHold: Double
        if config.autoNormalizeContrast, let highlightPoint {
            highlightHold = PrintCurve.highlightHoldOffset(
                slope: params.slopes.1,
                pivot: params.pivots.1,
                highlightPoint: highlightPoint,
                dMin: config.dMin
            )
        } else {
            highlightHold = 0
        }

        var image = normalized
        if processMode == .bwNegative {
            image = collapseToLuma(image)
        }

        let cmyOffsets = PrintCurve.filtrationOffsets(
            cyan: Double(config.wbCyan),
            magenta: Double(config.wbMagenta),
            yellow: Double(config.wbYellow),
            bounds: bounds
        )
        var printed = PrintCurve.apply(
            image,
            pivots: params.pivots,
            slopes: params.slopes,
            curvatures: params.curvatures,
            toe: toeEff,
            toeWidth: Double(config.toeWidth),
            shoulder: shEff,
            shoulderWidth: Double(config.shoulderWidth),
            dMin: config.dMin,
            midtoneGamma: ExposureConstants.paperMidtoneGamma,
            bpc: config.bpc,
            shadowDensity: Double(config.shadowDensity),
            highlightDensity: Double(config.highlightDensity) + highlightHold,
            shadowGradeDeltas: sg,
            highlightGradeDeltas: hg,
            cmyOffsets: cmyOffsets
        )
        if processMode == .bwNegative {
            printed = collapseToLuma(printed)
        }
        return WorkingOETF.encode(printed)
    }

    public static func perChannelCurveParams(
        grade: Double,
        density: Double,
        lumRange: Double?,
        strength: Double,
        shadowRefsNorm: (Double, Double, Double)?,
        axis: NeutralAxisRefs?,
        bounds: LogNegativeBounds,
        dMin: Double,
        autoNormalizeContrast: Bool = false,
        texturalRange: Double? = nil,
        anchor: Double? = nil,
        shadowPoint: Double? = nil
    ) -> CurveParams {
        let rEff = PrintCurve.effectiveGradeRange(
            autoNormalizeContrast: autoNormalizeContrast,
            floorCeilRange: lumRange,
            texturalRange: texturalRange
        )
        var baseSlope = PrintCurve.gradeToSlope(grade, densityRange: rEff)
        if autoNormalizeContrast, let shadowPoint {
            let ref = anchor ?? ExposureConstants.assumedAnchor
            baseSlope = PrintCurve.shadowReachSlope(
                slope: baseSlope,
                anchor: ref,
                shadowPoint: shadowPoint,
                dMin: dMin
            )
        }
        let slopeMin = ExposureConstants.slopeMin
        let slopeMax = ExposureConstants.slopeMax
        let eps = 1e-6

        if strength > 0, let axis {
            return solveNeutralAxis(
                axis: axis,
                bounds: bounds,
                baseSlope: baseSlope,
                density: density,
                dMin: dMin,
                strength: strength,
                anchor: anchor
            )
        }

        if strength > 0, let shadowRefsNorm {
            let anchorVal = anchor ?? ExposureConstants.assumedAnchor
            let limit = ExposureConstants.castRemovalMaxOffset
            let rGreen = shadowRefsNorm.1
            let numer = anchorVal - rGreen
            let refs = [shadowRefsNorm.0, shadowRefsNorm.1, shadowRefsNorm.2]
            var slopes = [0.0, 0.0, 0.0]
            var pivots = [0.0, 0.0, 0.0]
            for ch in 0..<3 {
                let cast = min(max(strength * (rGreen - refs[ch]), -limit), limit)
                let denom = anchorVal - (rGreen - cast)
                var slopeCh = baseSlope
                if ch != 1, abs(denom) >= eps {
                    slopeCh = min(max(baseSlope * numer / denom, slopeMin), slopeMax)
                }
                slopeCh = min(max(slopeCh, slopeMin), slopeMax)
                slopes[ch] = slopeCh
                pivots[ch] = PrintCurve.computePivot(slope: slopeCh, density: density, dMin: dMin, anchor: anchor)
            }
            return CurveParams(
                slopes: (slopes[0], slopes[1], slopes[2]),
                pivots: (pivots[0], pivots[1], pivots[2]),
                curvatures: (0, 0, 0)
            )
        }

        let s0 = min(max(baseSlope, slopeMin), slopeMax)
        let p = PrintCurve.computePivot(slope: s0, density: density, dMin: dMin, anchor: anchor)
        return CurveParams(slopes: (s0, s0, s0), pivots: (p, p, p), curvatures: (0, 0, 0))
    }

    private static func solveNeutralAxis(
        axis: NeutralAxisRefs,
        bounds: LogNegativeBounds,
        baseSlope: Double,
        density: Double,
        dMin: Double,
        strength: Double,
        anchor: Double?
    ) -> CurveParams {
        let midNorm = CastMetering.normalizeRefs(axis.midtone, bounds: bounds)
        let shNorm = CastMetering.normalizeRefs(axis.shadow, bounds: bounds)
        let hlNorm = axis.highlight.map { CastMetering.normalizeRefs($0, bounds: bounds) }
        let limit = ExposureConstants.midtoneCastMaxOffset
        let curvLim = ExposureConstants.neutralAxisCurvMaxRatio
        let slopeMin = ExposureConstants.slopeMin
        let slopeMax = ExposureConstants.slopeMax
        let eps = 1e-6
        let mid = [midNorm.0, midNorm.1, midNorm.2]
        let sh = [shNorm.0, shNorm.1, shNorm.2]
        let hl = hlNorm.map { [$0.0, $0.1, $0.2] }
        let slopeG = min(max(baseSlope, slopeMin), slopeMax)
        let pivotG = PrintCurve.computePivot(slope: slopeG, density: density, dMin: dMin, anchor: anchor)
        func target(_ g: Double) -> Double { slopeG * (g - pivotG) }
        let tM = target(mid[1])
        let tS = target(sh[1])
        let hG = hl?[1]

        func clampDev(_ g: Double, _ v: Double) -> Double {
            g + min(max(strength * (v - g), -limit), limit)
        }

        var slopes = [0.0, 0.0, 0.0]
        var pivots = [0.0, 0.0, 0.0]
        var curvs = [0.0, 0.0, 0.0]
        for ch in 0..<3 {
            if ch == 1 {
                slopes[ch] = slopeG
                pivots[ch] = pivotG
                curvs[ch] = 0
                continue
            }
            let uM = clampDev(mid[1], mid[ch])
            let uS = clampDev(sh[1], sh[ch])
            var curv = 0.0
            if let hG, let hl {
                let uH = clampDev(hG, hl[ch])
                curv = solveC2(u: [uH, uM, uS], v: [target(hG), tM, tS]) ?? 0
                curv = min(max(curv, -curvLim * slopeG), curvLim * slopeG)
            }
            let du = uM - uS
            var slopeCh = abs(du) < eps ? slopeG : ((tM - tS) - curv * (uM * uM - uS * uS)) / du
            slopeCh = min(max(slopeCh, slopeMin), slopeMax)
            let pivotCh = abs(slopeCh) > eps ? uM - (tM - curv * uM * uM) / slopeCh : pivotG
            slopes[ch] = slopeCh
            pivots[ch] = pivotCh
            curvs[ch] = curv
        }
        return CurveParams(
            slopes: (slopes[0], slopes[1], slopes[2]),
            pivots: (pivots[0], pivots[1], pivots[2]),
            curvatures: (curvs[0], curvs[1], curvs[2])
        )
    }

    private static func solveC2(u: [Double], v: [Double]) -> Double? {
        // Replace last column with v in the 3x3 [1, u, u²] and divide by det.
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let a = [
            [1.0, u[0], u[0] * u[0]],
            [1.0, u[1], u[1] * u[1]],
            [1.0, u[2], u[2] * u[2]],
        ]
        let d = det(a)
        if abs(d) < 1e-12 { return nil }
        let a2 = [
            [1.0, u[0], v[0]],
            [1.0, u[1], v[1]],
            [1.0, u[2], v[2]],
        ]
        return det(a2) / d
    }

    private static func collapseToLuma(_ image: LinearRGBBuffer) -> LinearRGBBuffer {
        var pixels = image.pixels
        let n = image.width * image.height
        for i in 0..<n {
            let y = Float(ExposureConstants.lumaR) * pixels[i * 3]
                + Float(ExposureConstants.lumaG) * pixels[i * 3 + 1]
                + Float(ExposureConstants.lumaB) * pixels[i * 3 + 2]
            pixels[i * 3] = y
            pixels[i * 3 + 1] = y
            pixels[i * 3 + 2] = y
        }
        return LinearRGBBuffer(width: image.width, height: image.height, pixels: pixels)
    }
}
