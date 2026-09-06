#if canImport(Metal)
import Foundation
import Metal

/// Shared Metal device + compiled S12 lite kernels. Nil when the GPU or
/// `LiteKernels.metal` is unavailable — callers fall back to CPU.
public enum MetalDevice: Sendable {
    public static let backendName = "metal"

    public static var isAvailable: Bool { runtime() != nil }

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

        static func make() -> Runtime? {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let source = kernelSource(),
                  let library = try? device.makeLibrary(source: source, options: nil)
            else {
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
                  let outputEncode = pipeline("output_encode")
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
                outputEncode: outputEncode
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
            outputEncode: MTLComputePipelineState
        ) {
            self.device = device
            self.queue = queue
            self.normalize = normalize
            self.exposure = exposure
            self.labSharpenH = labSharpenH
            self.labSharpenV = labSharpenV
            self.labApply = labApply
            self.outputEncode = outputEncode
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
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            return device.makeTexture(descriptor: desc)
        }

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
    }
}
#else
public enum MetalDevice: Sendable {
    public static let backendName = "metal"
    public static var isAvailable: Bool { false }
}
#endif
