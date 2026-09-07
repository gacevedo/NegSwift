import Foundation

#if canImport(Metal)
import Metal
#endif

/// S12 GPU path for used WGSL stages: normalize, H&D exposure, Lab sharpen, OETF.
/// Analysis stays on CPU. Returns nil when Metal is unavailable so callers keep CPU.
public enum MetalPrint: Sendable {
    public struct Output: Sendable {
        public var buffer: LinearRGBBuffer?
        /// Encoded working-space buffer for S13k disk cache when `readback` is false.
        public var cacheBuffer: LinearRGBBuffer?
        public var present: GPUPresentImage?
        public var uploaded: Bool
        public var downloaded: Bool
    }

    public static func process(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        config: PrintConfig,
        bounds: LogNegativeBounds? = nil,
        params: PhotometricPrint.PixelParams? = nil,
        baked: LinearRGBBuffer? = nil,
        bakeKey: String? = nil,
        persistResident: Bool = false
    ) -> LinearRGBBuffer? {
        processDetailed(
            linear: linear,
            processMode: processMode,
            config: config,
            bounds: bounds,
            params: params,
            baked: baked,
            bakeKey: bakeKey,
            persistResident: persistResident
        )?.buffer
    }

    /// S13h: GPU present without float `getBytes`. Nil when Metal is unavailable.
    public static func processPresent(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        config: PrintConfig,
        bounds: LogNegativeBounds? = nil,
        params: PhotometricPrint.PixelParams? = nil,
        baked: LinearRGBBuffer? = nil,
        bakeKey: String? = nil,
        persistResident: Bool = false
    ) -> (present: GPUPresentImage, uploaded: Bool)? {
        let out = processDetailed(
            linear: linear,
            processMode: processMode,
            config: config,
            bounds: bounds,
            params: params,
            baked: baked,
            bakeKey: bakeKey,
            persistResident: persistResident,
            readback: false
        )
        guard let present = out?.present else { return nil }
        return (present, out?.uploaded ?? false)
    }

    public static func processDetailed(
        linear: LinearRGBBuffer,
        processMode: FilmProcessMode,
        config: PrintConfig,
        bounds: LogNegativeBounds? = nil,
        params: PhotometricPrint.PixelParams? = nil,
        baked: LinearRGBBuffer? = nil,
        bakeKey: String? = nil,
        persistResident: Bool = false,
        readback: Bool = true
    ) -> Output? {
        #if canImport(Metal)
        guard MetalDevice.isAvailable else { return nil }
        let remapped = config.applyingMeteringRemap()
        let resolvedBounds: LogNegativeBounds
        if let bounds {
            resolvedBounds = bounds
        } else {
            let region = remapped.resolvedAnalysisRegion()
            resolvedBounds = LogNormalization.analyzeBounds(
                linear: linear,
                processMode: processMode,
                analysisBuffer: region.buffer,
                analysisRect: region.rect
            )
        }
        let resolvedParams = params ?? PhotometricPrint.resolvePixelParams(
            linear: linear,
            bounds: resolvedBounds,
            processMode: processMode,
            config: remapped
        )
        return run(
            linear: linear,
            bounds: resolvedBounds,
            params: resolvedParams,
            lab: remapped,
            encode: true,
            baked: persistResident ? baked : nil,
            bakeKey: persistResident ? bakeKey : nil,
            geometry: remapped,
            readback: readback
        )
        #else
        return nil
        #endif
    }

