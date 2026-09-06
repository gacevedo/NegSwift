import Foundation
import Testing
@testable import NegSwiftEngine

/// S13b: CPU-vs-Metal geometry MAE (S6 variants, including fine-rot).
@Suite(.serialized)
struct MetalGeometryTests {
    private static let discreteMAE: Float = 1e-5
    private static let fineRotMAE: Float = 5e-4
    private static let pipelineMAE: Float = 0.002

    @Test func rotateAndFlipMatchCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 48, height: 32)
        let variants: [(Int, Bool, Bool, Float)] = [
            (1, false, false, 0),
            (2, false, false, 0),
            (3, false, false, 0),
            (0, true, false, 0),
            (0, false, true, 0),
            (0, true, true, 0),
            (1, true, true, 0),
        ]
        for (rot, flipH, flipV, fine) in variants {
            let cpu = linear.oriented(
                rotation: rot,
                flipHorizontal: flipH,
                flipVertical: flipV,
                fineRotation: fine
            )
            let gpu = try #require(
                MetalGeometry.oriented(
                    linear,
                    rotation: rot,
                    flipHorizontal: flipH,
                    flipVertical: flipV,
                    fineRotation: fine
                )
            )
            #expect(gpu.width == cpu.width && gpu.height == cpu.height)
            #expect(gpu.meanAbsoluteError(against: cpu) < Self.discreteMAE)
        }
    }

    @Test func fineRotationMatchesCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 40, height: 32)
        for degrees: Float in [2.5, 15, -7] {
            let cpu = linear.fineRotated(degrees: degrees)
            let gpu = try #require(
                MetalGeometry.oriented(
                    linear,
                    rotation: 0,
                    flipHorizontal: false,
                    flipVertical: false,
                    fineRotation: degrees
                )
            )
            #expect(gpu.width == cpu.width && gpu.height == cpu.height)
            #expect(gpu.meanAbsoluteError(against: cpu) < Self.fineRotMAE)
        }
    }

    @Test func s6PipelineVariantsMatchCPU() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let cpuPipe = NativePipeline(pixelBackend: .cpu)
        let gpuPipe = NativePipeline(pixelBackend: .metal)
        var crop = PrintConfig.s5Pin
        crop.cropRect = NormalizedCropRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        var rot = PrintConfig.s5Pin
        rot.rotation = 1
        var flip = PrintConfig.s5Pin
        flip.flipHorizontal = true
        flip.flipVertical = true
        var fine = PrintConfig.s5Pin
        fine.fineRotation = 2.5
        for config in [crop, rot, flip, fine] {
            let cpu = try cpuPipe.renderPrint(
                path: url.path,
                longEdgePx: 64,
                processMode: .colorNegative,
                config: config
            )
            let gpu = try gpuPipe.renderPrint(
                path: url.path,
                longEdgePx: 64,
                processMode: .colorNegative,
                config: config
            )
            #expect(gpu.width == cpu.width && gpu.height == cpu.height)
            #expect(gpu.meanAbsoluteError(against: cpu) < Self.pipelineMAE)
        }
    }

    @Test func sliderMetalReprintDoesNotReupload() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline(pixelBackend: .metal)
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(first.uploadedLinear)
        var density = PrintConfig.s8Pin
        density.density += 0.2
        let second = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: density
        )
        #expect(second.reusedBake)
        #expect(second.reusedAnalysis)
        #expect(!second.uploadedLinear)
    }

    private func requireMetal() throws {
        try #require(MetalDevice.isAvailable, "Metal unavailable — S13b/c fall back to CPU")
    }

    private func decodeOrange(width: Int, height: Int) throws -> LinearRGBBuffer {
        let url = try writeOrangeMaskTIFF(width: width, height: height)
        defer { try? FileManager.default.removeItem(at: url) }
        return try LinearDecode.decode(path: url.path)
    }

    private func writeOrangeMaskTIFF(width: Int, height: Int) throws -> URL {
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        let cy = Double(height - 1) / 2
        let cx = Double(width - 1) / 2
        for y in 0..<height {
            for x in 0..<width {
                let dist = pow((Double(y) - cy) / Double(height), 2) + pow((Double(x) - cx) / Double(width), 2)
                let t = 0.25 + 0.55 * dist
                let i = (y * width + x) * 3
                samples[i] = UInt16(clamping: Int((min(1, max(1e-6, 0.70 * t)) * 65535).rounded()))
                samples[i + 1] = UInt16(clamping: Int((min(1, max(1e-6, 0.38 * t)) * 65535).rounded()))
                samples[i + 2] = UInt16(clamping: Int((min(1, max(1e-6, 0.16 * t)) * 65535).rounded()))
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13b-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
        return url
    }
}
