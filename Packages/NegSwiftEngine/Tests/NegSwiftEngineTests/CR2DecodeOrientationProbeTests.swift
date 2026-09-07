import Foundation
import Testing
@testable import NegSwiftEngine

struct CR2DecodeOrientationProbeTests {
    @Test(.enabled(if: RawDecode.isAvailable && RawDecodeTests.localCameraRaw()?.pathExtension.lowercased() == "cr2"))
    func halfAndFullDecodeShareAspect() throws {
        let url = try #require(RawDecodeTests.localCameraRaw())
        let half = try RawDecode.decodeDetailed(url: url, halfSize: true)
        let full = try RawDecode.decodeDetailed(url: url, halfSize: false)
        let halfAspect = Double(half.buffer.width) / Double(half.buffer.height)
        let fullAspect = Double(full.buffer.width) / Double(full.buffer.height)
        #expect(abs(halfAspect - fullAspect) < 0.02)
    }
}
