import Foundation
import Testing
@testable import NegSwiftEngine

/// Port of NegPy `tests/test_lab_logic.py` (saturation, skin, USM — not CLAHE/RL/glow).
struct PhotoLabTests {
    @Test func gaussianKernelMatchesVendorNegPy() {
        let k = PhotoLab.gaussianKernel1D(sigma: 1)
        let expected: [Float] = [
            0.004433048, 0.054005578, 0.24203622, 0.39905027,
            0.24203622, 0.054005578, 0.004433048,
        ]
        #expect(k.count == expected.count)
        for i in expected.indices {
            #expect(abs(k[i] - expected[i]) < 1e-6)
        }
    }

    @Test func saturationPaleRedMatchesVendor() {
        var pixels = [Float](repeating: 0.5, count: 8 * 8 * 3)
        for i in 0..<(8 * 8) {
            pixels[i * 3] = 0.8
        }
        let img = LinearRGBBuffer(width: 8, height: 8, pixels: pixels)
        let sat = PhotoLab.applySaturation(img, saturation: 1.3)
        #expect(abs(sat.pixels[0] - 0.8661166) < 1e-4)
        #expect(abs(sat.pixels[1] - 0.4716601) < 1e-4)
        #expect(abs(sat.pixels[2] - 0.4749905) < 1e-4)
    }

    @Test func skinProtectionMatchesVendor() {
        var pixels = [Float](repeating: 0, count: 8 * 8 * 3)
        for i in 0..<(8 * 8) {
            pixels[i * 3] = 0.53
            pixels[i * 3 + 1] = 0.27
            pixels[i * 3 + 2] = 0.16
        }
        let img = LinearRGBBuffer(width: 8, height: 8, pixels: pixels)
        let skin = PhotoLab.applySaturation(img, saturation: 1, skinProtection: 0.5)
        #expect(abs(skin.pixels[0] - 0.5207774) < 1e-4)
        #expect(abs(skin.pixels[1] - 0.2735210) < 1e-4)
        #expect(abs(skin.pixels[2] - 0.1670902) < 1e-4)
    }

    @Test func usmStepMatchesVendorL() {
        var pixels = [Float](repeating: 0, count: 40 * 40 * 3)
        for y in 0..<40 {
            for x in 20..<40 {
                let o = (y * 40 + x) * 3
                pixels[o] = 0.8
                pixels[o + 1] = 0.8
                pixels[o + 2] = 0.8
            }
        }
        let img = LinearRGBBuffer(width: 40, height: 40, pixels: pixels)
        let res = PhotoLab.applyOutputSharpening(img, amount: 0.25)
        let lOut = WorkingLab.rgbToLab(res)
        let row = 20
        let samples = [18, 19, 20, 21, 22].map { lOut.pixels[(row * 40 + $0) * 3] }
        #expect(abs(samples[0]) < 1e-4)
        #expect(abs(samples[1]) < 1e-4)
        #expect(abs(samples[2] - 92.68487) < 0.05)
        #expect(abs(samples[3] - 92.68487) < 0.05)
        #expect(abs(samples[4] - 91.93890) < 0.05)
    }

    @Test func gaussianKernelInvariants() {
        let cases: [(Float, Int)] = [(0.5, 2), (1.0, 3), (3.75, 10), (45.0, 113)]
        for (sigma, expectedR) in cases {
            let k = PhotoLab.gaussianKernel1D(sigma: sigma)
            #expect((k.count - 1) / 2 == expectedR)
            #expect(abs(k.reduce(0, +) - 1) < 1e-5)
            for i in 0..<k.count {
                #expect(abs(k[i] - k[k.count - 1 - i]) < 1e-6)
            }
        }
        #expect(PhotoLab.gaussianKernel1D(sigma: 1000).count == 511)
    }

    @Test func outputSharpeningIncreasesVariance() {
        var pixels = [Float](repeating: 0, count: 100 * 100 * 3)
        for y in 25..<75 {
            for x in 25..<75 {
                let o = (y * 100 + x) * 3
                pixels[o] = 0.5
                pixels[o + 1] = 0.5
                pixels[o + 2] = 0.5
            }
        }
        let img = LinearRGBBuffer(width: 100, height: 100, pixels: pixels)
        let res = PhotoLab.applyOutputSharpening(img, amount: 1)
        #expect(variance(res.pixels) > variance(img.pixels))
    }

