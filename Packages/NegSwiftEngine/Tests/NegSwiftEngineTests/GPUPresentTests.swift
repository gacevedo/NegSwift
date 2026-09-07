import CoreGraphics
import Foundation
import Testing
@testable import NegSwiftEngine

/// S13h: GPU present skips full-float `getBytes`; slider upload/download stay 0.
@Suite(.serialized)
struct GPUPresentTests {
    @Test func prefersPrecompiledMetallib() throws {
        try requireMetal()
        #expect(MetalDevice.loadedPrecompiledLibrary)
    }

    @Test func firstMetalPresentDoesNotDownloadFullFloatBuffer() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let first = try NativePipeline(pixelBackend: .metal).renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        #expect(first.gpuPresent != nil)
        #expect(first.gpuPresent?.isWorkingColorSpace == true)
        #expect(!first.downloadedLinear)
        #expect((first.gpuPresent?.width ?? 0) > 1)
        #expect((first.gpuPresent?.height ?? 0) > 1)
    }

    @Test func sliderReprintUploadAndDownloadStayZero() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .metal)
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        #expect(first.uploadedLinear)
        #expect(!first.downloadedLinear)
        var density = PrintConfig.s8Pin
        density.density += 0.2
        let second = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: density,
            readback: false
        )
        #expect(second.reusedBake)
        #expect(second.reusedAnalysis)
        #expect(!second.uploadedLinear)
        #expect(!second.downloadedLinear)
        #expect(second.gpuPresent != nil)
    }

    @Test func readbackStillMatchesCPU() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let cpu = try NativePipeline(pixelBackend: .cpu).renderPrint(
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
        #expect(gpu.meanAbsoluteError(against: cpu) < 0.002)
        #expect(PipelineStats.snapshot().download > 0)
    }

    @Test func cpuPresentTagsAdobeRGBWithoutColorSync() throws {
        let url = try writeOrangeMaskTIFF(width: 24, height: 16)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let result = try NativePipeline(pixelBackend: .cpu).renderPrintDetailed(
            path: url.path,
            longEdgePx: 32,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        #expect(result.gpuPresent?.isWorkingColorSpace == true)
        #expect(!result.downloadedLinear)
        #expect(result.gpuPresent?.width == result.buffer.width)
    }

    @Test func gpuPresentKeepsVerticalOrientation() throws {
        try requireMetal()
        let url = try writeTopBottomTIFF(width: 32, height: 24)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let cpu = try NativePipeline(pixelBackend: .cpu).renderPrintDetailed(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        let gpu = try NativePipeline(pixelBackend: .metal).renderPrintDetailed(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        let cpuImage = try #require(cpu.gpuPresent?.cgImage)
        let gpuImage = try #require(gpu.gpuPresent?.cgImage)
        let cpuBuf = try ImageCoding.buffer(from: cpuImage)
        let gpuBuf = try ImageCoding.buffer(from: gpuImage)
        let cpuTop = meanLuma(cpuBuf, y: 0)
        let cpuBot = meanLuma(cpuBuf, y: cpuBuf.height - 1)
        let gpuTop = meanLuma(gpuBuf, y: 0)
        let gpuBot = meanLuma(gpuBuf, y: gpuBuf.height - 1)
        #expect(abs(cpuTop - cpuBot) > 0.05)
        #expect(abs(gpuTop - cpuTop) < abs(gpuTop - cpuBot))
        #expect(abs(gpuBot - cpuBot) < abs(gpuBot - cpuTop))
    }

    @Test func isolatedSliderCountersStayZero() throws {
        try requireMetal()
        let url = try writeOrangeMaskTIFF(width: 36, height: 28)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .metal)
        _ = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin,
            readback: false
        )
        PipelineStats.reset()
        var density = PrintConfig.s8Pin
        density.density += 0.15
        let reprint = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: density,
            readback: false
        )
        #expect(!reprint.uploadedLinear)
        #expect(!reprint.downloadedLinear)
        // Meaningful when this suite runs alone (`make compare-s13`).
        #expect(PipelineStats.snapshot().upload == 0)
        #expect(PipelineStats.snapshot().download == 0)
    }

    private func requireMetal() throws {
        try #require(MetalDevice.isAvailable, "Metal unavailable — S13h falls back to CPU present")
    }
}

private func meanLuma(_ buffer: LinearRGBBuffer, y: Int) -> Float {
    var sum: Float = 0
    for x in 0..<buffer.width {
        let i = (y * buffer.width + x) * 3
        sum += 0.2126 * buffer.pixels[i] + 0.7152 * buffer.pixels[i + 1] + 0.0722 * buffer.pixels[i + 2]
    }
    return sum / Float(buffer.width)
}

/// Bright top band, dark bottom band — catches a present-path Y flip.
private func writeTopBottomTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    let mid = height / 2
    for y in 0..<height {
        let value: UInt16 = y < mid ? 50_000 : 4_000
        for x in 0..<width {
            let i = (y * width + x) * 3
            samples[i] = value
            samples[i + 1] = value
            samples[i + 2] = value
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13h-orient-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
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
        .appendingPathComponent("negswift-s13h-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
