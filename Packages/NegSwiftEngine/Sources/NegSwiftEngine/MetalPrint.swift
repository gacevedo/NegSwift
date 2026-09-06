import Foundation

#if canImport(Metal)
import Metal
#endif

/// S12 GPU path for used WGSL stages: normalize, H&D exposure, Lab sharpen, OETF.
/// Analysis stays on CPU. Returns nil when Metal is unavailable so callers keep CPU.
public enum MetalPrint: Sendable {
    public static func process(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        config: PrintConfig
    ) -> LinearRGBBuffer? {
        #if canImport(Metal)
        guard MetalDevice.isAvailable else { return nil }
        let remapped = config.applyingMeteringRemap()
        let region = remapped.resolvedAnalysisRegion()
        let bounds = LogNormalization.analyzeBounds(
            linear: linear,
            processMode: processMode,
            analysisBuffer: region.buffer,
            analysisRect: region.rect
        )
        let params = PhotometricPrint.resolvePixelParams(
            linear: linear,
            bounds: bounds,
            processMode: processMode,
            config: remapped
        )
        return run(
            linear: linear,
            bounds: bounds,
            params: params,
            lab: remapped,
            encode: true
        )
        #else
        return nil
        #endif
    }

    public static func normalize(_ linear: LinearRGBBuffer, bounds: LogNegativeBounds) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: linear, bounds: bounds, params: nil, lab: nil, encode: false, stopAfter: .normalize)
        #else
        return nil
        #endif
    }

    public static func applyExposure(
        normalized: LinearRGBBuffer,
        params: PhotometricPrint.PixelParams
    ) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: normalized, bounds: nil, params: params, lab: nil, encode: false, stopAfter: .exposure, inputIsNormalized: true)
        #else
        return nil
        #endif
    }

    public static func applyLab(_ image: LinearRGBBuffer, config: PrintConfig) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: image, bounds: nil, params: nil, lab: config, encode: false, stopAfter: .lab, inputIsNormalized: true)
        #else
        return nil
        #endif
    }

    public static func encodeOETF(_ image: LinearRGBBuffer) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: image, bounds: nil, params: nil, lab: nil, encode: true, stopAfter: .encode, inputIsNormalized: true)
        #else
        return nil
        #endif
    }
}

#if canImport(Metal)
extension MetalPrint {
    private enum Stage {
        case normalize
        case exposure
        case lab
        case encode
    }

    private struct NormalizeUniforms {
        var floors: SIMD4<Float>
        var ceils: SIMD4<Float>
    }

    private struct ExposureUniforms {
        var pivots: SIMD4<Float>
        var slopes: SIMD4<Float>
        var curvatures: SIMD4<Float>
        var cmyOffsets: SIMD4<Float>
        var midtoneGamma: SIMD4<Float>
        var shadowGrade: SIMD4<Float>
        var highlightGrade: SIMD4<Float>
        var aHL: SIMD4<Float>
        var aSH: SIMD4<Float>
        var dMinEff: SIMD4<Float>
        var dMaxEff: SIMD4<Float>
        var bpcBlack: SIMD4<Float>
        var shadowDensity: Float
        var highlightDensity: Float
        var vStar: Float
        var gammaWidth: Float
        var zoneShCenter: Float
        var zoneHiCenter: Float
        var zoneK: Float
        var mode: UInt32
        var useSplit: UInt32
        var useZone: UInt32
        var pad0: Float = 0
        var pad1: Float = 0
    }

    private struct LabUniforms {
        var saturation: Float
        var skinProtection: Float
        var sharpen: Float
        var kernelRadius: Float
        var sharpenMasking: Float
        var gateLo: Float
        var gateHi: Float
        var overshootLight: Float
        var overshootDark: Float
        var maskTHi: Float
        var pad0: Float = 0
        var pad1: Float = 0
    }

    private static func run(
        linear: LinearRGBBuffer,
        bounds: LogNegativeBounds?,
        params: PhotometricPrint.PixelParams?,
        lab: PrintConfig?,
        encode: Bool,
        stopAfter: Stage = .encode,
        inputIsNormalized: Bool = false
    ) -> LinearRGBBuffer? {
        guard let gpu = MetalDevice.runtime() else { return nil }
        let width = linear.width
        let height = linear.height
        guard let src = gpu.makeTexture(width: width, height: height),
              let dst = gpu.makeTexture(width: width, height: height)
        else {
            return nil
        }
        upload(linear, to: src)

        guard let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder()
        else {
            return nil
        }

        var current = src
        var scratch = dst
        func swapTextures() {
            swap(&current, &scratch)
        }
        func dispatch(_ pipeline: MTLComputePipelineState) {
            let w = pipeline.threadExecutionWidth
            let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
            )
        }

