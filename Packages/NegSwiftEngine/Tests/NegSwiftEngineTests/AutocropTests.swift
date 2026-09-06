import Foundation
import Testing
@testable import NegSwiftEngine

/// Ports of NegPy `test_autocrop_resolution.py` plus the S11 detect-once gate.
struct AutocropTests {
    @Test func detectionKeyIgnoresOffsetOnly() {
        var base = PrintConfig.s8Pin
        base.cropFromAuto = true
        var offset = base
        offset.autocropOffset = 40
        #expect(Autocrop.detectionKey(offset) == Autocrop.detectionKey(base))
        var ratio = base
        ratio.autocropRatio = "5:4"
        #expect(Autocrop.detectionKey(ratio) != Autocrop.detectionKey(base))
    }

    @Test func resolveReturnsNilOnDegenerateBuffer() {
        let tiny = LinearRGBBuffer.stub(width: 1, height: 1, gray: 0.2)
        #expect(Autocrop.resolveRect(tiny, config: PrintConfig()) == nil)
    }

    @Test func resolvingIsIdempotent() {
        let image = frameImage(height: 1200, width: 1800)
        let armed = armedConfig()
        let once = Autocrop.resolveArmed(image, config: armed)
        #expect(once.resolved != nil)
        let twice = Autocrop.resolveArmed(image, config: once.config)
        #expect(twice.resolved == nil)
        #expect(twice.config.cropRect == once.config.cropRect)
        #expect(twice.config.cropDetectKey == once.config.cropDetectKey)
    }

    @Test func resolvedRectExcludesCropOffset() {
        let image = frameImage(height: 1200, width: 1800)
        let plain = Autocrop.resolveArmed(image, config: armedConfig())
        var offsetCfg = armedConfig()
        offsetCfg.autocropOffset = 25
        let offset = Autocrop.resolveArmed(image, config: offsetCfg)
        #expect(plain.resolved?.rect == offset.resolved?.rect)
    }

    @Test func offsetChangeKeepsTheDetectedRect() {
        let image = frameImage(height: 1200, width: 1800)
        let resolved = Autocrop.resolveArmed(image, config: armedConfig())
        var moved = resolved.config
        moved.autocropOffset = 12
        let again = Autocrop.resolveArmed(image, config: moved)
        #expect(again.resolved == nil)
    }

    @Test func detectionInputsRearmTheCrop() {
        let image = frameImage(height: 1200, width: 1800)
        let resolved = Autocrop.resolveArmed(image, config: armedConfig())
        #expect(resolved.resolved != nil)

        func rearmed(_ mutate: (inout PrintConfig) -> Void) -> Bool {
            var stale = resolved.config
            mutate(&stale)
            return Autocrop.resolveArmed(image, config: stale).resolved != nil
        }

        #expect(rearmed { $0.autocropRatio = "5:4" })
        #expect(rearmed { $0.autocropMode = Autocrop.filmMode })
        #expect(rearmed { $0.autocropRebateTrim = 0.5 })
        #expect(rearmed { $0.rotation = 1 })
        #expect(rearmed { $0.flipHorizontal = true })
        #expect(rearmed { $0.fineRotation = 2 })
    }

    @Test func manualRectIsNeverResolvedOver() {
        let image = frameImage(height: 1200, width: 1800)
        var manual = PrintConfig()
        manual.cropRect = NormalizedCropRect(x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8)
        manual.cropFromAuto = false
        let kept = Autocrop.resolveArmed(image, config: manual)
        #expect(kept.resolved == nil)
        #expect(kept.config.cropRect == manual.cropRect)
        #expect(Autocrop.hasManualCrop(kept.config))
    }

    @Test func holderFixtureDetectsAnInsetRect() {
        let image = frameImage(height: 1200, width: 1800)
        let rect = Autocrop.resolveRect(image, config: armedConfig())
        #expect(rect != nil)
        guard let rect else { return }
        #expect(rect.x1 > 0.04)
        #expect(rect.y1 > 0.04)
        #expect(rect.x2 < 0.96)
        #expect(rect.y2 < 0.96)
        #expect(rect.x2 - rect.x1 > 0.5)
        #expect(rect.y2 - rect.y1 > 0.5)
    }

    @Test func darkHolderFixtureDetectsBrightInterior() {
        let image = darkHolderImage(height: 120, width: 160)
        let rect = Autocrop.resolveRect(image, config: armedConfig())
        #expect(rect != nil)
        guard let rect else { return }
        #expect(rect.x1 > 0.05)
        #expect(rect.y1 > 0.05)
        #expect(rect.x2 < 0.95)
        #expect(rect.y2 < 0.95)
    }

