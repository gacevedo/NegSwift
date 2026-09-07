#if canImport(Metal)
import Foundation
import Metal
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(IOSurface)
import IOSurface
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif

/// Shared Metal device + compiled S12 lite kernels. Prefers a precompiled
/// `LiteKernels.metallib` (S13h); falls back to source when the library is
/// missing. Nil when the GPU is unavailable — callers fall back to CPU.
public enum MetalDevice: Sendable {
    public static let backendName = "metal"

    public static var isAvailable: Bool { runtime() != nil }

    /// True when `Runtime.make` loaded the precompiled metallib (not source).
    public static var loadedPrecompiledLibrary: Bool {
        runtime()?.usedPrecompiledLibrary ?? false
    }

    static func runtime() -> Runtime? {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        guard let built = Runtime.make() else {
            return nil
        }
        cached = built
        return built
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Runtime?

    final class Runtime: @unchecked Sendable {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let normalize: MTLComputePipelineState
        let exposure: MTLComputePipelineState
        let labSharpenH: MTLComputePipelineState
        let labSharpenV: MTLComputePipelineState
        let labApply: MTLComputePipelineState
        let outputEncode: MTLComputePipelineState
        let geometry: MTLComputePipelineState
        let present: MTLComputePipelineState
        let usedPrecompiledLibrary: Bool
        let dustErodeRGB: MTLComputePipelineState
        let dustDownsampleArea: MTLComputePipelineState
        let dustDensity: MTLComputePipelineState
        let dustProxy: MTLComputePipelineState
        let dustBoxBlurH: MTLComputePipelineState
        let dustBoxBlurV: MTLComputePipelineState
        let dustMedian: MTLComputePipelineState
        let dustMorphErode: MTLComputePipelineState
        let dustMorphDilate: MTLComputePipelineState
        let dustBackground: MTLComputePipelineState
        let dustMadSrc: MTLComputePipelineState
        let dustZ: MTLComputePipelineState
        let dustTextureStd: MTLComputePipelineState
        let dustSquare: MTLComputePipelineState
        #if canImport(CoreImage)
        let ciContext: CIContext
        #endif

        private var ping: MTLTexture?
        private var pong: MTLTexture?
        private var labTmp: MTLTexture?
        private var labBlur: MTLTexture?
        private var presentTex: MTLTexture?
        #if canImport(IOSurface)
        private var presentSurface: IOSurface?
        #endif

        static func make() -> Runtime? {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue()
            else {
                return nil
            }
            let loaded = makeLibrary(device: device)
            guard let library = loaded.library else {
                return nil
            }
            func pipeline(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else { return nil }
                return try? device.makeComputePipelineState(function: fn)
            }
            guard let normalize = pipeline("normalize_main"),
                  let exposure = pipeline("exposure_main"),
                  let labSharpenH = pipeline("lab_sharpen_h"),
                  let labSharpenV = pipeline("lab_sharpen_v"),
                  let labApply = pipeline("lab_apply"),
                  let outputEncode = pipeline("output_encode"),
                  let geometry = pipeline("geometry_main"),
                  let present = pipeline("present_main"),
                  let dustErodeRGB = pipeline("dust_erode_rgb_main"),
                  let dustDownsampleArea = pipeline("dust_downsample_area_main"),
                  let dustDensity = pipeline("dust_density_main"),
                  let dustProxy = pipeline("dust_proxy_main"),
                  let dustBoxBlurH = pipeline("dust_box_blur_h_main"),
                  let dustBoxBlurV = pipeline("dust_box_blur_v_main"),
                  let dustMedian = pipeline("dust_median_main"),
                  let dustMorphErode = pipeline("dust_morph_erode_main"),
                  let dustMorphDilate = pipeline("dust_morph_dilate_main"),
                  let dustBackground = pipeline("dust_background_main"),
                  let dustMadSrc = pipeline("dust_mad_src_main"),
                  let dustZ = pipeline("dust_z_main"),
                  let dustTextureStd = pipeline("dust_texture_std_main"),
                  let dustSquare = pipeline("dust_square_main")
            else {
                return nil
            }
            return Runtime(
                device: device,
                queue: queue,
                normalize: normalize,
                exposure: exposure,
                labSharpenH: labSharpenH,
                labSharpenV: labSharpenV,
                labApply: labApply,
                outputEncode: outputEncode,
                geometry: geometry,
                present: present,
                usedPrecompiledLibrary: loaded.precompiled,
                dustErodeRGB: dustErodeRGB,
                dustDownsampleArea: dustDownsampleArea,
                dustDensity: dustDensity,
                dustProxy: dustProxy,
                dustBoxBlurH: dustBoxBlurH,
                dustBoxBlurV: dustBoxBlurV,
                dustMedian: dustMedian,
                dustMorphErode: dustMorphErode,
                dustMorphDilate: dustMorphDilate,
                dustBackground: dustBackground,
                dustMadSrc: dustMadSrc,
                dustZ: dustZ,
                dustTextureStd: dustTextureStd,
                dustSquare: dustSquare
            )
        }

        private init(
            device: MTLDevice,
            queue: MTLCommandQueue,
            normalize: MTLComputePipelineState,
            exposure: MTLComputePipelineState,
            labSharpenH: MTLComputePipelineState,
            labSharpenV: MTLComputePipelineState,
            labApply: MTLComputePipelineState,
            outputEncode: MTLComputePipelineState,
            geometry: MTLComputePipelineState,
            present: MTLComputePipelineState,
            usedPrecompiledLibrary: Bool,
            dustErodeRGB: MTLComputePipelineState,
            dustDownsampleArea: MTLComputePipelineState,
            dustDensity: MTLComputePipelineState,
            dustProxy: MTLComputePipelineState,
            dustBoxBlurH: MTLComputePipelineState,
            dustBoxBlurV: MTLComputePipelineState,
            dustMedian: MTLComputePipelineState,
            dustMorphErode: MTLComputePipelineState,
            dustMorphDilate: MTLComputePipelineState,
            dustBackground: MTLComputePipelineState,
            dustMadSrc: MTLComputePipelineState,
            dustZ: MTLComputePipelineState,
            dustTextureStd: MTLComputePipelineState,
            dustSquare: MTLComputePipelineState
        ) {
            self.device = device
            self.queue = queue
            self.normalize = normalize
            self.exposure = exposure
            self.labSharpenH = labSharpenH
            self.labSharpenV = labSharpenV
            self.labApply = labApply
            self.outputEncode = outputEncode
            self.geometry = geometry
            self.present = present
            self.usedPrecompiledLibrary = usedPrecompiledLibrary
            self.dustErodeRGB = dustErodeRGB
            self.dustDownsampleArea = dustDownsampleArea
            self.dustDensity = dustDensity
            self.dustProxy = dustProxy
            self.dustBoxBlurH = dustBoxBlurH
            self.dustBoxBlurV = dustBoxBlurV
            self.dustMedian = dustMedian
            self.dustMorphErode = dustMorphErode
            self.dustMorphDilate = dustMorphDilate
            self.dustBackground = dustBackground
            self.dustMadSrc = dustMadSrc
            self.dustZ = dustZ
            self.dustTextureStd = dustTextureStd
            self.dustSquare = dustSquare
            #if canImport(CoreImage)
            let adobe = CGColorSpace(name: CGColorSpace.adobeRGB1998)
            var options: [CIContextOption: Any] = [.cacheIntermediates: false]
            if let adobe {
                options[.workingColorSpace] = adobe
                options[.outputColorSpace] = adobe
            }
            self.ciContext = CIContext(mtlDevice: device, options: options)
            #endif
        }

        private static func makeLibrary(device: MTLDevice) -> (library: MTLLibrary?, precompiled: Bool) {
            func sourceLibrary() -> MTLLibrary? {
                guard let source = kernelSource() else { return nil }
                return try? device.makeLibrary(source: source, options: nil)
            }
            let metallibURLs = [
                Bundle.module.url(forResource: "LiteKernels", withExtension: "metallib"),
                Bundle.module.url(forResource: "LiteKernels", withExtension: "metallib", subdirectory: "Metal"),
            ]
            for url in metallibURLs {
                if let url, let library = try? device.makeLibrary(URL: url) {
                    if library.makeFunction(name: "dust_erode_rgb_main") != nil {
                        return (library, true)
                    }
                    // Precompiled metallib predates S13l dust kernels — compile from source.
                    if let live = sourceLibrary() {
                        return (live, false)
                    }
                }
            }
            guard let library = sourceLibrary() else {
                return (nil, false)
            }
            return (library, false)
        }

        private static func kernelSource() -> String? {
            let urls = [
                Bundle.module.url(forResource: "LiteKernels", withExtension: "metal"),
                Bundle.module.url(forResource: "LiteKernels", withExtension: "metal", subdirectory: "Metal"),
            ]
            for url in urls {
                if let url, let source = try? String(contentsOf: url, encoding: .utf8) {
                    return source
                }
            }
            return nil
        }

        func makeTexture(width: Int, height: Int) -> MTLTexture? {
            makeTexture(width: width, height: height, pixelFormat: .rgba32Float)
        }

        func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            return device.makeTexture(descriptor: desc)
        }

        /// Reused rgba32Float ping/pong for the print chain (S13h).
        func workingPair(width: Int, height: Int) -> (ping: MTLTexture, pong: MTLTexture)? {
            if let ping, let pong, ping.width == width, ping.height == height {
                return (ping, pong)
            }
            guard let a = makeTexture(width: width, height: height),
                  let b = makeTexture(width: width, height: height)
            else {
                return nil
            }
            ping = a
            pong = b
            return (a, b)
        }

        /// Reused Lab blur temps (same size as the working pair).
        func labScratch(width: Int, height: Int) -> (tmp: MTLTexture, blur: MTLTexture)? {
            if let labTmp, let labBlur, labTmp.width == width, labTmp.height == height {
                return (labTmp, labBlur)
            }
            guard let tmp = makeTexture(width: width, height: height),
                  let blur = makeTexture(width: width, height: height)
            else {
                return nil
            }
            labTmp = tmp
            labBlur = blur
            return (tmp, blur)
        }

        /// rgba16Float present target, IOSurface-backed when the OS allows it.
        func presentTarget(width: Int, height: Int) -> PresentTarget? {
            if let presentTex, presentTex.width == width, presentTex.height == height {
                #if canImport(IOSurface)
                return PresentTarget(texture: presentTex, surface: presentSurface)
                #else
                return PresentTarget(texture: presentTex, surface: nil)
                #endif
            }
            #if canImport(IOSurface) && canImport(CoreVideo)
            if let built = makeIOSurfacePresent(width: width, height: height) {
                presentTex = built.texture
                presentSurface = built.surface
                return built
            }
            #endif
            guard let tex = makeTexture(width: width, height: height, pixelFormat: .rgba16Float) else {
                return nil
            }
            presentTex = tex
            #if canImport(IOSurface)
            presentSurface = nil
            #endif
            return PresentTarget(texture: tex, surface: nil)
        }

        #if canImport(IOSurface) && canImport(CoreVideo)
        private func makeIOSurfacePresent(width: Int, height: Int) -> PresentTarget? {
            let bytesPerPixel = 8
            let align = IOSurfaceAlignProperty(IOSurfacePropertyKey.bytesPerRow.rawValue as CFString, width * bytesPerPixel)
            let bytesPerRow = max(align, width * bytesPerPixel)
            let props: [IOSurfacePropertyKey: Any] = [
                .width: width,
                .height: height,
                .pixelFormat: kCVPixelFormatType_64RGBAHalf,
                .bytesPerElement: bytesPerPixel,
                .bytesPerRow: bytesPerRow,
                .allocSize: bytesPerRow * height,
            ]
            guard let surface = IOSurface(properties: props) else {
                return nil
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0) else {
                return nil
            }
            return PresentTarget(texture: texture, surface: surface)
        }
        #endif

        func makeBuffer<T>(_ value: T) -> MTLBuffer? {
            var copy = value
            return withUnsafeBytes(of: &copy) { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count)
            }
        }

        func makeFloatBuffer(_ values: [Float]) -> MTLBuffer? {
            values.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count)
            }
        }

        func resetScratch() {
            ping = nil
            pong = nil
            labTmp = nil
            labBlur = nil
            presentTex = nil
            #if canImport(IOSurface)
            presentSurface = nil
            #endif
        }
    }

    struct PresentTarget {
        let texture: MTLTexture
        #if canImport(IOSurface)
        let surface: IOSurface?
        #else
        let surface: Any?
        #endif
    }
}
#else
public enum MetalDevice: Sendable {
    public static let backendName = "metal"
    public static var isAvailable: Bool { false }
    public static var loadedPrecompiledLibrary: Bool { false }
}
#endif
