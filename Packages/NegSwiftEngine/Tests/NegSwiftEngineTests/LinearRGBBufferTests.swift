import Foundation
import Testing
@testable import NegSwiftEngine

struct LinearRGBBufferTests {
    @Test func stubHasExpectedShape() {
        let buffer = LinearRGBBuffer.stub(width: 8, height: 4)
        #expect(buffer.width == 8)
        #expect(buffer.height == 4)
        #expect(buffer.pixels.count == 8 * 4 * 3)
        #expect(buffer.pixels.allSatisfy { $0 == 0.5 })
    }

    @Test func pngRoundTripWritesFile() throws {
        let buffer = LinearRGBBuffer.stub(width: 16, height: 16, gray: 0.25)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-engine-s0-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageCoding.writePNG(buffer, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let probed = ImageCoding.probeDimensions(at: url)
        #expect(probed?.width == 16)
        #expect(probed?.height == 16)
    }

    @Test func stubPreviewRespectsLongEdgeCap() {
        let pipeline = NativePipeline()
        let buffer = pipeline.stubPreview(longEdgePx: 2048)
        #expect(buffer.width == 512)
        #expect(buffer.height == 512)
    }

    @Test func jpegDataIsNonEmptySOI() throws {
        let data = try ImageCoding.jpegData(from: .stub(width: 8, height: 8), quality: 0.9)
        #expect(data.count > 16)
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0xD8)
    }

    @Test func analysisCenterCropMatchesNegPyInset() {
        let buffer = LinearRGBBuffer.stub(width: 200, height: 100)
        let cropped = buffer.analysisCenterCrop(bufferRatio: 0.12)
        #expect(cropped.width == 200 - 2 * 24)
        #expect(cropped.height == 100 - 2 * 12)
        #expect(buffer.analysisCenterCrop(bufferRatio: 0).width == 200)
        let clamped = buffer.analysisCenterCrop(bufferRatio: 0.9)
        #expect(clamped.width == 200 - 2 * 60)
        #expect(clamped.height == 100 - 2 * 30)
    }

    @Test func downsampledCapsLongEdgeAndIsIdentityWhenSmall() {
        let buffer = LinearRGBBuffer.stub(width: 40, height: 20)
        let small = buffer.downsampled(toLongEdge: 10)
        #expect(small.width == 10)
        #expect(small.height == 5)
        #expect(buffer.downsampled(toLongEdge: 40).width == 40)
    }

    @Test func areaDownsampledAveragesPinholes() {
        var pixels = [Float](repeating: 0.2, count: 4 * 4 * 3)
        pixels[0] = 0
        pixels[1] = 0
        pixels[2] = 0
        let buffer = LinearRGBBuffer(width: 4, height: 4, pixels: pixels)
        let nearest = buffer.downsampled(toLongEdge: 2)
        let area = buffer.areaDownsampled(toLongEdge: 2)
        #expect(area.width == 2)
        #expect(area.height == 2)
        #expect(nearest.pixels[0] == 0)
        #expect(area.pixels[0] > 0.1)
    }

    @Test func croppedToAnalysisROIMatchesNegPyIntSlice() {
        let buffer = LinearRGBBuffer.stub(width: 100, height: 50)
        let roi = buffer.croppedToAnalysisROI(normalized: (0.1, 0.2, 0.8, 0.9))
        #expect(roi.width == Int(0.8 * 100) - Int(0.1 * 100))
        #expect(roi.height == Int(0.9 * 50) - Int(0.2 * 50))
        #expect(buffer.croppedToAnalysisROI(normalized: (0, 0, 1, 1)).width == 100)
        #expect(buffer.croppedToAnalysisROI(normalized: (0.5, 0.5, 0.5, 0.51)).width == 100)
    }

    @Test func croppedNormalizedTakesInterior() {
        var pixels = [Float](repeating: 0, count: 10 * 10 * 3)
        pixels[(5 * 10 + 5) * 3] = 1
        let buffer = LinearRGBBuffer(width: 10, height: 10, pixels: pixels)
        let cropped = buffer.cropped(normalized: (0.4, 0.4, 0.7, 0.7))
        #expect(cropped.width == 3)
        #expect(cropped.height == 3)
        #expect(cropped.pixels.contains(where: { $0 == 1 }))
    }

    @Test func croppedNormalizedUsesNegPyTruncation() {
        let buffer = LinearRGBBuffer.stub(width: 33, height: 33)
        let cropped = buffer.cropped(normalized: (0.1, 0.1, 0.3, 0.3))
        #expect(cropped.width == 6)
        #expect(cropped.height == 6)
    }

    @Test func rotate180MovesCornerToOpposite() {
        var pixels = [Float](repeating: 0, count: 4 * 2 * 3)
        pixels[0] = 1
        let buffer = LinearRGBBuffer(width: 4, height: 2, pixels: pixels)
        let rotated = buffer.oriented(rotation: 2, flipHorizontal: false, flipVertical: false)
        #expect(rotated.width == 4)
        #expect(rotated.height == 2)
        #expect(rotated.pixels[(2 * 4 - 1) * 3] == 1)
        #expect(rotated.pixels[0] == 0)
    }

    @Test func applyingExifOrientationMatchesNegPy() {
        var pixels = [Float](repeating: 0, count: 2 * 3 * 3)
        pixels[0] = 1
        let buffer = LinearRGBBuffer(width: 2, height: 3, pixels: pixels)
        #expect(buffer.applyingExifOrientation(1).pixels[0] == 1)
        let flippedH = buffer.applyingExifOrientation(2)
        #expect(flippedH.width == 2)
        #expect(flippedH.pixels[1 * 3] == 1)
        let rot180 = buffer.applyingExifOrientation(3)
        #expect(rot180.pixels[(2 * 3 - 1) * 3] == 1)
        let cw = buffer.applyingExifOrientation(6)
        #expect(cw.width == 3)
        #expect(cw.height == 2)
        #expect(cw.pixels[2 * 3] == 1)
        let ccw = buffer.applyingExifOrientation(8)
        #expect(ccw.width == 3)
        #expect(ccw.height == 2)
        #expect(ccw.pixels[(1 * 3 + 0) * 3] == 1)
    }

    @Test func stridedDownsampleUsesCeilStep() {
        let buffer = LinearRGBBuffer.stub(width: 300, height: 200)
        let down = buffer.stridedDownsample(maxDim: 256)
        #expect(down.width == 150)
        #expect(down.height == 100)
        #expect(buffer.stridedDownsample(maxDim: 300).width == 300)
    }
}
