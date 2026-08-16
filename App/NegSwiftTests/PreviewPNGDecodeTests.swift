//
//  PreviewPNGDecodeTests.swift
//  NegSwiftTests
//

import AppKit
import Foundation
import Testing
@testable import NegSwift

struct PreviewPNGDecodeTests {
    /// 2×2 red PNG — verifies off-main decode returns a usable bitmap for main-thread NSImage.
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP8z8BQz0AEYBxVSF+FABJ0" +
        "Afin5QAAAABJRU5ErkJggg=="

    @Test @MainActor func decodePreviewPNGBuildsValidMainThreadImage() async {
        let session = EngineSession(preferences: AppPreferences())
        let image = await session.decodePreviewPNGForTesting(base64: Self.tinyPNGBase64)
        #expect(image != nil)
        #expect(image?.size.width == 2)
        #expect(image?.size.height == 2)
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("NSImage missing CGImage backing")
            return
        }
        #expect(cgImage.width == 2)
        #expect(cgImage.height == 2)
    }
}
