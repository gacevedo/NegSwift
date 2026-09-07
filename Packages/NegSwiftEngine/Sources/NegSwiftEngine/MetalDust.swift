import Foundation

#if canImport(Metal)
import Metal
#endif

/// S13l: GPU optical dust detection plane (downsample + computeStats).
/// Detection logic and repair stay on CPU for parity with NegPy.
public enum MetalDust: Sendable {
    public static func bake(
        _ image: LinearRGBBuffer,
        threshold: Float = OpticalDust.defaultThreshold,
        size: Int = OpticalDust.defaultSize
    ) -> LinearRGBBuffer? {
        guard let found = detect(image, threshold: threshold, size: size) else {
            return nil
        }
        return OpticalDust.applyDetection(image, found: found)
    }

    public static func detect(
        _ image: LinearRGBBuffer,
        threshold: Float = OpticalDust.defaultThreshold,
        size: Int = OpticalDust.defaultSize
    ) -> OpticalDust.Detection? {
        #if canImport(Metal)
        guard let gpu = MetalDevice.runtime() else { return nil }
        guard let small = detectionDownsample(gpu: gpu, image: image) else { return nil }
        guard let stats = computeStats(gpu: gpu, image: small, dustSize: size) else { return nil }
        return OpticalDust.detectFromStats(
            stats,
            threshold: threshold,
            dustSize: size,
            width: small.width,
            height: small.height
        )
        #else
        return nil
        #endif
    }
}

#if canImport(Metal)
extension MetalDust {
    struct DustUniforms {
        var width: Int32 = 0
        var height: Int32 = 0
        var ksize: Int32 = 0
        var srcWidth: Int32 = 0
        var srcHeight: Int32 = 0
        var dstWidth: Int32 = 0
        var dstHeight: Int32 = 0
        var lo: Float = 0
        var spread: Float = 1
        var madGain: Float = OpticalDust.detectMadGain
        var sigmaMin: Float = OpticalDust.detectSigmaMin
    }

    private static func detectionDownsample(
        gpu: MetalDevice.Runtime,
        image: LinearRGBBuffer
    ) -> LinearRGBBuffer? {
        let long = max(image.width, image.height)
        let target = OpticalDust.detectTarget(bufferLongEdge: long)
        if long <= target {
            return image
        }
        let scale = Float(target) / Float(long)
        let nw = max(1, Int((Float(image.width) * scale).rounded()))
        let nh = max(1, Int((Float(image.height) * scale).rounded()))
        let k = max(1, Int((Double(long) / Double(target)).rounded()) | 1)

        guard let src = gpu.makeTexture(width: image.width, height: image.height),
              let work = gpu.makeTexture(width: image.width, height: image.height),
              let dst = gpu.makeTexture(width: nw, height: nh)
        else {
            return nil
        }
        MetalPrint.upload(image, to: src)

        let current: MTLTexture
        if k > 1 {
            var uniforms = DustUniforms(
                width: Int32(image.width),
                height: Int32(image.height),
                ksize: Int32(k)
            )
            guard dispatch(
                gpu: gpu,
                pipeline: gpu.dustErodeRGB,
                uniforms: uniforms,
                width: image.width,
                height: image.height,
                textures: [(src, true), (work, false)]
            ) else {
                return nil
            }
            current = work
        } else {
            current = src
        }

        var down = DustUniforms(
            srcWidth: Int32(image.width),
            srcHeight: Int32(image.height),
            dstWidth: Int32(nw),
            dstHeight: Int32(nh)
        )
        guard dispatch(
            gpu: gpu,
            pipeline: gpu.dustDownsampleArea,
            uniforms: down,
            width: nw,
            height: nh,
            textures: [(current, true), (dst, false)]
        ) else {
            return nil
        }
        return downloadRGB(dst, width: nw, height: nh)
    }

