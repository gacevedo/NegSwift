//
//  PreviewRenderMemoTests.swift
//  NegSwiftTests
//

import AppKit
import Testing
@testable import NegSwift

struct PreviewRenderMemoTests {
  @Test func storeAndRetrieveMatchingFingerprint() {
    var memo = PreviewRenderMemo(maxEntries: 4)
    let image = NSImage(size: NSSize(width: 10, height: 8))
    let size = CGSize(width: 10, height: 8)
    memo.store(path: "/a.tif", fingerprint: "key1", image: image, pixelSize: size)
    let entry = memo.get(path: "/a.tif", fingerprint: "key1")
    #expect(entry != nil)
    #expect(entry?.image === image)
    #expect(entry?.pixelSize == size)
  }

  @Test func mismatchFingerprintIsMiss() {
    var memo = PreviewRenderMemo(maxEntries: 4)
    let image = NSImage(size: NSSize(width: 10, height: 8))
    memo.store(path: "/a.tif", fingerprint: "key1", image: image, pixelSize: CGSize(width: 10, height: 8))
    #expect(memo.get(path: "/a.tif", fingerprint: "key2") == nil)
  }

  @Test func evictsOldestWhenOverBudget() {
    var memo = PreviewRenderMemo(maxEntries: 2)
    let image = NSImage(size: NSSize(width: 4, height: 4))
    let size = CGSize(width: 4, height: 4)
    memo.store(path: "/a.tif", fingerprint: "a", image: image, pixelSize: size)
    memo.store(path: "/b.tif", fingerprint: "b", image: image, pixelSize: size)
    memo.store(path: "/c.tif", fingerprint: "c", image: image, pixelSize: size)
    #expect(memo.get(path: "/a.tif", fingerprint: "a") == nil)
    #expect(memo.get(path: "/b.tif", fingerprint: "b") != nil)
    #expect(memo.get(path: "/c.tif", fingerprint: "c") != nil)
  }

  @Test func invalidateRemovesPath() {
    var memo = PreviewRenderMemo()
    let image = NSImage(size: NSSize(width: 4, height: 4))
    memo.store(path: "/a.tif", fingerprint: "a", image: image, pixelSize: CGSize(width: 4, height: 4))
    memo.invalidate(path: "/a.tif")
    #expect(memo.get(path: "/a.tif", fingerprint: "a") == nil)
  }

  @Test func fingerprintChangesWhenDensityChanges() {
    let settings = PreviewRenderSettings(longEdgePx: 1600, preferGPU: true)
  let base = FrameEditState()
    let changed = FrameEditState(density: 1.2)
    let first = PreviewMemoFingerprint.make(pipelineConfig: base, settings: settings, cropPreviewFull: false)
    let second = PreviewMemoFingerprint.make(pipelineConfig: changed, settings: settings, cropPreviewFull: false)
    #expect(first != second)
  }

  @Test func fingerprintIncludesPreviewSettings() {
    let config = FrameEditState()
    let gpu = PreviewRenderSettings(longEdgePx: 1600, preferGPU: true)
    let cpu = PreviewRenderSettings(longEdgePx: 1600, preferGPU: false)
    let a = PreviewMemoFingerprint.make(pipelineConfig: config, settings: gpu, cropPreviewFull: false)
    let b = PreviewMemoFingerprint.make(pipelineConfig: config, settings: cpu, cropPreviewFull: false)
    #expect(a != b)
  }
}
