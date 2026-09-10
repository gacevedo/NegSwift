//
//  EngineSessionThumbnailTests.swift
//  NegSwiftTests
//

import AppKit
import CoreGraphics
import Testing
@testable import NegSwift

@Suite(.serialized)
struct EngineSessionThumbnailTests {
    @Test @MainActor func stripThumbnailsUseNativePreviewWhenEncodedImageIsMissing() async {
        let session = EngineSession.preview
        session.setCurrentPathForTests(session.frames[0].path)
        session.setPreviewSettledForTests(true)
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

    @Test @MainActor func stripFillsEveryFrameWithoutSkippingTheThird() async {
        let session = EngineSession.preview
        let frames = (0..<4).map { index in
            ScanFrame(
                id: UUID(),
                url: URL(fileURLWithPath: "/preview/frame-\(index).tif"),
                path: "/preview/frame-\(index).tif",
                name: "frame-\(index).tif"
            )
        }
        session.setFramesForTests(frames)
        session.setFilmStripSelectionForTests(primary: frames[0].id, ids: [frames[0].id])
        session.setCurrentPathForTests(frames[0].path)
        session.setPreviewSettledForTests(true)
        session.setPreviewImageForTests(nil)
        for frame in frames {
            session.setFrameEditForTests(path: frame.path, edit: FrameEditState())
            session.setHasSidecarForTests(path: frame.path)
        }

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

        #expect(session.frames.map(\.thumbnail).allSatisfy { $0 != nil })
        session.clearRenderTestHandlerForTests()
    }

    @Test @MainActor func leavingAFrameKeepsPreviewDerivedThumbnail() async {
        let session = EngineSession.preview
        let frameA = session.frames[0]
        let frameB = session.frames[1]
        session.setFrameEditForTests(path: frameA.path, edit: FrameEditState())
        session.setFrameEditForTests(path: frameB.path, edit: FrameEditState())
        session.setHasSidecarForTests(path: frameA.path)
        session.setHasSidecarForTests(path: frameB.path)

        let preview = NSImage(
            cgImage: Self.makeCGImage(red: 20, green: 180, blue: 40),
            size: NSSize(width: 160, height: 120)
        )
        session.storePreviewMemoForTests(
            path: frameA.path,
            image: preview,
            pixelSize: CGSize(width: 160, height: 120)
        )
        session.setFilmStripSelectionForTests(primary: frameB.id, ids: [frameB.id])
        session.setCurrentPathForTests(frameB.path)
        session.setPreviewImageForTests(nil)

        session.setRenderTestHandlerForTests { _ in
            RenderResult(
                width: 8,
                height: 6,
                previewFormat: "cgimage",
                pngBase64: nil,
                jpegBase64: nil,
                metrics: nil,
                nativePreview: NativePreview(cgImage: Self.makeCGImage(red: 200, green: 40, blue: 40))
            )
        }

        await session.refreshThumbnailForTests(path: frameA.path)

        #expect(session.renderTestRecordsForTests.filter(\.stripThumbnail).isEmpty)
        #expect(session.frames[0].thumbnail != nil)
        #expect(session.frames[0].thumbnail?.size.width == 256)
        #expect(session.frames[0].thumbnail?.size.height == 192)
        session.clearRenderTestHandlerForTests()
    }

    @Test @MainActor func refreshWithoutMemoDoesNotReplaceExistingThumbnail() async {
        let session = EngineSession.preview
        let frameA = session.frames[0]
        let existing = NSImage(
            cgImage: Self.makeCGImage(red: 20, green: 180, blue: 40),
            size: NSSize(width: 64, height: 48)
        )
        session.setFramesForTests([
            ScanFrame(
                id: frameA.id,
                url: frameA.url,
                path: frameA.path,
                name: frameA.name,
                thumbnail: existing,
                hasProcessedThumbnail: true
            ),
            session.frames[1],
        ])
        session.setFrameEditForTests(path: frameA.path, edit: FrameEditState())
        session.setHasSidecarForTests(path: frameA.path)
        session.setFilmStripSelectionForTests(primary: session.frames[1].id, ids: [session.frames[1].id])
        session.setCurrentPathForTests(session.frames[1].path)

        session.setRenderTestHandlerForTests { _ in
            RenderResult(
                width: 8,
                height: 6,
                previewFormat: "cgimage",
                pngBase64: nil,
                jpegBase64: nil,
                metrics: nil,
                nativePreview: NativePreview(cgImage: Self.makeCGImage(red: 200, green: 40, blue: 40))
            )
        }

        await session.refreshThumbnailForTests(path: frameA.path)

        #expect(session.renderTestRecordsForTests.filter(\.stripThumbnail).isEmpty)
        #expect(session.frames[0].thumbnail === existing)
        session.clearRenderTestHandlerForTests()
    }

    private static func makeCGImage() -> CGImage {
        makeCGImage(red: 200, green: 40, blue: 40)
    }

    private static func makeCGImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        var pixel: [UInt8] = [red, green, blue, 255]
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
