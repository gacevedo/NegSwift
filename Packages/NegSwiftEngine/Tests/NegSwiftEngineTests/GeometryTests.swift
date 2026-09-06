import Foundation
import Testing
@testable import NegSwiftEngine

struct GeometryTests {
    @Test func storedCropPixelROIMatchesNegPyIntSlice() {
        let roi = LinearRGBBuffer.storedCropPixelROI(
            width: 33,
            height: 33,
            rect: (0.1, 0.1, 0.3, 0.3)
        )
        #expect(roi?.x1 == 3)
        #expect(roi?.y1 == 3)
        #expect(roi?.x2 == 9)
        #expect(roi?.y2 == 9)
        #expect(LinearRGBBuffer.storedCropPixelROI(width: 10, height: 10, rect: (0.4, 0.4, 0.7, 0.7))?.x2 == 7)
        #expect(LinearRGBBuffer.storedCropPixelROI(width: 40, height: 32, rect: (0.25, 0.25, 0.75, 0.75))?.x2 == 30)
        #expect(LinearRGBBuffer.storedCropPixelROI(width: 8, height: 8, rect: (0.5, 0.5, 0.5, 0.51)) == nil)
    }

    @Test func rotate90CCWSwapsDimensionsAndMovesCorner() {
        var pixels = [Float](repeating: 0, count: 4 * 2 * 3)
        pixels[0] = 1
        let buffer = LinearRGBBuffer(width: 4, height: 2, pixels: pixels)
        let rotated = buffer.oriented(rotation: 1, flipHorizontal: false, flipVertical: false)
        #expect(rotated.width == 2)
        #expect(rotated.height == 4)
        #expect(rotated.pixels[(3 * 2) * 3] == 1)
        #expect(rotated.pixels[0] == 0)
    }

    @Test func flipHorizontalMirrorsColumns() {
        var pixels = [Float](repeating: 0, count: 3 * 1 * 3)
        pixels[0] = 1
        let buffer = LinearRGBBuffer(width: 3, height: 1, pixels: pixels)
        let flipped = buffer.oriented(rotation: 0, flipHorizontal: true, flipVertical: false)
        #expect(flipped.pixels[2 * 3] == 1)
        #expect(flipped.pixels[0] == 0)
    }

    @Test func fineRotationZeroIsIdentity() {
        let buffer = LinearRGBBuffer.stub(width: 8, height: 6, gray: 0.4)
        #expect(buffer.fineRotated(degrees: 0) == buffer)
    }

    @Test func fineRotationKeepsCanvasAndMovesMass() {
        var pixels = [Float](repeating: 0, count: 16 * 16 * 3)
        pixels[(8 * 16 + 12) * 3] = 1
        let buffer = LinearRGBBuffer(width: 16, height: 16, pixels: pixels)
        let rotated = buffer.fineRotated(degrees: 90)
        #expect(rotated.width == 16)
        #expect(rotated.height == 16)
        #expect(rotated.pixels != buffer.pixels)
        let peak = brightestIndex(rotated)
        #expect(abs(peak.x - 8) <= 1)
        #expect(abs(peak.y - 4) <= 1)
    }

    @Test func renderPrintRotatesPreviewDimensions() throws {
        let url = try writeGeometryTIFF(width: 40, height: 24)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        let base = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s5Pin
        )
        var rotated = PrintConfig.s5Pin
        rotated.rotation = 1
        let out = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: rotated
        )
        #expect(out.width == base.height)
        #expect(out.height == base.width)
    }

    @Test func renderPrintCropPreviewFullIsLargerThanAppliedCrop() throws {
        let url = try writeGeometryTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        var cropped = PrintConfig.s5Pin
        cropped.cropRect = NormalizedCropRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        cropped.applyPixelCrop = true
        var preview = cropped
        preview.applyPixelCrop = false
        let applied = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: cropped
        )
        let full = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: preview
        )
        #expect(full.width * full.height > applied.width * applied.height)
        #expect(full.width == applied.width * 2)
        #expect(full.height == applied.height * 2)
    }

    @Test func renderPrintCropPreviewFullMatchesAppliedInterior() throws {
        let url = try writeGeometryTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        var cropped = PrintConfig.s5Pin
        cropped.cropRect = NormalizedCropRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        cropped.autoDensityUsesCrop = true
        cropped.applyPixelCrop = true
        var preview = cropped
        preview.applyPixelCrop = false
        let applied = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: cropped
        )
        let full = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: preview
        )
        let roi = LinearRGBBuffer.storedCropPixelROI(
            width: full.width,
            height: full.height,
            rect: (0.25, 0.25, 0.75, 0.75)
        )
        #expect(roi != nil)
        guard let roi else { return }
        #expect(roi.x2 - roi.x1 == applied.width)
        #expect(roi.y2 - roi.y1 == applied.height)
        var maxAbs: Float = 0
        for y in 0..<applied.height {
            for x in 0..<applied.width {
                let src = ((roi.y1 + y) * full.width + (roi.x1 + x)) * 3
                let dst = (y * applied.width + x) * 3
                for c in 0..<3 {
                    maxAbs = max(maxAbs, abs(full.pixels[src + c] - applied.pixels[dst + c]))
                }
            }
        }
        #expect(maxAbs < 1e-5)
    }

    @Test func renderPrintFineRotationChangesPixelsKeepsSize() throws {
        let url = try writeGeometryTIFF(width: 40, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        let pin = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: .s5Pin
        )
        var fine = PrintConfig.s5Pin
        fine.fineRotation = 3
        let out = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: fine
        )
        #expect(out.width == pin.width)
        #expect(out.height == pin.height)
        #expect(out.pixels != pin.pixels)
    }

    @Test func printConfigMergesGeometryKeys() {
        let merged = PrintConfig.s5Pin.merging([
            "rotation": 1,
            "flip_horizontal": true,
            "flip_vertical": true,
            "fine_rotation": 4.5,
            "crop_rect": [0.1, 0.2, 0.8, 0.9],
            "crop_preview_full": true,
            "crop_detect_key": "1|1|1|4.5000|0.0|0.0|Free|image|1.0",
            "autocrop_ratio": "5:4",
            "autocrop_mode": "film",
        ])
        #expect(merged.rotation == 1)
        #expect(merged.flipHorizontal)
        #expect(merged.flipVertical)
        #expect(merged.fineRotation == 4.5)
        #expect(merged.applyPixelCrop == false)
        #expect(merged.cropRect == NormalizedCropRect(x1: 0.1, y1: 0.2, x2: 0.8, y2: 0.9))
        #expect(merged.cropDetectKey == "1|1|1|4.5000|0.0|0.0|Free|image|1.0")
        #expect(merged.autocropRatio == "5:4")
        #expect(merged.autocropMode == "film")
    }
}

private func brightestIndex(_ buffer: LinearRGBBuffer) -> (x: Int, y: Int) {
    var best = 0
    var value: Float = -1
    let n = buffer.width * buffer.height
    for i in 0..<n {
        let luma = buffer.pixels[i * 3]
        if luma > value {
            value = luma
            best = i
        }
    }
    return (best % buffer.width, best / buffer.width)
}

private func writeGeometryTIFF(width: Int, height: Int) throws -> URL {
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
        .appendingPathComponent("negswift-s6-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
