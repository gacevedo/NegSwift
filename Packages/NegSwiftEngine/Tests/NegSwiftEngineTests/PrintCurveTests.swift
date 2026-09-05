import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of NegPy `tests/test_characteristic_curve.py` (S4a + kernel params for S4b).
struct PrintCurveTests {
    @Test func monotoneDecreasing() {
        for grade in [50.0, 115.0, 180.0] {
            let (_, out) = curve(grade: grade)
            for i in 1..<out.count {
                #expect(out[i] - out[i - 1] <= 1e-6, "non-monotone at grade \(grade)")
            }
        }
    }

    @Test func endpointsReachPaperWhiteAndBlack() {
        let (_, out) = curve()
        let d = out.map(outputToDensity)
        #expect(abs(d[0] - ExposureConstants.dMin) < 0.25)
        #expect(abs(d[d.count - 1] - ExposureConstants.dMax) < 0.4)
    }

    @Test func toeActsOnShadowsNotHighlights() {
        let (x, base) = curve()
        let (_, toed) = curve(toe: 1)
        var maxSh = 0.0
        for i in x.indices {
            if x[i] > 0.8 {
                maxSh = max(maxSh, abs(toed[i] - base[i]))
            }
            if x[i] < 0.2 {
                #expect(abs(toed[i] - base[i]) < 0.01)
            }
        }
        #expect(maxSh > 0.02)
    }

    @Test func shoulderActsOnHighlightsNotShadows() {
        let (x, base) = curve()
        let (_, shOut) = curve(shoulder: 1)
        var maxHi = 0.0
        for i in x.indices {
            if x[i] < 0.2 {
                maxHi = max(maxHi, abs(shOut[i] - base[i]))
            }
            if x[i] > 0.8 {
                #expect(abs(shOut[i] - base[i]) < 0.01)
            }
        }
        #expect(maxHi > 0.02)
    }

    @Test func toePositiveLiftsShadows() {
        let (x, base) = curve()
        let (_, toed) = curve(toe: 1)
        let sh = x.indices.filter { x[$0] > 0.85 }
        let meanToed = sh.reduce(0.0) { $0 + toed[$1] } / Double(sh.count)
        let meanBase = sh.reduce(0.0) { $0 + base[$1] } / Double(sh.count)
        #expect(meanToed > meanBase)
    }

    @Test func shoulderPositiveDarkensHighlights() {
        let (x, base) = curve()
        let (_, shOut) = curve(shoulder: 1)
        let hi = x.indices.filter { x[$0] < 0.15 }
        let meanOut = hi.reduce(0.0) { $0 + shOut[$1] } / Double(hi.count)
        let meanBase = hi.reduce(0.0) { $0 + base[$1] } / Double(hi.count)
        #expect(meanOut < meanBase)
    }

    @Test func defaultCurveShape() {
        let (x, out) = curve()
        let idx = [0, 64, 128, 192, 256]
        let golden = [0.922, 0.783, 0.4, 0.168, 0.098]
        for (i, g) in zip(idx, golden) {
            #expect(abs(out[i] - g) < 0.03, "x=\(x[i])")
        }
    }

    @Test func fullToeLiftStrength() {
        let (_, out) = curve(toe: 1)
        let d = outputToDensity(out[out.count - 1])
        let expected = ExposureConstants.dMax - ExposureConstants.toeShoulderStrength * ExposureConstants.toeHeight
        #expect(abs(d - expected) < 0.1)
        #expect(expected < 1.7)
    }