    @Test func secondRenderWithNoEditDoesNotChangeRect() throws {
        let url = try writeFrameTIFF(width: 180, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        var config = PrintConfig.s8Pin
        config.cropFromAuto = true
        config.autoCropEnabled = true
        let first = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: config
        )
        #expect(first.resolvedAutocrop != nil)
        guard let resolved = first.resolvedAutocrop else { return }
        var frozen = config
        frozen.cropRect = resolved.rect
        frozen.cropDetectKey = resolved.key
        frozen.cropFromAuto = true
        let second = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: frozen
        )
        #expect(second.resolvedAutocrop == nil)
        #expect(second.cropRect == resolved.rect)
        #expect(second.buffer.width == first.buffer.width)
        #expect(second.buffer.height == first.buffer.height)
    }

    @Test func previewAndExportShareTheFrozenRect() throws {
        let url = try writeFrameTIFF(width: 240, height: 160)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = NativePipeline()
        var armed = PrintConfig.s8Pin
        armed.cropFromAuto = true
        armed.autoCropEnabled = true
        let preview = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative,
            config: armed
        )
        #expect(preview.resolvedAutocrop != nil)
        guard let resolved = preview.resolvedAutocrop else { return }
        var frozen = armed
        frozen.cropRect = resolved.rect
        frozen.cropDetectKey = resolved.key
        let export = try pipeline.renderPrintDetailed(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: frozen
        )
        #expect(export.resolvedAutocrop == nil)
        #expect(export.cropRect == resolved.rect)
        #expect(export.buffer.width < 240 || export.buffer.height < 160)
    }

    @Test func protocolRenderReportsThenFreezes() throws {
        let url = try writeFrameTIFF(width: 160, height: 120)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: SidecarStore.url(forScanPath: url.path))
        }
        let server = ProtocolServer()
        let first = server.handleMessage(
            """
            {"id":"ac-1","method":"render","params":{"path":"\(url.path)","prefer_gpu":false,"config":{"crop_from_auto":true,"auto_crop_enabled":true}}}
            """
        )
        #expect(first["ok"] as? Bool == true)
        let metrics = (first["result"] as? [String: Any])?["metrics"] as? [String: Any]
        let rect = (metrics?["autocrop_resolved_rect"] as? [NSNumber])?.map(\.doubleValue)
            ?? (metrics?["autocrop_resolved_rect"] as? [Double])
        let key = metrics?["autocrop_resolved_key"] as? String
        #expect(rect?.count == 4)
        #expect(key?.isEmpty == false)
        guard let rect, let key else { return }

        let second = server.handleMessage(
            """
            {"id":"ac-2","method":"render","params":{"path":"\(url.path)","prefer_gpu":false,"config":{"crop_from_auto":true,"crop_rect":[\(rect[0]),\(rect[1]),\(rect[2]),\(rect[3])],"crop_detect_key":"\(key)"}}}
            """
        )
        #expect(second["ok"] as? Bool == true)
        let again = (second["result"] as? [String: Any])?["metrics"] as? [String: Any]
        #expect(again?["autocrop_resolved_rect"] == nil)
    }

    @Test func openSuggestsCropWhenArmed() throws {
        let url = try writeFrameTIFF(width: 160, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }
        let server = ProtocolServer()
        let msg = server.handleMessage(
            """
            {"id":"open-ac","method":"open","params":{"path":"\(url.path)","config":{"crop_from_auto":true}}}
            """
        )
        let result = msg["result"] as? [String: Any]
        let rect = (result?["suggested_crop_rect"] as? [NSNumber])?.map(\.doubleValue)
            ?? (result?["suggested_crop_rect"] as? [Double])
        #expect(rect?.count == 4)
        #expect((result?["crop_detect_key"] as? String)?.isEmpty == false)
    }
}

private func armedConfig() -> PrintConfig {
    var config = PrintConfig()
    config.cropFromAuto = true
    config.autoCropEnabled = true
    config.autocropRatio = Autocrop.defaultRatio
    return config
}

/// Bright bed with a dark exposed frame — NegPy `_frame_image`.
private func frameImage(height: Int, width: Int) -> LinearRGBBuffer {
    var pixels = [Float](repeating: 1, count: width * height * 3)
    let y1 = Int((0.12 * Double(height)).rounded())
    let y2 = Int((0.88 * Double(height)).rounded())
    let x1 = Int((0.10 * Double(width)).rounded())
    let x2 = Int((0.90 * Double(width)).rounded())
    for y in y1..<y2 {
        for x in x1..<x2 {
            let i = (y * width + x) * 3
            pixels[i] = 0.05
            pixels[i + 1] = 0.05
            pixels[i + 2] = 0.05
        }
    }
    return LinearRGBBuffer(width: width, height: height, pixels: pixels)
}

private func darkHolderImage(height: Int, width: Int) -> LinearRGBBuffer {
    var pixels = [Float](repeating: 2000.0 / 65535.0, count: width * height * 3)
    let y1 = Int((20.0 / 120.0 * Double(height)).rounded())
    let y2 = Int((100.0 / 120.0 * Double(height)).rounded())
    let x1 = Int((30.0 / 160.0 * Double(width)).rounded())
    let x2 = Int((130.0 / 160.0 * Double(width)).rounded())
    let interior: Float = 30000.0 / 65535.0
    for y in y1..<y2 {
        for x in x1..<x2 {
            let i = (y * width + x) * 3
            pixels[i] = interior
            pixels[i + 1] = interior
            pixels[i + 2] = interior
        }
    }
    return LinearRGBBuffer(width: width, height: height, pixels: pixels)
}

private func writeFrameTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 65535, count: width * height * 3)
    let y1 = Int((0.12 * Double(height)).rounded())
    let y2 = Int((0.88 * Double(height)).rounded())
    let x1 = Int((0.10 * Double(width)).rounded())
    let x2 = Int((0.90 * Double(width)).rounded())
    for y in y1..<y2 {
        for x in x1..<x2 {
            let i = (y * width + x) * 3
            samples[i] = 3277
            samples[i + 1] = 3277
            samples[i + 2] = 3277
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s11-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
