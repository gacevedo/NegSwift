import CoreGraphics
import Foundation

#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(Metal)
import Metal
#endif
#if canImport(IOSurface)
import IOSurface
#endif

/// S13h in-process present: Adobe RGB working numbers, no ColorSync hop to sRGB.
public struct GPUPresentImage: @unchecked Sendable {
    public var width: Int
    public var height: Int
    public var cgImage: CGImage
    #if canImport(CoreImage)
    public var ciImage: CIImage?
    #endif

    public var isWorkingColorSpace: Bool {
        cgImage.colorSpace?.name == CGColorSpace.adobeRGB1998
    }

    public init(width: Int, height: Int, cgImage: CGImage, ciImage: CIImage? = nil) {
        self.width = width
        self.height = height
        self.cgImage = cgImage
        #if canImport(CoreImage)
        self.ciImage = ciImage
        #endif
    }
}

#if canImport(Metal)
enum GPUPresent {
    struct Uniforms {
        var originX: Int32
        var originY: Int32
    }

    /// Blit the working-set ROI into an rgba16Float present texture and wrap it
    /// as Adobe RGB `CIImage` / `CGImage`. Does not `getBytes` the float buffer.
    static func image(
        gpu: MetalDevice.Runtime,
        source: MTLTexture,
        width: Int,
        height: Int,
        originX: Int = 0,
        originY: Int = 0
    ) -> GPUPresentImage? {
        guard let target = gpu.presentTarget(width: width, height: height),
              let uniforms = gpu.makeBuffer(Uniforms(originX: Int32(originX), originY: Int32(originY))),
              let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder()
        else {
            return nil
        }
        encoder.setComputePipelineState(gpu.present)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(target.texture, index: 1)
        encoder.setBuffer(uniforms, offset: 0, index: 0)
        let w = gpu.present.threadExecutionWidth
        let h = max(1, gpu.present.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            return nil
        }
        return wrap(gpu: gpu, target: target, width: width, height: height)
    }

    private static func wrap(
        gpu: MetalDevice.Runtime,
        target: MetalDevice.PresentTarget,
        width: Int,
        height: Int
    ) -> GPUPresentImage? {
        guard let adobe = CGColorSpace(name: CGColorSpace.adobeRGB1998) else {
            return nil
        }
        #if canImport(CoreImage)
        let image: CIImage
        #if canImport(IOSurface)
        if let surface = target.surface {
            // IOSurface row 0 is the top of the working image (same as the CPU buffer).
            image = CIImage(ioSurface: surface, options: [.colorSpace: adobe])
        } else {
            guard let metalImage = CIImage(mtlTexture: target.texture, options: [.colorSpace: adobe]) else {
                return nil
            }
            image = flipVertical(metalImage, height: height)
        }
        #else
        guard let metalImage = CIImage(mtlTexture: target.texture, options: [.colorSpace: adobe]) else {
            return nil
        }
        image = flipVertical(metalImage, height: height)
        #endif
        guard let cgImage = gpu.ciContext.createCGImage(
            image,
            from: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: adobe
        ) else {
            return nil
        }
        return GPUPresentImage(width: width, height: height, cgImage: cgImage, ciImage: image)
        #else
        return nil
        #endif
    }

    /// `CIImage(mtlTexture:)` treats Metal's origin as bottom-left. The print
    /// kernels write y=0 as the top row, matching the CPU buffer.
    private static func flipVertical(_ image: CIImage, height: Int) -> CIImage {
        image.transformed(
            by: CGAffineTransform(translationX: 0, y: CGFloat(height)).scaledBy(x: 1, y: -1)
        )
    }
}
#endif
