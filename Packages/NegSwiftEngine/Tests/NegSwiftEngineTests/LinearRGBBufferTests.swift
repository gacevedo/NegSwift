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
}
