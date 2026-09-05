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

    @Test func stridedDownsampleUsesCeilStep() {
        let buffer = LinearRGBBuffer.stub(width: 300, height: 200)
        let down = buffer.stridedDownsample(maxDim: 256)
        #expect(down.width == 150)
        #expect(down.height == 100)
        #expect(buffer.stridedDownsample(maxDim: 300).width == 300)
    }
}