    @Test func sharpenNoOvershootOnStep() {
        var pixels = [Float](repeating: 0, count: 40 * 40 * 3)
        for y in 0..<40 {
            for x in 20..<40 {
                let o = (y * 40 + x) * 3
                pixels[o] = 0.8
                pixels[o + 1] = 0.8
                pixels[o + 2] = 0.8
            }
        }
        let img = LinearRGBBuffer(width: 40, height: 40, pixels: pixels)
        let res = PhotoLab.applyOutputSharpening(img, amount: 1)
        let lIn = WorkingLab.rgbToLab(img)
        let lOut = WorkingLab.rgbToLab(res)
        var inMin: Float = .greatestFiniteMagnitude
        var inMax: Float = -.greatestFiniteMagnitude
        var outMin: Float = .greatestFiniteMagnitude
        var outMax: Float = -.greatestFiniteMagnitude
        for i in 0..<(40 * 40) {
            inMin = min(inMin, lIn.pixels[i * 3])
            inMax = max(inMax, lIn.pixels[i * 3])
            outMin = min(outMin, lOut.pixels[i * 3])
            outMax = max(outMax, lOut.pixels[i * 3])
        }
        #expect(outMin >= inMin - 2.1)
        #expect(outMax <= inMax + 1.1)
    }

    @Test func sharpenShadowGainRollsOffTowardPaperBlack() {
        let mid = PhotoLab.sharpenShadowGain(0.5 * PhotoLab.sharpenShadowLHi)
        #expect(abs(PhotoLab.sharpenShadowGain(0) - PhotoLab.sharpenShadowFloor) < 1e-5)
        #expect(abs(PhotoLab.sharpenShadowGain(PhotoLab.sharpenShadowLHi) - 1) < 1e-5)
        #expect(PhotoLab.sharpenShadowGain(100) == 1)
        #expect(mid > PhotoLab.sharpenShadowFloor && mid < 1)
    }

