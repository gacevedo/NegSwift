import CoreGraphics
import Foundation
import Testing
@testable import NegSwiftEngine

struct DisplayTransformTests {
    @Test func blackAndWhiteStayPut() throws {
        let ramp = LinearRGBBuffer(width: 2, height: 1, pixels: [0, 0, 0, 1, 1, 1])
        let srgb = try DisplayTransform.workingToSRGB(ramp)
        #expect(srgb.width == 2)
        #expect(srgb.height == 1)
        #expect(abs(srgb.pixels[0] - 0) < 1.0 / 255)
        #expect(abs(srgb.pixels[3] - 1) < 1.0 / 255)
    }

    @Test func saturatedWorkingGreenMovesTowardSRGB() throws {
        let adobe = LinearRGBBuffer(width: 1, height: 1, pixels: [0.05, 0.85, 0.15])
        let srgb = try DisplayTransform.workingToSRGB(adobe)
        #expect(srgb.pixels != adobe.pixels)
        #expect(srgb.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func workingImageTagsAdobeRGB() throws {
        let image = try DisplayTransform.workingImage(fromWorkingSpace: .stub(width: 4, height: 3))
        #expect(image.width == 4)
        #expect(image.height == 3)
        #expect(image.colorSpace?.name == CGColorSpace.adobeRGB1998)
    }

    @Test func previewJPEGFromWorkingSpaceIsValid() throws {
        let data = try ImageCoding.jpegDataFromWorkingSpace(.stub(width: 8, height: 8), quality: 0.9)
        #expect(data.count > 16)
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0xD8)
    }
}