    private static func computeStats(
        gpu: MetalDevice.Runtime,
        image: LinearRGBBuffer,
        dustSize: Int
    ) -> OpticalDust.DustStats? {
        let w = image.width
        let h = image.height
        guard let rgb = gpu.makeTexture(width: w, height: h),
              let dens = gpu.makePlane(width: w, height: h),
              let proxy = gpu.makePlane(width: w, height: h),
              let median = gpu.makePlane(width: w, height: h),
              let openedE = gpu.makePlane(width: w, height: h),
              let opened = gpu.makePlane(width: w, height: h),
              let background = gpu.makePlane(width: w, height: h),
              let residual = gpu.makePlane(width: w, height: h),
              let excess = gpu.makePlane(width: w, height: h),
              let madSrc = gpu.makePlane(width: w, height: h),
              let mad = gpu.makePlane(width: w, height: h),
              let z = gpu.makePlane(width: w, height: h),
              let mean = gpu.makePlane(width: w, height: h),
              let meanSq = gpu.makePlane(width: w, height: h),
              let texture = gpu.makePlane(width: w, height: h),
              let scratch = gpu.makePlane(width: w, height: h)
        else {
            return nil
        }

        MetalPrint.upload(image, to: rgb)
        var plane = DustUniforms(width: Int32(w), height: Int32(h))

        guard dispatch(gpu: gpu, pipeline: gpu.dustDensity, uniforms: plane, width: w, height: h, textures: [(rgb, true), (dens, false)]) else {
            return nil
        }

        let density = downloadPlane(dens, width: w, height: h)
        let (lo, spread) = OpticalDust.proxyNorm(density)
        plane.lo = lo
        plane.spread = spread
        guard dispatch(gpu: gpu, pipeline: gpu.dustProxy, uniforms: plane, width: w, height: h, textures: [(dens, true), (proxy, false)]) else {
            return nil
        }

        let scale = HealInpaint.filmScale(width: w, height: h)
        let base = max(1, Float(dustSize)) * scale
        let vWin = (Int(max(3, base * 3)) * 2) + 1
        let wWin = (Int(max(7, base * 4)) * 2) + 1
        let disk = (2 * Int(base.rounded())) + 1

        plane.ksize = Int32(vWin)
        guard dispatch(gpu: gpu, pipeline: gpu.dustMedian, uniforms: plane, width: w, height: h, textures: [(proxy, true), (median, false)]) else {
            return nil
        }

        plane.ksize = Int32(disk)
        guard dispatch(gpu: gpu, pipeline: gpu.dustMorphErode, uniforms: plane, width: w, height: h, textures: [(proxy, true), (openedE, false)]),
              dispatch(gpu: gpu, pipeline: gpu.dustMorphDilate, uniforms: plane, width: w, height: h, textures: [(openedE, true), (opened, false)])
        else {
            return nil
        }

        guard dispatch(
            gpu: gpu,
            pipeline: gpu.dustBackground,
            uniforms: plane,
            width: w,
            height: h,
            textures: [(proxy, true), (median, true), (opened, true), (background, false), (residual, false)]
        ) else {
            return nil
        }

        plane.ksize = Int32(OpticalDust.detectAvgPx)
        guard boxBlur(gpu: gpu, src: residual, dst: excess, scratch: scratch, uniforms: plane, width: w, height: h) else {
            return nil
        }

        guard dispatch(gpu: gpu, pipeline: gpu.dustMadSrc, uniforms: plane, width: w, height: h, textures: [(excess, true), (madSrc, false)]) else {
            return nil
        }

        plane.ksize = Int32(wWin)
        guard dispatch(gpu: gpu, pipeline: gpu.dustMedian, uniforms: plane, width: w, height: h, textures: [(madSrc, true), (mad, false)]) else {
            return nil
        }

        guard dispatch(gpu: gpu, pipeline: gpu.dustZ, uniforms: plane, width: w, height: h, textures: [(excess, true), (mad, true), (z, false)]) else {
            return nil
        }

        guard boxBlur(gpu: gpu, src: proxy, dst: mean, scratch: scratch, uniforms: plane, width: w, height: h),
              dispatch(gpu: gpu, pipeline: gpu.dustSquare, uniforms: plane, width: w, height: h, textures: [(proxy, true), (scratch, false)]),
              boxBlur(gpu: gpu, src: scratch, dst: meanSq, scratch: scratch, uniforms: plane, width: w, height: h),
              dispatch(
                  gpu: gpu,
                  pipeline: gpu.dustTextureStd,
                  uniforms: plane,
                  width: w,
                  height: h,
                  textures: [(proxy, true), (mean, true), (meanSq, true), (texture, false)]
              )
        else {
            return nil
        }

        return OpticalDust.DustStats(
            proxy: downloadPlane(proxy, width: w, height: h),
            background: downloadPlane(background, width: w, height: h),
            z: downloadPlane(z, width: w, height: h),
            texture: downloadPlane(texture, width: w, height: h)
        )
    }

    private static func boxBlur(
        gpu: MetalDevice.Runtime,
        src: MTLTexture,
        dst: MTLTexture,
        scratch: MTLTexture,
        uniforms: DustUniforms,
        width: Int,
        height: Int
    ) -> Bool {
        dispatch(gpu: gpu, pipeline: gpu.dustBoxBlurH, uniforms: uniforms, width: width, height: height, textures: [(src, true), (scratch, false)])
            && dispatch(gpu: gpu, pipeline: gpu.dustBoxBlurV, uniforms: uniforms, width: width, height: height, textures: [(scratch, true), (dst, false)])
    }

    private static func dispatch(
        gpu: MetalDevice.Runtime,
        pipeline: MTLComputePipelineState,
        uniforms: DustUniforms,
        width: Int,
        height: Int,
        textures: [(MTLTexture, Bool)]
    ) -> Bool {
        guard let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder(),
              let buf = gpu.makeBuffer(uniforms)
        else {
            return false
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buf, offset: 0, index: 0)
        for (idx, entry) in textures.enumerated() {
            encoder.setTexture(entry.0, index: idx)
        }
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        return command.status == .completed
    }

    private static func downloadPlane(_ texture: MTLTexture, width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: width * 16,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        var plane = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            plane[i] = out[i * 4]
        }
        return plane
    }

    private static func downloadRGB(_ texture: MTLTexture, width: Int, height: Int) -> LinearRGBBuffer {
        MetalPrint.download(texture, width: width, height: height)
    }
}

extension MetalDevice.Runtime {
    func makePlane(width: Int, height: Int) -> MTLTexture? {
        makeTexture(width: width, height: height, pixelFormat: .rgba32Float)
    }
}
#endif