    @Test func referencePrintsAtTargetGradeInvariant() {
        let dMin = ExposureConstants.dMin
        let xRef = Float(ExposureConstants.assumedAnchor)
        let target = ExposureConstants.anchorTargetDensity
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: [Float](repeating: xRef, count: 4 * 4 * 3))
        for grade in [60.0, 115.0, 170.0] {
            let slope = PrintCurve.gradeToSlope(grade, densityRange: 1.3)
            let pivot = PrintCurve.computePivot(slope: slope, density: 1, dMin: dMin)
            let lin = PrintCurve.apply(img, pivots: (pivot, pivot, pivot), slopes: (slope, slope, slope), dMin: dMin)
            let enc = WorkingOETF.encode(lin)
            let dOut = outputToDensity(Double(enc.pixels[0]))
            #expect(abs(dOut - target) < 0.0015, "grade=\(grade)")
        }
    }

    @Test func gradeSlopeRoundtrip() {
        for grade in [50.0, 90.0, 115.0, 150.0, 180.0] {
            let r = 1.4
            #expect(abs(PrintCurve.slopeToGrade(PrintCurve.gradeToSlope(grade, densityRange: r), densityRange: r) - grade) < 0.015)
        }
    }

    @Test func splitGradeSignConvention() {
        let (sg, hg) = PrintCurve.splitGradeDeltas(grade: 115, shadowGrade: -30, highlightGrade: 30)
        #expect(sg.0 > 0)
        #expect(hg.0 < 0)
        let zero = PrintCurve.splitGradeDeltas(grade: 115, shadowGrade: 0, highlightGrade: 0)
        #expect(zero.0 == (0, 0, 0))
        #expect(zero.1 == (0, 0, 0))
    }

    @Test func shadowLiftActsOnShadowsSparesMids() {
        let (x, base) = curve()
        let (_, out) = curve(shadowDensity: -0.9)
        var dSh = 0.0, dHi = 0.0, dMid = 0.0
        var meanShOut = 0.0, meanShBase = 0.0, nSh = 0
        for i in x.indices {
            let d = abs(out[i] - base[i])
            if x[i] > 0.8 {
                dSh = max(dSh, d)
                meanShOut += out[i]
                meanShBase += base[i]
                nSh += 1
            }
            if x[i] < 0.2 { dHi = max(dHi, d) }
            if x[i] > 0.35 && x[i] < 0.55 { dMid = max(dMid, d) }
        }
        #expect(dSh > 0.1)
        #expect(dSh > 10 * dHi)
        #expect(dSh > 3 * dMid)
        #expect(meanShOut / Double(nSh) > meanShBase / Double(nSh))
    }

    @Test func highlightBurnActsOnHighlightsSparesShadows() {
        let (x, base) = curve()
        let (_, out) = curve(highlightDensity: 0.5)
        var dSh = 0.0, dHi = 0.0
        var meanHiOut = 0.0, meanHiBase = 0.0, nHi = 0
        for i in x.indices {
            let d = abs(out[i] - base[i])
            if x[i] > 0.8 { dSh = max(dSh, d) }
            if x[i] < 0.3 {
                dHi = max(dHi, d)
                meanHiOut += out[i]
                meanHiBase += base[i]
                nHi += 1
            }
        }
        #expect(dHi > 0.1)
        #expect(dHi > 20 * dSh)
        #expect(meanHiOut / Double(nHi) < meanHiBase / Double(nHi))
    }

    @Test func zoneOffsetsStayInsidePaperLimits() {
        for (sd, hd) in [(0.9, 0.0), (0.0, -0.5)] {
            let (_, out) = curve(shadowDensity: sd, highlightDensity: hd)
            let d = out.map(outputToDensity)
            #expect(d.max()! <= ExposureConstants.dMax + 1e-6)
            #expect(d.min()! >= 0)
            for i in 1..<out.count {
                #expect(out[i] - out[i - 1] <= 1e-6, "zone offset broke monotonicity sd=\(sd) hd=\(hd)")
            }
        }
    }

    @Test func shadowGradeActsOnShadowsSparesMids() {
        let (x, base) = curve()
        let (_, out) = curve(shadowGrade: 30)
        let dBase = base.map(outputToDensity)
        let dOut = out.map(outputToDensity)
        var dSh = 0.0, dHi = 0.0, dMid = 0.0
        var meanShOut = 0.0, meanShBase = 0.0, nSh = 0
        for i in x.indices {
            let d = abs(dOut[i] - dBase[i])
            if x[i] > 0.8 {
                dSh = max(dSh, d)
                meanShOut += dOut[i]
                meanShBase += dBase[i]
                nSh += 1
            }
            if x[i] < 0.2 { dHi = max(dHi, d) }
            if x[i] > 0.35 && x[i] < 0.55 { dMid = max(dMid, d) }
        }
        #expect(dSh > 0.05)
        #expect(dSh > 10 * dHi)
        #expect(dSh > 3 * dMid)
        #expect(meanShOut / Double(nSh) < meanShBase / Double(nSh))
    }

    @Test func highlightGradeActsOnHighlightsSparesShadows() {
        let (x, base) = curve()
        let (_, out) = curve(highlightGrade: 30)
        let dBase = base.map(outputToDensity)
        let dOut = out.map(outputToDensity)
        var dSh = 0.0, dHi = 0.0
        var meanHiOut = 0.0, meanHiBase = 0.0, nHi = 0
        for i in x.indices {
            let d = abs(dOut[i] - dBase[i])
            if x[i] > 0.8 { dSh = max(dSh, d) }
            if x[i] < 0.3 {
                dHi = max(dHi, d)
                meanHiOut += dOut[i]
                meanHiBase += dBase[i]
                nHi += 1
            }
        }
        #expect(dHi > 0.03)
        #expect(dHi > 10 * dSh)
        #expect(meanHiOut / Double(nHi) > meanHiBase / Double(nHi))
    }

    @Test func stackedZoneAndSplitGradeStayMonotoneAndBounded() {
        for grade in [50.0, 115.0, 180.0] {
            for sg in [-50.0, 50.0] {
                for hg in [-50.0, 50.0] {
                    for (sd, hd) in [(0.0, 0.0), (-0.9, -0.5), (0.9, 0.5)] {
                        let (_, out) = curve(
                            grade: grade,
                            shadowDensity: sd,
                            highlightDensity: hd,
                            shadowGrade: sg,
                            highlightGrade: hg
                        )
                        for i in 1..<out.count {
                            #expect(
                                out[i] - out[i - 1] <= 1e-6,
                                "non-monotone at grade=\(grade) sg=\(sg) hg=\(hg) sd=\(sd) hd=\(hd)"
                            )
                        }
                        let d = out.map(outputToDensity)
                        #expect(d.max()! <= ExposureConstants.dMax + 1e-6)
                        #expect(d.min()! >= 0)
                    }
                }
            }
        }
    }

    @Test func filtrationOffsetsAreRangeInvariantDensity() {
        let cmyMax = ExposureConstants.cmyMaxDensity
        for rng in [0.8, 1.3, 2.2] {
            let bounds = LogNegativeBounds(floors: (-rng, -rng, -rng), ceils: (0, 0, 0))
            let off = PrintCurve.filtrationOffsets(cyan: 1, magenta: 0.5, yellow: 0, bounds: bounds)
            #expect(abs(off.0 * rng - cmyMax) < 1e-6)
            #expect(abs(off.1 * rng - 0.5 * cmyMax) < 1e-6)
            #expect(off.2 == 0)
        }
    }

    @Test func filtrationOffsetsNilBoundsUseUnitRange() {
        let off = PrintCurve.filtrationOffsets(cyan: 1, magenta: 0, yellow: 0, bounds: nil)
        #expect(abs(off.0 - ExposureConstants.cmyMaxDensity) < 1e-6)
    }

    @Test func filtrationOffsetsReversedBoundsKeepDirection() {
        let fwd = PrintCurve.filtrationOffsets(
            cyan: 1, magenta: 1, yellow: 1,
            bounds: LogNegativeBounds(floors: (-1.5, -1.5, -1.5), ceils: (0, 0, 0))
        )
        let rev = PrintCurve.filtrationOffsets(
            cyan: 1, magenta: 1, yellow: 1,
            bounds: LogNegativeBounds(floors: (0, 0, 0), ceils: (-1.5, -1.5, -1.5))
        )
        #expect(fwd == rev)
    }

    @Test func yellowOffsetReducesBlueTransmittance() {
        let img = LinearRGBBuffer(width: 10, height: 10, pixels: [Float](repeating: 0.5, count: 10 * 10 * 3))
        let base = PrintCurve.apply(
            img,
            pivots: (0.5, 0.5, 0.5),
            slopes: (1, 1, 1),
            midtoneGamma: 0
        )
        let yellow = PrintCurve.apply(
            img,
            pivots: (0.5, 0.5, 0.5),
            slopes: (1, 1, 1),
            midtoneGamma: 0,
            cmyOffsets: (0, 0, 0.5)
        )
        var baseB: Double = 0
        var yellowB: Double = 0
        let n = 10 * 10
        for i in 0..<n {
            baseB += Double(base.pixels[i * 3 + 2])
            yellowB += Double(yellow.pixels[i * 3 + 2])
        }
        #expect(yellowB / Double(n) < baseB / Double(n))
    }

    private func curve(
        toe: Double = 0,
        shoulder: Double = 0,
        grade: Double = 115,
        density: Double = 1,
        lumRange: Double = 1.3,
        shadowDensity: Double = 0,
        highlightDensity: Double = 0,
        shadowGrade: Double = 0,
        highlightGrade: Double = 0
    ) -> ([Double], [Double]) {
        let n = 257
        var pixels = [Float](repeating: 0, count: n * 3)
        var x = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let v = Float(i) / Float(n - 1)
            x[i] = Double(v)
            pixels[i * 3] = v
            pixels[i * 3 + 1] = v
            pixels[i * 3 + 2] = v
        }
        let ramp = LinearRGBBuffer(width: n, height: 1, pixels: pixels)
        let dMin = ExposureConstants.dMin
        let slope = PrintCurve.gradeToSlope(grade, densityRange: lumRange)
        let pivot = PrintCurve.computePivot(slope: slope, density: density, dMin: dMin)
        let (sg, hg) = PrintCurve.splitGradeDeltas(grade: grade, shadowGrade: shadowGrade, highlightGrade: highlightGrade)
        let lin = PrintCurve.apply(
            ramp,
            pivots: (pivot, pivot, pivot),
            slopes: (slope, slope, slope),
            toe: toe,
            shoulder: shoulder,
            dMin: dMin,
            shadowDensity: shadowDensity,
            highlightDensity: highlightDensity,
            shadowGradeDeltas: sg,
            highlightGradeDeltas: hg
        )
        let enc = WorkingOETF.encode(lin)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = Double(enc.pixels[i * 3])
        }
        return (x, out)
    }

    private func outputToDensity(_ s: Double) -> Double {
        let t = Double(WorkingOETF.decode(Float(s)))
        return -log10(max(t, 1e-12))
    }
}
