import Foundation
import Testing
@testable import NegSwiftEngine

/// Regression for Canon CR2 where LibRaw `sizes.flip` disagrees with EXIF Orientation.
/// Run locally: `NEGSWIFT_S14_RAW='/path/to/file.CR2' swift test --filter CR2ExportGeometryProbeTests`
struct CR2ExportGeometryProbeTests {
    @Test(.enabled(if: RawDecode.isAvailable && RawDecodeTests.localCameraRaw()?.pathExtension.lowercased() == "cr2"))
    func previewAndExportMatchGeometry() throws {
        let url = try #require(RawDecodeTests.localCameraRaw())
        let path = url.path
        let pipeline = NativePipeline(pixelBackend: .cpu)

        func sizes(rotation: Int, crop: NormalizedCropRect?) throws -> (preview: String, export: String) {
            var cfg = PrintConfig.s8Pin
            cfg.rotation = rotation
            cfg.applyPixelCrop = true
            cfg.cropRect = crop
            let preview = try pipeline.renderPrint(path: path, longEdgePx: 1600, config: cfg)
            let export = try pipeline.renderPrint(path: path, longEdgePx: nil, config: cfg)
            return ("\(preview.width)x\(preview.height)", "\(export.width)x\(export.height)")
        }

        let base = try sizes(rotation: 0, crop: nil)
        let rot1 = try sizes(rotation: 1, crop: nil)
        #expect(rot1.preview != base.preview, "rotation should change preview dimensions")

        let crop = NormalizedCropRect(x1: 0.15, y1: 0.15, x2: 0.85, y2: 0.85)
        let rot1Crop = try sizes(rotation: 1, crop: crop)
        let previewAspect = Self.aspect(from: rot1Crop.preview)
        let exportAspect = Self.aspect(from: rot1Crop.export)
        #expect(abs(previewAspect - exportAspect) < 0.02, "preview/export aspect mismatch")
    }

    private static func aspect(from size: String) -> Double {
        let parts = size.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 0 }
        return parts[0] / parts[1]
    }
}
