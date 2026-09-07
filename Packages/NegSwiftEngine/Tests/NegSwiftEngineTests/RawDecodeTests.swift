import Foundation
import Testing
@testable import NegSwiftEngine

@Suite(.serialized)
struct RawDecodeTests {
    @Test func scanFormatListsNegPyCameraRawNotJXL() {
        #expect(ScanFormat.isCameraRaw("roll/frame.NEF"))
        #expect(ScanFormat.isCameraRaw("roll/frame.arw"))
        #expect(ScanFormat.isCameraRaw("roll/frame.cr2"))
        #expect(ScanFormat.isCameraRaw("roll/frame.cr3"))
        #expect(ScanFormat.isCameraRaw("roll/frame.dng"))
        #expect(ScanFormat.isCameraRaw("roll/frame.raf"))
        #expect(ScanFormat.isCameraRaw("roll/frame.rw2"))
        #expect(ScanFormat.isSupportedScan("roll/scan.TIFF"))
        #expect(ScanFormat.isRaster("roll/scan.jpg"))
        #expect(!ScanFormat.isCameraRaw("roll/scan.tif"))
        #expect(!ScanFormat.isSupportedScan("roll/frame.jxl"))
        #expect(!ScanFormat.isSupportedScan("roll/notes.txt"))
    }

    @Test func infoReportsLibRawFlag() {
        let info = NativePipeline().infoJSON()
        #expect(info["libraw"] as? Bool == RawDecode.isAvailable)
        #expect(info["negpy_version"] as? String == "s14-raw")
    }