    public static func normalize(_ linear: LinearRGBBuffer, bounds: LogNegativeBounds) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: linear, bounds: bounds, params: nil, lab: nil, encode: false, stopAfter: .normalize)?.buffer
        #else
        return nil
        #endif
    }

    public static func applyExposure(
        normalized: LinearRGBBuffer,
        params: PhotometricPrint.PixelParams
    ) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: normalized, bounds: nil, params: params, lab: nil, encode: false, stopAfter: .exposure, inputIsNormalized: true)?.buffer
        #else
        return nil
        #endif
    }

    public static func applyLab(_ image: LinearRGBBuffer, config: PrintConfig) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: image, bounds: nil, params: nil, lab: config, encode: false, stopAfter: .lab, inputIsNormalized: true)?.buffer
        #else
        return nil
        #endif
    }

    public static func encodeOETF(_ image: LinearRGBBuffer) -> LinearRGBBuffer? {
        #if canImport(Metal)
        run(linear: image, bounds: nil, params: nil, lab: nil, encode: true, stopAfter: .encode, inputIsNormalized: true)?.buffer
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

    private static let encodeLock = NSLock()

    private static func run(
        linear: LinearRGBBuffer,
        bounds: LogNegativeBounds?,
        params: PhotometricPrint.PixelParams?,
        lab: PrintConfig?,
        encode: Bool,
        stopAfter: Stage = .encode,
        inputIsNormalized: Bool = false,
        baked: LinearRGBBuffer? = nil,
        bakeKey: String? = nil,
        geometry: PrintConfig? = nil,
        readback: Bool = true
    ) -> Output? {
        encodeLock.lock()
        defer { encodeLock.unlock() }
        guard let gpu = MetalDevice.runtime() else { return nil }

        let source: MTLTexture
        let width: Int
        let height: Int
        var uploaded = false
        if let baked, let bakeKey {
            guard let prepared = MetalWorkingSet.shared.orientedSource(
                gpu: gpu,
                bakeKey: bakeKey,
                baked: baked,
                config: geometry ?? .s4aPin
            ) else {
                return nil
            }
            source = prepared.texture
            width = prepared.width
            height = prepared.height
            uploaded = prepared.uploaded
        } else {
            width = linear.width
            height = linear.height
            guard let src = gpu.makeTexture(width: width, height: height) else {
                return nil
            }
            upload(linear, to: src)
            PipelineStats.increment(.upload)
            uploaded = true
            source = src
        }

        guard let pair = gpu.workingPair(width: width, height: height) else {
            return nil
        }
        let ping = pair.ping
        let pong = pair.pong

        guard let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder()
        else {
            return nil
        }

        var current = source
        var scratch = ping
        var sourceStillCurrent = true
        func swapTextures() {
            if sourceStillCurrent {
                current = scratch
                scratch = pong
                sourceStillCurrent = false
            } else {
                swap(&current, &scratch)
            }
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
                return readbackOutput(current, width: width, height: height, uploaded: uploaded)
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
                return readbackOutput(current, width: width, height: height, uploaded: uploaded)
            }
        }

        let needsLab = lab.map { $0.saturation != 1 || $0.skinProtection > 0 || $0.sharpen > 0 } ?? false
        if needsLab, let lab {
            let kernel = PhotoLab.gaussianKernel1D(sigma: lab.sharpenRadius)
            let labU = labUniforms(lab, kernelRadius: kernel.count / 2)
            guard let uBuf = gpu.makeBuffer(labU),
                  let kBuf = gpu.makeFloatBuffer(kernel),
                  let scratchPair = gpu.labScratch(width: width, height: height)
            else {
                encoder.endEncoding()
                return nil
            }
            let tmp = scratchPair.tmp
            let blur = scratchPair.blur
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
                return readbackOutput(current, width: width, height: height, uploaded: uploaded)
            }
        } else if stopAfter == .lab {
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            return readbackOutput(current, width: width, height: height, uploaded: uploaded)
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
        var outW = width
        var outH = height
        var originX = 0
        var originY = 0
        if encode, let geometry, geometry.applyPixelCrop, let crop = geometry.cropRect,
           let roi = LinearRGBBuffer.storedCropPixelROI(
               width: width,
               height: height,
               rect: crop,
               offsetPx: geometry.autocropOffset
           )
        {
            outW = roi.x2 - roi.x1
            outH = roi.y2 - roi.y1
            originX = roi.x1
            originY = roi.y1
        }
        if !readback, encode, stopAfter == .encode,
           let present = GPUPresent.image(
               gpu: gpu,
               source: current,
               width: outW,
               height: outH,
               originX: originX,
               originY: originY
           )
        {
            let cacheBuffer = download(
                current,
                width: outW,
                height: outH,
                originX: originX,
                originY: originY
            )
            return Output(
                buffer: nil,
                cacheBuffer: cacheBuffer,
                present: present,
                uploaded: uploaded,
                downloaded: false
            )
        }
        return readbackOutput(
            current,
            width: outW,
            height: outH,
            originX: originX,
            originY: originY,
            uploaded: uploaded
        )
    }

    private static func readbackOutput(
        _ texture: MTLTexture,
        width: Int,
        height: Int,
        originX: Int = 0,
        originY: Int = 0,
        uploaded: Bool
    ) -> Output {
        PipelineStats.increment(.download)
        return Output(
            buffer: download(
                texture,
                width: width,
                height: height,
                originX: originX,
                originY: originY
            ),
            cacheBuffer: nil,
            present: nil,
            uploaded: uploaded,
            downloaded: true
        )
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

    static func upload(_ buffer: LinearRGBBuffer, to texture: MTLTexture) {
        let rgba = AccelerateConvert.rgbToRGBA(buffer.pixels, width: buffer.width, height: buffer.height)
        rgba.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, buffer.width, buffer.height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: buffer.width * 16
            )
        }
    }

    static func download(
        _ texture: MTLTexture,
        width: Int,
        height: Int,
        originX: Int = 0,
        originY: Int = 0
    ) -> LinearRGBBuffer {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: width * 16,
                from: MTLRegionMake2D(originX, originY, width, height),
                mipmapLevel: 0
            )
        }
        let rgb = AccelerateConvert.rgbaToRGB(rgba, width: width, height: height)
        return LinearRGBBuffer(width: width, height: height, pixels: rgb)
    }
}

