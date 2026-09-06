import Foundation

#if canImport(Metal)
import Metal
#endif

/// S13b: used `transform.wgsl` lite subset (90°, flips, fine-rot). Keystone / k1 stay unused.
/// Matches CPU ``LinearRGBBuffer.oriented``. Nil when Metal is unavailable.
public enum MetalGeometry: Sendable {
    public static func outputSize(
        width: Int,
        height: Int,
        rotation: Int
    ) -> (width: Int, height: Int) {
        let turns = ((rotation % 4) + 4) % 4
        if turns % 2 == 1 {
            return (height, width)
        }
        return (width, height)
    }

    public static func isIdentity(
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float
    ) -> Bool {
        ((rotation % 4) + 4) % 4 == 0 && !flipHorizontal && !flipVertical && fineRotation == 0
    }

    public static func oriented(
        _ linear: LinearRGBBuffer,
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float = 0
    ) -> LinearRGBBuffer? {
        #if canImport(Metal)
        guard MetalDevice.isAvailable else { return nil }
        if isIdentity(
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            fineRotation: fineRotation
        ) {
            return linear
        }
        return run(
            linear,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            fineRotation: fineRotation
        )
        #else
        return nil
        #endif
    }
}

#if canImport(Metal)
extension MetalGeometry {
    struct Uniforms {
        var rotation: Int32
        var flipH: Int32
        var flipV: Int32
        var srcWidth: Int32
        var srcHeight: Int32
        var dstWidth: Int32
        var dstHeight: Int32
        var fineRotation: Float
    }

    static func uniforms(
        srcWidth: Int,
        srcHeight: Int,
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float
    ) -> Uniforms {
        let dest = outputSize(width: srcWidth, height: srcHeight, rotation: rotation)
        return Uniforms(
            rotation: Int32(((rotation % 4) + 4) % 4),
            flipH: flipHorizontal ? 1 : 0,
            flipV: flipVertical ? 1 : 0,
            srcWidth: Int32(srcWidth),
            srcHeight: Int32(srcHeight),
            dstWidth: Int32(dest.width),
            dstHeight: Int32(dest.height),
            fineRotation: fineRotation
        )
    }

    private static func run(
        _ linear: LinearRGBBuffer,
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float
    ) -> LinearRGBBuffer? {
        guard let gpu = MetalDevice.runtime() else { return nil }
        let dest = outputSize(width: linear.width, height: linear.height, rotation: rotation)
        guard let src = gpu.makeTexture(width: linear.width, height: linear.height),
              let dst = gpu.makeTexture(width: dest.width, height: dest.height)
        else {
            return nil
        }
        MetalPrint.upload(linear, to: src)
        PipelineStats.increment(.upload)
        guard apply(
            gpu: gpu,
            source: src,
            destination: dst,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            fineRotation: fineRotation
        ) else {
            return nil
        }
        return MetalPrint.download(dst, width: dest.width, height: dest.height)
    }

    static func apply(
        gpu: MetalDevice.Runtime,
        source: MTLTexture,
        destination: MTLTexture,
        rotation: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        fineRotation: Float
    ) -> Bool {
        let u = uniforms(
            srcWidth: source.width,
            srcHeight: source.height,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            fineRotation: fineRotation
        )
        guard let buf = gpu.makeBuffer(u),
              let command = gpu.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder()
        else {
            return false
        }
        encoder.setComputePipelineState(gpu.geometry)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setBuffer(buf, offset: 0, index: 0)
        let w = gpu.geometry.threadExecutionWidth
        let h = max(1, gpu.geometry.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: destination.width, height: destination.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        return command.status == .completed
    }
}
#endif
