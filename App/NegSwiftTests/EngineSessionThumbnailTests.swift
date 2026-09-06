//
//  EngineSessionThumbnailTests.swift
//  NegSwiftTests
//

import AppKit
import CoreGraphics
import Testing
@testable import NegSwift

struct EngineSessionThumbnailTests {
    @Test @MainActor func stripThumbnailsUseNativePreviewWhenEncodedImageIsMissing() async {
        let session = EngineSession.preview
        session.setCurrentPathForTests(session.frames[0].path)
        session.setPreviewImageForTests(nil)
        session.setFrameEditForTests(path: session.frames[0].path, edit: FrameEditState())
        session.setFrameEditForTests(path: session.frames[1].path, edit: FrameEditState())
        session.setHasSidecarForTests(path: session.frames[0].path)
        session.setHasSidecarForTests(path: session.frames[1].path)

        let cgImage = Self.makeCGImage()
        session.setRenderTestHandlerForTests { _ in
            RenderResult(
                width: 8,
                height: 6,
                previewFormat: "cgimage",
                pngBase64: nil,
                jpegBase64: nil,
                metrics: nil,
                nativePreview: NativePreview(cgImage: cgImage)
            )
        }

        await session.runThumbnailLoadingForTests()

        #expect(session.frames[0].thumbnail != nil)
        #expect(session.frames[1].thumbnail != nil)
        session.clearRenderTestHandlerForTests()
    }

    private static func makeCGImage() -> CGImage {
        var pixel: [UInt8] = [200, 40, 40, 255]
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