    @Test func sharpenFlatBelowGatePassthrough() {
        var pixels = [Float](repeating: 0, count: 64 * 64 * 3)
        var seed: UInt64 = 3
        for i in 0..<pixels.count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let noise = (Float(seed % 2001) / 2001 - 0.5) * 0.002
            pixels[i] = min(max(0.5 + noise, 0), 1)
        }
        let img = LinearRGBBuffer(width: 64, height: 64, pixels: pixels)
        let res = PhotoLab.applyOutputSharpening(img, amount: 1)
        let lIn = WorkingLab.rgbToLab(img)
        let lOut = WorkingLab.rgbToLab(res)
        for i in 0..<(64 * 64) {
            #expect(abs(lOut.pixels[i * 3] - lIn.pixels[i * 3]) < 0.05)
        }
    }

    @Test func saturationPreservesLightnessOnDesat() {
        var pixels = [Float](repeating: 0, count: 10 * 10 * 3)
        for i in 0..<(10 * 10) {
            pixels[i * 3] = 1
        }
        let img = LinearRGBBuffer(width: 10, height: 10, pixels: pixels)
        let lInput = WorkingLab.rgbToLab(img).pixels[0]
        let desat = PhotoLab.applySaturation(img, saturation: 0)
        #expect(abs(desat.pixels[0] - desat.pixels[1]) < 1e-3)
        #expect(abs(desat.pixels[1] - desat.pixels[2]) < 1e-3)
        #expect(desat.pixels[0] < 0.5 && desat.pixels[0] > 0.2)
        let lDesat = WorkingLab.rgbToLab(desat).pixels[0]
        #expect(abs(lDesat - lInput) < 1)
    }

    @Test func saturationBoostKeepsRedDominant() {
        var pixels = [Float](repeating: 0.5, count: 10 * 10 * 3)
        for i in 0..<(10 * 10) {
            pixels[i * 3] = 0.8
        }
        let img = LinearRGBBuffer(width: 10, height: 10, pixels: pixels)
        let lInput = WorkingLab.rgbToLab(img).pixels[0]
        let sat = PhotoLab.applySaturation(img, saturation: 2)
        #expect(sat.pixels[0] > sat.pixels[1])
        #expect(sat.pixels[0] > sat.pixels[2])
        let lSat = WorkingLab.rgbToLab(sat).pixels[0]
        #expect(abs(lSat - lInput) < 2)
    }

    @Test func saturationDoesNotDarkenSaturatedRed() {
        var pixels = [Float](repeating: 0, count: 10 * 10 * 3)
        for i in 0..<(10 * 10) {
            pixels[i * 3] = 0.9
            pixels[i * 3 + 1] = 0.15
            pixels[i * 3 + 2] = 0.1
        }
        let img = LinearRGBBuffer(width: 10, height: 10, pixels: pixels)
        let lIn = WorkingLab.rgbToLab(img).pixels[0]
        let boosted = PhotoLab.applySaturation(img, saturation: 1.5)
        let lOut = WorkingLab.rgbToLab(boosted).pixels[0]
        #expect(lOut >= lIn - 5.5)
    }

    @Test func saturationBelowOneIsFlatScale() {
        var pixels = [Float](repeating: 0, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3] = 0.9
            pixels[i * 3 + 1] = 0.15
            pixels[i * 3 + 2] = 0.1
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let gamutAware = PhotoLab.applySaturation(img, saturation: 0.3)
        var lab = WorkingLab.rgbToLab(img)
        for i in 0..<(4 * 4) {
            lab.pixels[i * 3 + 1] *= 0.3
            lab.pixels[i * 3 + 2] *= 0.3
        }
        let naive = PhotoLab.clip01(WorkingLab.labToRgb(lab))
        for i in gamutAware.pixels.indices {
            #expect(abs(gamutAware.pixels[i] - naive.pixels[i]) < 1e-5)
        }
    }

    @Test func saturationUnaffectedWhenComfortablyInGamut() {
        var pixels = [Float](repeating: 0.5, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3 + 2] = 0.55
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let gamutAware = PhotoLab.applySaturation(img, saturation: 1.1)
        var lab = WorkingLab.rgbToLab(img)
        for i in 0..<(4 * 4) {
            lab.pixels[i * 3 + 1] *= 1.1
            lab.pixels[i * 3 + 2] *= 1.1
        }
        let naive = PhotoLab.clip01(WorkingLab.labToRgb(lab))
        for i in gamutAware.pixels.indices {
            #expect(abs(gamutAware.pixels[i] - naive.pixels[i]) < 1e-4)
        }
    }

    @Test func skinPatchScoresHigh() {
        let lab = labFrom(l: 65, chroma: 28, hueDeg: 52)
        #expect(PhotoLab.skinWeight(l: 65, a: lab.1, b: lab.2) > 0.9)
    }

    @Test func saturatedRedScoresNearZero() {
        let lab = WorkingLab.rgbToLab(rgb(1, 0, 0))
        #expect(hypot(lab.pixels[1], lab.pixels[2]) > 85)
        #expect(PhotoLab.skinWeight(l: lab.pixels[0], a: lab.pixels[1], b: lab.pixels[2]) < 0.01)
    }

    @Test func deepSkinScoresHigh() {
        let lab = labFrom(l: 27, chroma: 22, hueDeg: 53)
        #expect(PhotoLab.skinWeight(l: 27, a: lab.1, b: lab.2) > 0.9)
    }

    @Test func saturatedWarmObjectsScoreLow() {
        let samples: [(Float, Float, Float)] = [
            (71, 57, 55),
            (55, 53, 45),
            (39, 51, 40),
            (53, 71, 54),
            (44, 69, 48),
        ]
        for (l, chroma, hue) in samples {
            let ab = labFrom(l: l, chroma: chroma, hueDeg: hue)
            #expect(PhotoLab.skinWeight(l: l, a: ab.1, b: ab.2) < 0.3)
        }
    }

    @Test func neutralAndShadowScoreZero() {
        #expect(PhotoLab.skinWeight(l: 50, a: 0.3, b: 0.4) == 0)
        #expect(PhotoLab.skinWeight(l: 0, a: 20, b: 25) == 0)
    }

    @Test func coolHueScoresZero() {
        let lab = labFrom(l: 65, chroma: 28, hueDeg: 250)
        #expect(PhotoLab.skinWeight(l: 65, a: lab.1, b: lab.2) < 1e-3)
    }

    @Test func skinReinZeroStrengthIsIdentity() {
        let lab = bufferFrom(labFrom(l: 60, chroma: 70, hueDeg: 52))
        let out = PhotoLab.skinChromaRein(lab, strength: 0)
        #expect(out.pixels == lab.pixels)
    }

    @Test func skinReinNeverRaisesChroma() {
        for chroma in [Float(5), 20, 40, 60, 80, 100] {
            for hue in [Float(0), 52, 120, 250] {
                let lab = bufferFrom(labFrom(l: 60, chroma: chroma, hueDeg: hue))
                let out = PhotoLab.skinChromaRein(lab, strength: 1)
                #expect(chromaOf(out) <= chroma + 1e-4)
            }
        }
    }

    @Test func skinReinBelowKneeUntouched() {
        let lab = bufferFrom(labFrom(l: 65, chroma: 20, hueDeg: 52))
        let out = PhotoLab.skinChromaRein(lab, strength: 0.5)
        for i in lab.pixels.indices {
            #expect(abs(out.pixels[i] - lab.pixels[i]) < 1e-5)
        }
    }

    @Test func excessiveSkinChromaIsPulledDown() {
        let lab = bufferFrom(labFrom(l: 65, chroma: 45, hueDeg: 52))
        #expect(chromaOf(PhotoLab.skinChromaRein(lab, strength: 0.5)) < 43)
    }

    @Test func skinReinPreservesHueAndLightness() {
        let lab = bufferFrom(labFrom(l: 65, chroma: 45, hueDeg: 52))
        let out = PhotoLab.skinChromaRein(lab, strength: 0.8)
        #expect(abs(out.pixels[0] - 65) < 1e-4)
        let hue = atan2(out.pixels[2], out.pixels[1]) * (180 / Float.pi)
        #expect(abs(hue - 52) < 1e-3)
    }

    @Test func strongerReinsHarder() {
        let lab = bufferFrom(labFrom(l: 65, chroma: 45, hueDeg: 52))
        let chromas = [Float(0.2), 0.5, 0.8, 1.0].map { chromaOf(PhotoLab.skinChromaRein(lab, strength: $0)) }
        #expect(chromas == chromas.sorted(by: >))
    }

    @Test func skinProtectionActsAtChromaOne() {
        var pixels = [Float](repeating: 0, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3] = 0.53
            pixels[i * 3 + 1] = 0.27
            pixels[i * 3 + 2] = 0.16
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let before = chromaOf(WorkingLab.rgbToLab(img))
        let after = chromaOf(WorkingLab.rgbToLab(PhotoLab.applySaturation(img, saturation: 1, skinProtection: 0.8)))
        #expect(after < before - 1)
    }

    @Test func skinProtectionOnByDefault() {
        #expect(PhotoLab.defaultSkinProtection == 0.5)
        var pixels = [Float](repeating: 0, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3] = 0.53
            pixels[i * 3 + 1] = 0.27
            pixels[i * 3 + 2] = 0.16
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let before = chromaOf(WorkingLab.rgbToLab(img))
        let after = chromaOf(
            WorkingLab.rgbToLab(PhotoLab.applySaturation(img, saturation: 1, skinProtection: PhotoLab.defaultSkinProtection))
        )
        #expect(after < before - 1)
    }

    @Test func skinOffIsIdentityAtChromaOne() {
        var pixels = [Float](repeating: 0.5, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3] = 0.85
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        #expect(PhotoLab.applySaturation(img, saturation: 1, skinProtection: 0).pixels == img.pixels)
    }

    @Test func desaturationStillReachesGrey() {
        var pixels = [Float](repeating: 0, count: 4 * 4 * 3)
        for i in 0..<(4 * 4) {
            pixels[i * 3] = 1
        }
        let img = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let desat = PhotoLab.applySaturation(img, saturation: 0, skinProtection: 1)
        #expect(abs(desat.pixels[0] - desat.pixels[1]) < 1e-3)
        #expect(abs(desat.pixels[1] - desat.pixels[2]) < 1e-3)
    }

    @Test func printConfigMergesLabKeys() {
        let merged = PrintConfig.s5Pin.merging([
            "saturation": 1.2,
            "skin_protection": 0.5,
            "sharpen": 0.25,
        ])
        #expect(merged.saturation == 1.2)
        #expect(merged.skinProtection == 0.5)
        #expect(merged.sharpen == 0.25)
        #expect(PrintConfig.s4aPin.sharpen == 0)
        #expect(PrintConfig.s4aPin.skinProtection == 0)
    }

    private func rgb(_ r: Float, _ g: Float, _ b: Float) -> LinearRGBBuffer {
        LinearRGBBuffer(width: 1, height: 1, pixels: [r, g, b])
    }

    private func labFrom(l: Float, chroma: Float, hueDeg: Float) -> (Float, Float, Float) {
        let rad = hueDeg * (Float.pi / 180)
        return (l, chroma * cos(rad), chroma * sin(rad))
    }

    private func bufferFrom(_ lab: (Float, Float, Float)) -> LinearRGBBuffer {
        LinearRGBBuffer(width: 1, height: 1, pixels: [lab.0, lab.1, lab.2])
    }

    private func chromaOf(_ lab: LinearRGBBuffer) -> Float {
        hypot(lab.pixels[1], lab.pixels[2])
    }

    private func variance(_ pixels: [Float]) -> Float {
        let mean = pixels.reduce(0, +) / Float(pixels.count)
        var acc: Float = 0
        for v in pixels {
            let d = v - mean
            acc += d * d
        }
        return acc / Float(pixels.count)
    }
}
