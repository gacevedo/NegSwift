import Foundation
import Testing
@testable import NegSwiftEngine

struct RawOrientationTests {
    @Test(.enabled(if: RawDecode.isAvailable && RawDecodeTests.localCameraRaw() != nil))
    func decodeUsesExifOrientationNotLibRawFlip() throws {
        let url = try #require(RawDecodeTests.localCameraRaw())
        let exif = ImageCoding.exifOrientation(at: url)
        let half = try RawDecode.decodeDetailed(url: url, halfSize: true)
        let full = try RawDecode.decodeDetailed(url: url, halfSize: false)
        let halfAspect = Double(half.buffer.width) / Double(half.buffer.height)
        let fullAspect = Double(full.buffer.width) / Double(full.buffer.height)
        if exif == 1 {
            #expect(abs(halfAspect - fullAspect) < 0.02)
        } else {
            #expect(half.buffer.width > 0)
            #expect(full.buffer.width > 0)
        }
    }
}