/// S13c: last uploaded post-dust/heal linear, plus oriented texture after geometry.
final class MetalWorkingSet: @unchecked Sendable {
    static let shared = MetalWorkingSet()

    private struct Slot {
        var baked: MTLTexture
        var geometryKey: String?
        var oriented: MTLTexture?
    }

    private let lock = NSLock()
    private var slots: [String: Slot] = [:]
    private var order: [String] = []
    private let limit = CacheBudget.metalWorkingSet

    func reset() {
        lock.lock()
        slots.removeAll()
        order.removeAll()
        lock.unlock()
    }

    func orientedSource(
        gpu: MetalDevice.Runtime,
        bakeKey: String,
        baked linear: LinearRGBBuffer,
        config: PrintConfig
    ) -> (texture: MTLTexture, width: Int, height: Int, uploaded: Bool)? {
        let dest = MetalGeometry.outputSize(
            width: linear.width,
            height: linear.height,
            rotation: config.rotation
        )
        let geomKey = ReprintCache.geometryKey(config)
        let identity = MetalGeometry.isIdentity(
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            fineRotation: config.fineRotation
        )

        lock.lock()
        let existing = slots[bakeKey]
        lock.unlock()

        let bakedTex: MTLTexture
        var uploaded = false
        if let existing {
            bakedTex = existing.baked
        } else {
            guard let tex = gpu.makeTexture(width: linear.width, height: linear.height) else {
                return nil
            }
            MetalPrint.upload(linear, to: tex)
            PipelineStats.increment(.upload)
            uploaded = true
            bakedTex = tex
            lock.lock()
            rememberLocked(bakeKey, Slot(baked: tex, geometryKey: nil, oriented: nil))
            lock.unlock()
        }

        if identity {
            return (bakedTex, linear.width, linear.height, uploaded)
        }
        if let existing, existing.geometryKey == geomKey, let oriented = existing.oriented {
            return (oriented, dest.width, dest.height, uploaded)
        }
        guard let destTex = gpu.makeTexture(width: dest.width, height: dest.height) else {
            return nil
        }
        guard MetalGeometry.apply(
            gpu: gpu,
            source: bakedTex,
            destination: destTex,
            rotation: config.rotation,
            flipHorizontal: config.flipHorizontal,
            flipVertical: config.flipVertical,
            fineRotation: config.fineRotation
        ) else {
            return nil
        }
        lock.lock()
        if var slot = slots[bakeKey] {
            slot.geometryKey = geomKey
            slot.oriented = destTex
            slots[bakeKey] = slot
        }
        lock.unlock()
        return (destTex, dest.width, dest.height, uploaded)
    }

    private func rememberLocked(_ key: String, _ slot: Slot) {
        slots[key] = slot
        order.removeAll { $0 == key }
        order.insert(key, at: 0)
        while order.count > limit {
            let evicted = order.removeLast()
            slots.removeValue(forKey: evicted)
        }
    }
}
#endif
