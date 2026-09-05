import Foundation
import Testing
@testable import NegSwiftEngine

struct AnalysisBufferCropTests {
    @Test func autoCropLiveBufferShiftsPrintWhenHolderIsInCrop() throws {
        let url = try writeHolderBorderTIFF(width: 200, height: 160)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        var tight = PrintConfig.s5Pin
        tight.grade = 100
        tight.cropRect = NormalizedCropRect(x1: 0.05, y1: 0.05, x2: 0.95, y2: 0.95)
        tight.cropFromAuto = true
        tight.autoDensityUsesCrop = true
        tight.analysisBuffer = 0
        tight.applyPixelCrop = true
        var loose = tight
        loose.analysisBuffer = 0.25
        let a = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: tight
        )
        let b = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: loose
        )
        #expect(a.width == b.width)
        #expect(a.pixels != b.pixels)
        let delta = meanAbsDelta(a, b)
        #expect(delta > 0.02)
    }

    @Test func previewOversampleLetsBufferMoveExposureOnCroppedScan() throws {
        let path = "/Users/gacevedo/Downloads/Kodak Portra Gold 120 K6500-008.TIFF"
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        let pipeline = NativePipeline()
        var tight = PrintConfig.s5Pin
        tight.grade = 100
        tight.cropRect = NormalizedCropRect(
            x1: 0.104375,
            y1: 0.028142589118198873,
            x2: 0.958125,
            y2: 0.9896810506566605
        )
        tight.cropFromAuto = true
        tight.analysisBuffer = 0
        var loose = tight
        loose.analysisBuffer = 0.25
        let a = try pipeline.renderPrint(
            path: path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: tight
        )
        let b = try pipeline.renderPrint(
            path: path,
            longEdgePx: 1600,
            processMode: .colorNegative,
            config: loose
        )
        #expect(meanAbsDelta(a, b) > 0.008)
    }
}

/// Dark holder border + brighter film; crop still includes some holder.
private func writeHolderBorderTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    let insetX = width / 5
    let insetY = height / 5
    for y in 0..<height {
        for x in 0..<width {
            let film = x >= insetX && x < width - insetX && y >= insetY && y < height - insetY
            let i = (y * width + x) * 3
            if film {
                samples[i] = UInt16(clamping: Int((0.70 * 65535).rounded()))
                samples[i + 1] = UInt16(clamping: Int((0.38 * 65535).rounded()))
                samples[i + 2] = UInt16(clamping: Int((0.16 * 65535).rounded()))
            } else {
                samples[i] = UInt16(clamping: Int((0.95 * 65535).rounded()))
                samples[i + 1] = UInt16(clamping: Int((0.92 * 65535).rounded()))
                samples[i + 2] = UInt16(clamping: Int((0.88 * 65535).rounded()))
            }
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-holder-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func meanAbsDelta(_ a: LinearRGBBuffer, _ b: LinearRGBBuffer) -> Float {
    let n = min(a.pixels.count, b.pixels.count)
    var sum: Float = 0
    for i in 0..<n {
        sum += abs(a.pixels[i] - b.pixels[i])
    }
    return sum / Float(n)
}
