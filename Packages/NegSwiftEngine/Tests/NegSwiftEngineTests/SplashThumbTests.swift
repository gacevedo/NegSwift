import Foundation
import Testing
@testable import NegSwiftEngine

/// S13f: embedded-preview splash and cheap strip thumbs (not a full print).
@Suite(.serialized)
struct SplashThumbTests {
    @Test func rasterOpenDoesNotInventSplash() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(NativePipeline().splashJPEG(path: url.path) == nil)
        #expect(EmbeddedPreview.splashJPEG(path: url.path) == nil)
    }

    @Test func cheapThumbIsNotAPrintPath() throws {
        let url = try writeOrangeMaskTIFF(width: 96, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let thumb = try NativePipeline().cheapThumb(
            path: url.path,
            longEdgePx: 32,
            processMode: .colorNegative
        )
        #expect(max(thumb.width, thumb.height) <= 32)
        #expect(thumb.width > 0 && thumb.height > 0)
        let stats = PipelineStats.snapshot()
        #expect(stats.print == 0)
        #expect(stats.decode == 0)
        #expect(stats.analyze == 0)
        #expect(stats.orient == 0)
    }

    @Test func cheapThumbLogNormalizeIsNotBlue() throws {
        let url = try writeOrangeMaskTIFF(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        var config = PrintConfig.s8Pin
        config.cropRect = NormalizedCropRect(x1: 0, y1: 0, x2: 1, y2: 1)
        let source = try ImageCoding.buffer(
            from: EmbeddedPreview.imageIOThumbnail(
                url: url,
                maxLongEdge: 64,
                embeddedOnly: false
            )!
        )
        let thumb = try EmbeddedPreview.cheapThumb(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: config
        )
        #expect(meanChannel(source, 0) > meanChannel(source, 2))
        let sourceRB = meanChannel(source, 0) / max(meanChannel(source, 2), 1e-6)
        let thumbRB = meanChannel(thumb, 0) / max(meanChannel(thumb, 2), 1e-6)
        #expect(thumbRB < sourceRB)
        #expect(meanChannel(thumb, 2) < meanChannel(thumb, 0) * 1.25)
    }

    @Test func cheapThumbAppliesStoredCropAndRotation() throws {
        let url = try writeOrangeMaskTIFF(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        var cropped = PrintConfig.s8Pin
        cropped.cropRect = NormalizedCropRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        let cut = try EmbeddedPreview.cheapThumb(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: cropped
        )
        var rotated = cropped
        rotated.rotation = 1
        let spun = try EmbeddedPreview.cheapThumb(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: rotated
        )
        #expect(cut.width * cut.height < 64 * 48)
        #expect(spun.width == cut.height)
        #expect(spun.height == cut.width)
    }

    @Test func cheapThumbCropsLightboxOnSmallBuffer() throws {
        let url = try writeLightboxTIFF(width: 160, height: 120)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let thumb = try EmbeddedPreview.cheapThumb(
            path: url.path,
            longEdgePx: 160,
            processMode: .colorNegative
        )
        #expect(thumb.width * thumb.height < 160 * 120 * 3 / 4)
        #expect(PipelineStats.snapshot().print == 0)
        #expect(PipelineStats.snapshot().decode == 0)
    }

    @Test func cheapThumbLeavesTransparencyReadable() throws {
        let url = try writePositiveJPEG()
        defer { try? FileManager.default.removeItem(at: url) }
        var config = PrintConfig.s8Pin
        config.cropRect = NormalizedCropRect(x1: 0, y1: 0, x2: 1, y2: 1)
        let thumb = try EmbeddedPreview.cheapThumb(
            path: url.path,
            longEdgePx: 16,
            processMode: .transparency,
            config: config
        )
        #expect(thumb.width > 0 && thumb.height > 0)
        #expect(meanChannel(thumb, 0) + meanChannel(thumb, 1) > meanChannel(thumb, 2))
    }

    @Test func protocolOpenSplashOnRasterOmitsPayload() throws {
        let url = try writeOrangeMaskTIFF(width: 40, height: 28)
        defer { try? FileManager.default.removeItem(at: url) }
        let server = ProtocolServer()
        let msg = server.handleMessage(
            #"{"id":"s13f-open","method":"open","params":{"path":"\#(url.path)","include_splash":true}}"#
        )
        let result = msg["result"] as? [String: Any]
        #expect(msg["ok"] as? Bool == true)
        #expect(result?["splash_jpeg_base64"] == nil)
        #expect(result?["width"] as? Int != nil)
    }

    @Test func protocolFastPreviewDoesNotPrint() throws {
        let url = try writeOrangeMaskTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let server = ProtocolServer()
        let msg = server.handleMessage(
            #"{"id":"s13f-thumb","method":"render","params":{"path":"\#(url.path)","long_edge_px":24,"fast_preview":true,"preview_format":"jpeg"}}"#
        )
        #expect(msg["ok"] as? Bool == true)
        let result = msg["result"] as? [String: Any]
        #expect((result?["width"] as? Int ?? 0) > 0)
        #expect(result?["jpeg_base64"] is String)
        #expect(PipelineStats.snapshot().print == 0)
        #expect(PipelineStats.snapshot().decode == 0)
    }

    @Test(.enabled(if: RawDecode.isAvailable && SplashThumbTests.localCameraRaw() != nil))
    func splashJPEGOnLocalCameraRaw() throws {
        guard let url = Self.localCameraRaw() else { return }
        NativePipeline.resetWorkingSets()
        let splash = NativePipeline().splashJPEG(path: url.path)
        #expect(splash != nil)
        guard let splash else { return }
        #expect(splash.width > 0 && splash.height > 0)
        #expect(splash.jpeg.count > 100)
        #expect(splash.jpeg.starts(with: [0xFF, 0xD8]))
        #expect(PipelineStats.snapshot().decode == 0)
        #expect(PipelineStats.snapshot().print == 0)

        let server = ProtocolServer()
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\")
        let msg = server.handleMessage(
            #"{"id":"s13f-raw","method":"open","params":{"path":"\#(escaped)","include_splash":true}}"#
        )
        let result = msg["result"] as? [String: Any]
        #expect(msg["ok"] as? Bool == true)
        #expect((result?["splash_width"] as? Int ?? 0) > 0)
        #expect(result?["splash_jpeg_base64"] is String)
    }

    @Test(.enabled(if: RawDecode.isAvailable))
    func syntheticDNGSplashDoesNotCrash() throws {
        let width = 32
        let height = 32
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13f-\(UUID().uuidString).dng")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeLinearRawDNG16(width: width, height: height, samples: samples, to: url)
        let splash = NativePipeline().splashJPEG(path: url.path)
        #expect(splash == nil || splash!.jpeg.starts(with: [0xFF, 0xD8]))
        let thumb = try NativePipeline().cheapThumb(path: url.path, longEdgePx: 16, processMode: .colorNegative)
        #expect(max(thumb.width, thumb.height) <= 16)
        #expect(PipelineStats.snapshot().print == 0)
    }

    static func localCameraRaw() -> URL? {
        RawDecodeTests.localCameraRaw()
    }
}

private func meanChannel(_ buffer: LinearRGBBuffer, _ channel: Int) -> Float {
    let count = buffer.width * buffer.height
    var sum: Float = 0
    for i in 0..<count {
        sum += buffer.pixels[i * 3 + channel]
    }
    return sum / Float(count)
}

private func writeOrangeMaskTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    let cy = Double(height - 1) / 2
    let cx = Double(width - 1) / 2
    for y in 0..<height {
        for x in 0..<width {
            let dist = pow((Double(y) - cy) / Double(height), 2) + pow((Double(x) - cx) / Double(width), 2)
            let t = 0.25 + 0.55 * dist
            let i = (y * width + x) * 3
            samples[i] = UInt16(clamping: Int((min(1, max(1e-6, 0.70 * t)) * 65535).rounded()))
            samples[i + 1] = UInt16(clamping: Int((min(1, max(1e-6, 0.38 * t)) * 65535).rounded()))
            samples[i + 2] = UInt16(clamping: Int((min(1, max(1e-6, 0.16 * t)) * 65535).rounded()))
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13f-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func writeLightboxTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 65_535, count: width * height * 3)
    let y1 = Int((0.12 * Double(height)).rounded())
    let y2 = Int((0.88 * Double(height)).rounded())
    let x1 = Int((0.10 * Double(width)).rounded())
    let x2 = Int((0.90 * Double(width)).rounded())
    for y in y1..<y2 {
        for x in x1..<x2 {
            let i = (y * width + x) * 3
            samples[i] = 45_000
            samples[i + 1] = 22_000
            samples[i + 2] = 8_000
        }
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13f-box-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func writePositiveJPEG() throws -> URL {
    var pixels = [Float](repeating: 0, count: 16 * 12 * 3)
    for i in 0..<(16 * 12) {
        pixels[i * 3] = 0.75
        pixels[i * 3 + 1] = 0.45
        pixels[i * 3 + 2] = 0.20
    }
    let buffer = LinearRGBBuffer(width: 16, height: 12, pixels: pixels)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13f-\(UUID().uuidString).jpg")
    try ImageCoding.jpegData(from: buffer, quality: 0.9).write(to: url)
    return url
}
