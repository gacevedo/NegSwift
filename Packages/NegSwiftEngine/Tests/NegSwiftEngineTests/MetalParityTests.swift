import Foundation
import Testing
@testable import NegSwiftEngine

/// S12 gate: CPU-vs-Metal MAE on the used WGSL stages. No new look.
struct MetalParityTests {
    private static let stageMAE: Float = 5e-4
    private static let pipelineMAE: Float = 0.002

    @Test func infoReportsMetalWhenAvailable() {
        let info = NativePipeline(pixelBackend: .auto).infoJSON()
        #expect(info["gpu_available"] as? Bool == MetalDevice.isAvailable)
        if MetalDevice.isAvailable {
            #expect(info["gpu_backend"] as? String == "metal")
            #expect(info["pixel_backend"] as? String == "metal")
        } else {
            #expect(info["pixel_backend"] as? String == "cpu")
        }
    }

    @Test func normalizeMatchesCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 48, height: 32)
        let bounds = LogNormalization.analyzeBounds(linear: linear, processMode: .colorNegative)
        let cpu = LogNormalization.process(linear: linear, processMode: .colorNegative, bounds: bounds)
        let gpu = try #require(MetalPrint.normalize(linear, bounds: bounds))
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.stageMAE)
    }

    @Test func exposureMatchesCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 48, height: 32)
        let config = PrintConfig.s4aPin
        let bounds = LogNormalization.analyzeBounds(linear: linear, processMode: .colorNegative)
        let normalized = LogNormalization.process(linear: linear, processMode: .colorNegative, bounds: bounds)
        let params = PhotometricPrint.resolvePixelParams(
            linear: linear,
            bounds: bounds,
            processMode: .colorNegative,
            config: config
        )
        let cpu = PhotometricPrint.apply(normalized: normalized, params: params)
        let gpu = try #require(MetalPrint.applyExposure(normalized: normalized, params: params))
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.stageMAE)
    }

    @Test func oetfMatchesCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 32, height: 24)
        let cpu = WorkingOETF.encode(linear)
        let gpu = try #require(MetalPrint.encodeOETF(linear))
        #expect(gpu.meanAbsoluteError(against: cpu) < 1e-5)
    }

    @Test func labSharpenMatchesCPU() throws {
        try requireMetal()
        let linear = try decodeOrange(width: 40, height: 32)
        let printed = PhotometricPrint.process(linear: linear, processMode: .colorNegative, config: .s5Pin)
        let cpu = PhotoLab.process(printed, config: .s8Pin)
        let gpu = try #require(MetalPrint.applyLab(printed, config: .s8Pin))
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.stageMAE)
    }

    @Test func s8PipelineMatchesCPU() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let cpu = try NativePipeline().renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s8Pin
        )
        let gpu = try NativePipeline(pixelBackend: .metal).renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(gpu.width == cpu.width && gpu.height == cpu.height)
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.pipelineMAE)
    }

    @Test func s8ChromaAndZoneMatchCPU() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        var chroma = PrintConfig.s8Pin
        chroma.saturation = 1.3
        let zone = PrintConfig.s4bZoneOffset
        let cpuPipe = NativePipeline()
        let gpuPipe = NativePipeline(pixelBackend: .metal)
        let cpuChroma = try cpuPipe.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: chroma
        )
        let gpuChroma = try gpuPipe.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: chroma
        )
        #expect(gpuChroma.meanAbsoluteError(against: cpuChroma) < Self.pipelineMAE)

        let cpuZone = try cpuPipe.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: zone
        )
        let gpuZone = try gpuPipe.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: zone
        )
        #expect(gpuZone.meanAbsoluteError(against: cpuZone) < Self.pipelineMAE)
    }

    @Test func goldenFixtureS8MatchesCPU() throws {
        try requireMetal()
        guard let fixture = sampleTIFF() else {
            return
        }
        let cpu = try NativePipeline().renderPrint(
            path: fixture.path,
            longEdgePx: 256,
            processMode: .colorNegative,
            config: .s8Pin
        )
        let gpu = try NativePipeline(pixelBackend: .metal).renderPrint(
            path: fixture.path,
            longEdgePx: 256,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(gpu.width == cpu.width && gpu.height == cpu.height)
        #expect(gpu.meanAbsoluteError(against: cpu) < Self.pipelineMAE)
    }

    @Test func metalFallsBackWhenForcedUnavailablePathStillRenders() throws {
        let url = try writeOrangeMaskTIFF(width: 24, height: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        let cpu = try NativePipeline(pixelBackend: .cpu).renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(cpu.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    private func requireMetal() throws {
        try #require(MetalDevice.isAvailable, "Metal unavailable — S12 falls back to CPU")
    }

    private func decodeOrange(width: Int, height: Int) throws -> LinearRGBBuffer {
        let url = try writeOrangeMaskTIFF(width: width, height: height)
        defer { try? FileManager.default.removeItem(at: url) }
        return try LinearDecode.decode(path: url.path)
    }

    private func sampleTIFF() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("App/NegSwiftUITests/Fixtures/sample.tif")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
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
            .appendingPathComponent("negswift-s12-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
        return url
    }
}
