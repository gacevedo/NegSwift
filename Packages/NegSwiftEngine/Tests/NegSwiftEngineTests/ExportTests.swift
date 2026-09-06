import Foundation
import Testing
@testable import NegSwiftEngine

struct ExportTests {
    @Test func namingUsesStemThenNumericSuffix() throws {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-name-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        let source = dest.appendingPathComponent("scan.tif").path
        let first = try ExportNaming.outputURL(
            sourcePath: source,
            destDir: dest.path,
            format: .jpeg,
            overwrite: false
        )
        #expect(first.lastPathComponent == "scan.jpg")
        try Data([0xFF, 0xD8]).write(to: first)
        let second = try ExportNaming.outputURL(
            sourcePath: source,
            destDir: dest.path,
            format: .jpeg,
            overwrite: false
        )
        #expect(second.lastPathComponent == "scan_2.jpg")
        let over = try ExportNaming.outputURL(
            sourcePath: source,
            destDir: dest.path,
            format: .jpeg,
            overwrite: true
        )
        #expect(over.lastPathComponent == "scan.jpg")
    }

    @Test func parseRejectsUnknownFormat() {
        #expect(throws: ProtocolFailure.self) {
            _ = try NativeExportSettings.parse(["export_fmt": "JXL"])
        }
    }

    @Test func exportJPEGAndTIFFWriteOpenableFiles() throws {
        let frame = try writeProtocolTIFF()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-exp-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        let jpeg = try NativePipeline().export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: .s8Pin,
            settings: NativeExportSettings(format: .jpeg, jpegQuality: 90)
        )
        #expect(jpeg.url.pathExtension.lowercased() == "jpg")
        #expect(jpeg.width == 8)
        #expect(jpeg.height == 8)
        #expect(jpeg.format == "JPEG")
        #expect(FileManager.default.fileExists(atPath: jpeg.url.path))
        let probed = ImageCoding.probeDimensions(at: jpeg.url)
        #expect(probed?.width == 8)
        #expect(probed?.height == 8)

        let tiff = try NativePipeline().export(
            path: frame.path,
            destDir: dest.path,
            processMode: .colorNegative,
            config: .s8Pin,
            settings: NativeExportSettings(format: .tiff)
        )
        #expect(tiff.url.pathExtension.lowercased() == "tiff")
        #expect(tiff.format == "TIFF")
        #expect(ImageCoding.probeDimensions(at: tiff.url)?.width == 8)
    }

    @Test func exportAppliesStoredCrop() throws {
        let frame = try writeProtocolTIFF()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-crop-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        var cropped = PrintConfig.s8Pin
        cropped.cropRect = NormalizedCropRect(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        cropped.autoDensityUsesCrop = false
        let full = try NativePipeline().export(
            path: frame.path,
            destDir: dest.appendingPathComponent("full").path,
            processMode: .colorNegative,
            config: .s8Pin
        )
        let cut = try NativePipeline().export(
            path: frame.path,
            destDir: dest.appendingPathComponent("crop").path,
            processMode: .colorNegative,
            config: cropped
        )
        #expect(cut.width * cut.height < full.width * full.height)
    }

    @Test func protocolExportMatchesPythonContract() throws {
        let frame = try writeProtocolTIFF()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s9-proto-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: dest)
        }
        let server = ProtocolServer()
        let jpegLine = """
        {"id":"export-jpeg","method":"export","params":{"path":"\(frame.path)","dest_dir":"\(dest.path)","prefer_gpu":false,"config":{"crop_from_auto":false,"auto_crop_enabled":false},"export":{"export_fmt":"JPEG","export_color_space":"sRGB","export_resolution_mode":"original","jpeg_quality":90}}}
        """
        let jpeg = server.handleMessage(jpegLine)
        #expect(jpeg["ok"] as? Bool == true, "\(jpeg)")
        let result = jpeg["result"] as? [String: Any]
        let outPath = result?["output_path"] as? String
        #expect(outPath?.hasSuffix(".jpg") == true)
        #expect((result?["width"] as? NSNumber)?.intValue == 8)
        #expect((result?["format"] as? String) == "JPEG")

        let again = server.handleMessage(jpegLine)
        let second = (again["result"] as? [String: Any])?["output_path"] as? String
        #expect(second?.hasSuffix("scan_2.jpg") == true || second?.contains("_2.jpg") == true)

        let missing = server.handleMessage(
            #"{"id":"export-missing","method":"export","params":{"path":"/no/such/file.tif","dest_dir":"\#(dest.path)","prefer_gpu":false}}"#
        )
        #expect((missing["error"] as? [String: Any])?["code"] as? String == "NOT_FOUND")
    }
}