        if !inputIsNormalized, let bounds {
            guard let buf = gpu.makeBuffer(normalizeUniforms(bounds)) else {
                encoder.endEncoding()
                return nil
            }
            encoder.setComputePipelineState(gpu.normalize)
            encoder.setTexture(current, index: 0)
            encoder.setTexture(scratch, index: 1)
            encoder.setBuffer(buf, offset: 0, index: 0)
            dispatch(gpu.normalize)
            swapTextures()
            if stopAfter == .normalize {
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                return download(current, width: width, height: height)
            }
        }

        if let params {
            guard let buf = gpu.makeBuffer(exposureUniforms(params)) else {
                encoder.endEncoding()
                return nil
            }
            encoder.setComputePipelineState(gpu.exposure)
            encoder.setTexture(current, index: 0)
            encoder.setTexture(scratch, index: 1)
            encoder.setBuffer(buf, offset: 0, index: 0)
            dispatch(gpu.exposure)
            swapTextures()
            if stopAfter == .exposure {
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                return download(current, width: width, height: height)
            }
        }

        let needsLab = lab.map { $0.saturation != 1 || $0.skinProtection > 0 || $0.sharpen > 0 } ?? false
        if needsLab, let lab {
            let kernel = PhotoLab.gaussianKernel1D(sigma: lab.sharpenRadius)
            let labU = labUniforms(lab, kernelRadius: kernel.count / 2)
            guard let uBuf = gpu.makeBuffer(labU),
                  let kBuf = gpu.makeFloatBuffer(kernel),
                  let tmp = gpu.makeTexture(width: width, height: height),
                  let blur = gpu.makeTexture(width: width, height: height)
            else {
                encoder.endEncoding()
                return nil
            }
            if lab.sharpen > 0 {
                encoder.setComputePipelineState(gpu.labSharpenH)
                encoder.setTexture(current, index: 0)
                encoder.setTexture(tmp, index: 1)
                encoder.setBuffer(uBuf, offset: 0, index: 0)
                encoder.setBuffer(kBuf, offset: 0, index: 1)
                dispatch(gpu.labSharpenH)

                encoder.setComputePipelineState(gpu.labSharpenV)
                encoder.setTexture(tmp, index: 0)
                encoder.setTexture(blur, index: 1)
                encoder.setBuffer(uBuf, offset: 0, index: 0)
                encoder.setBuffer(kBuf, offset: 0, index: 1)
                dispatch(gpu.labSharpenV)
            }

            encoder.setComputePipelineState(gpu.labApply)
            encoder.setTexture(current, index: 0)
            encoder.setTexture(blur, index: 1)
            encoder.setTexture(scratch, index: 2)
            encoder.setBuffer(uBuf, offset: 0, index: 0)
            dispatch(gpu.labApply)
            swapTextures()
            if stopAfter == .lab {
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                return download(current, width: width, height: height)
            }
        } else if stopAfter == .lab {
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            return download(current, width: width, height: height)
        }