    @Test func missingRawThrows() {
        #expect(throws: LinearDecodeError.self) {
            _ = try LinearDecode.decode(path: "/no/such/scan.nef")
        }
    }

    @Test func rasterPathUnchangedOnSampleShape() throws {
        let samples = [UInt16](repeating: 40_000, count: 8 * 6 * 3)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s14-raster-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeRGB16(width: 8, height: 6, samples: samples, to: url)
        let buffer = try LinearDecode.decode(url: url)
        #expect(buffer.width == 8)
        #expect(buffer.height == 6)
        #expect(abs(buffer.pixels[0] - 40_000 / 65535) < 1.5 / 65535)
    }

    @Test(.enabled(if: RawDecode.isAvailable))
    func linearRawDNGDecodesWhenLibRawLinked() throws {
        // LibRaw rejects DNG smaller than 22 px on either edge.
        let width = 32
        let height = 32
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s14-\(UUID().uuidString).dng")
        defer { try? FileManager.default.removeItem(at: url) }
        try UncompressedTIFF.writeLinearRawDNG16(width: width, height: height, samples: samples, to: url)

        #expect(ScanFormat.isCameraRaw(url.path))
        let probed = NativePipeline().probeSource(at: url.path)
        #expect(probed?.width == width)
        #expect(probed?.height == height)

        let buffer = try LinearDecode.decode(url: url)
        #expect(buffer.width == width)
        #expect(buffer.height == height)
        #expect(abs(buffer.pixels[0] - 40_000 / 65535) < 2 / 65535)
        #expect(abs(buffer.pixels[1] - 22_000 / 65535) < 2 / 65535)
        #expect(abs(buffer.pixels[2] - 10_000 / 65535) < 2 / 65535)
        let down = try LinearDecode.decode(url: url, maxLongEdge: 16)
        #expect(max(down.width, down.height) <= 16)

        let full = try RawDecode.decodeDetailed(url: url, halfSize: false)
        #expect(!full.usedHalfSize)
        #expect(full.demosaic == .ahd)
        let half = try RawDecode.decodeDetailed(url: url, halfSize: true)
        #expect(!half.isXTrans)
        #expect(half.demosaic == .linear)
        if half.usedHalfSize {
            #expect(max(half.buffer.width, half.buffer.height) <= max(full.buffer.width, full.buffer.height))
        }
        #expect(abs(half.buffer.pixels[0] - 40_000 / 65535) < 4 / 65535)
    }

    @Test(.enabled(if: RawDecode.isAvailable))
    func probeThumbAndPreviewShareOneLibRawHandle() throws {
        let url = try Self.writeLinearDNG()
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        _ = RawDecode.probe(url: url)
        _ = RawDecode.extractThumb(url: url)
        let preview = try RawDecode.decodeDetailed(url: url, halfSize: true)
        #expect(RawDecode.openCount == 1)
        #expect(RawDecode.unpackCount == 1)
        #expect(preview.demosaic == .linear)
        let exported = try RawDecode.decodeDetailed(url: url, halfSize: false)
        #expect(exported.demosaic == .ahd)
        #expect(RawDecode.openCount == 1)
        #expect(RawDecode.unpackCount == 1)
    }

    @Test(.enabled(if: RawDecode.isAvailable && RawDecodeTests.localCameraRaw() != nil))
    func halfSizeBinsLocalCameraRaw() throws {
        guard let url = Self.localCameraRaw() else { return }
        NativePipeline.resetWorkingSets()
        let full = try RawDecode.decodeDetailed(url: url, halfSize: false)
        let half = try RawDecode.decodeDetailed(url: url, halfSize: true)
        if half.isXTrans {
            #expect(!half.usedHalfSize)
            #expect(half.demosaic == .ppg)
            #expect(full.demosaic == .ahd)
        } else {
            #expect(half.usedHalfSize)
            #expect(half.demosaic == .linear)
            #expect(full.demosaic == .ahd)
            let fullLong = max(full.buffer.width, full.buffer.height)
            let halfLong = max(half.buffer.width, half.buffer.height)
            #expect(halfLong * 2 <= fullLong + 4)
            #expect(halfLong * 2 >= fullLong - 8)
        }
        let thumb = try LinearDecode.decode(url: url, maxLongEdge: 256)
        #expect(max(thumb.width, thumb.height) <= 256)
    }

    @Test(.enabled(if: RawDecode.isAvailable && RawDecodeTests.localXTrans() != nil))
    func xTransPreviewUsesPPGNotAHD() throws {
        guard let url = Self.localXTrans() else { return }
        NativePipeline.resetWorkingSets()
        _ = RawDecode.probe(url: url)
        _ = RawDecode.extractThumb(url: url)
        let preview = try RawDecode.decodeDetailed(url: url, halfSize: true)
        #expect(preview.isXTrans)
        #expect(!preview.usedHalfSize)
        #expect(preview.demosaic == .ppg)
        #expect(RawDecode.openCount == 1)
        #expect(RawDecode.unpackCount == 1)
        let exported = try RawDecode.decodeDetailed(url: url, halfSize: false)
        #expect(exported.demosaic == .ahd)
        #expect(RawDecode.openCount == 1)
    }

    @Test(.enabled(if: !RawDecode.isAvailable))
    func rawUnavailableWhenStubbed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s14-stub-\(UUID().uuidString).dng")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not-a-raw".utf8).write(to: url)
        do {
            _ = try LinearDecode.decode(url: url)
            Issue.record("expected rawUnavailable")
        } catch LinearDecodeError.rawUnavailable {
            #expect(Bool(true))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    static func localCameraRaw() -> URL? {
        let keys = ["NEGSWIFT_S14_NEF", "NEGSWIFT_S14_ARW", "NEGSWIFT_S14_RAF", "NEGSWIFT_S14_RAW"]
        for key in keys {
            guard let path = ProcessInfo.processInfo.environment[key], !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func localXTrans() -> URL? {
        if let path = ProcessInfo.processInfo.environment["NEGSWIFT_S14_RAF"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let url = localCameraRaw(), url.pathExtension.lowercased() == "raf" {
            return url
        }
        let fallbacks = [
            "/Users/gacevedo/Downloads/sample-raw-scans/_DSF9243.RAF",
            "/Users/gacevedo/Downloads/sample-raw-scans/_DSF8951.RAF",
            "/Users/gacevedo/Downloads/sample-raw-scans/_DSF8434.RAF",
        ]
        for path in fallbacks where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func writeLinearDNG(width: Int = 32, height: Int = 32) throws -> URL {
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            samples[i * 3] = 40_000
            samples[i * 3 + 1] = 22_000
            samples[i * 3 + 2] = 10_000
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s13i-\(UUID().uuidString).dng")
        try UncompressedTIFF.writeLinearRawDNG16(width: width, height: height, samples: samples, to: url)
        return url
    }
}