        if encode {
            encoder.setComputePipelineState(gpu.outputEncode)
            encoder.setTexture(current, index: 0)
            encoder.setTexture(scratch, index: 1)
            dispatch(gpu.outputEncode)
            swapTextures()
        }

        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        return download(current, width: width, height: height)
    }

    private static func normalizeUniforms(_ bounds: LogNegativeBounds) -> NormalizeUniforms {
        NormalizeUniforms(
            floors: SIMD4(Float(bounds.floors.0), Float(bounds.floors.1), Float(bounds.floors.2), 0),
            ceils: SIMD4(Float(bounds.ceils.0), Float(bounds.ceils.1), Float(bounds.ceils.2), 0)
        )
    }

    private static func exposureUniforms(_ params: PhotometricPrint.PixelParams) -> ExposureUniforms {
        let ts = ExposureConstants.toeShoulderStrength
        let toe3 = (params.toe * ts, params.toe * ts, params.toe * ts)
        let sh3 = (params.shoulder * ts, params.shoulder * ts, params.shoulder * ts)
        let dMax = ExposureConstants.dMax
        let aToeBase = ExposureConstants.toeSharpnessBase
        let aShBase = ExposureConstants.shoulderSharpnessBase
        let widthRef = ExposureConstants.toeShoulderWidthRef
        let toeHeight = ExposureConstants.toeHeight
        let shHeight = ExposureConstants.shoulderHeight
        let eps = 1e-6
        let toeA = [toe3.0, toe3.1, toe3.2]
        let shA = [sh3.0, sh3.1, sh3.2]
        let twA = [params.toeWidth, params.toeWidth, params.toeWidth]
        let swA = [params.shoulderWidth, params.shoulderWidth, params.shoulderWidth]
        let dMinA = [params.dMin, params.dMin, params.dMin]
        var aHL = [0.0, 0.0, 0.0]
        var aSH = [0.0, 0.0, 0.0]
        var dMinEff = [0.0, 0.0, 0.0]
        var dMaxEff = [0.0, 0.0, 0.0]
        var bpcBlack = [0.0, 0.0, 0.0]
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
            if params.bpc {
                var db = dMax
                if tCh < 0 {
                    db = dMax + tCh * toeHeight
                }
                bpcBlack[ch] = pow(10, -db)
            }
        }
        let sg = params.shadowGradeDeltas
        let hg = params.highlightGradeDeltas
        let useSplit = sg.0 != 0 || sg.1 != 0 || sg.2 != 0 || hg.0 != 0 || hg.1 != 0 || hg.2 != 0
        let useZone = params.shadowDensity != 0 || params.highlightDensity != 0
        let zoneCenter = ExposureConstants.anchorTargetDensity
        return ExposureUniforms(
            pivots: simd3(params.pivots),
            slopes: simd3(params.slopes),
            curvatures: simd3(params.curvatures),
            cmyOffsets: simd3(params.cmyOffsets),
            midtoneGamma: SIMD4(
                Float(ExposureConstants.paperMidtoneGamma),
                Float(ExposureConstants.paperMidtoneGamma),
                Float(ExposureConstants.paperMidtoneGamma),
                0
            ),
            shadowGrade: simd3(sg),
            highlightGrade: simd3(hg),
            aHL: simd3((aHL[0], aHL[1], aHL[2])),
            aSH: simd3((aSH[0], aSH[1], aSH[2])),
            dMinEff: simd3((dMinEff[0], dMinEff[1], dMinEff[2])),
            dMaxEff: simd3((dMaxEff[0], dMaxEff[1], dMaxEff[2])),
            bpcBlack: simd3((bpcBlack[0], bpcBlack[1], bpcBlack[2])),
            shadowDensity: Float(params.shadowDensity),
            highlightDensity: Float(params.highlightDensity),
            vStar: Float(PrintCurve.referenceLinearValue(dMin: params.dMin)),
            gammaWidth: Float(ExposureConstants.paperGammaWidth),
            zoneShCenter: Float(zoneCenter + ExposureConstants.zoneDensityShadowOffset),
            zoneHiCenter: Float(zoneCenter + ExposureConstants.zoneDensityHighlightOffset),
            zoneK: Float(ExposureConstants.zoneDensitySharpness),
            mode: params.processMode == .bwNegative ? 1 : 0,
            useSplit: useSplit ? 1 : 0,
            useZone: useZone ? 1 : 0
        )
    }

    private static func labUniforms(_ config: PrintConfig, kernelRadius: Int) -> LabUniforms {
        LabUniforms(
            saturation: config.saturation,
            skinProtection: config.skinProtection,
            sharpen: config.sharpen,
            kernelRadius: Float(kernelRadius),
            sharpenMasking: config.sharpenMasking,
            gateLo: PhotoLab.sharpenGateLo,
            gateHi: PhotoLab.sharpenGateHi,
            overshootLight: PhotoLab.sharpenOvershootLight,
            overshootDark: PhotoLab.sharpenOvershootDark,
            maskTHi: PhotoLab.sharpenMaskTHi
        )
    }

    private static func simd3(_ t: (Double, Double, Double)) -> SIMD4<Float> {
        SIMD4(Float(t.0), Float(t.1), Float(t.2), 0)
    }

    private static func upload(_ buffer: LinearRGBBuffer, to texture: MTLTexture) {
        var rgba = [Float](repeating: 1, count: buffer.width * buffer.height * 4)
        let n = buffer.width * buffer.height
        for i in 0..<n {
            rgba[i * 4] = buffer.pixels[i * 3]
            rgba[i * 4 + 1] = buffer.pixels[i * 3 + 1]
            rgba[i * 4 + 2] = buffer.pixels[i * 3 + 2]
        }
        rgba.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, buffer.width, buffer.height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: buffer.width * 16
            )
        }
    }

    private static func download(_ texture: MTLTexture, width: Int, height: Int) -> LinearRGBBuffer {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: width * 16,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        var rgb = [Float](repeating: 0, count: width * height * 3)
        let n = width * height
        for i in 0..<n {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return LinearRGBBuffer(width: width, height: height, pixels: rgb)
    }
}
#endif
