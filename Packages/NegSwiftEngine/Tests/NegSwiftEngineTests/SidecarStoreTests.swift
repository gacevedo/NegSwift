import Foundation
import Testing
@testable import NegSwiftEngine

struct SidecarStoreTests {
    @Test func loadWithoutSidecarReturnsShippedDefaults() throws {
        let frame = try writeTempTIFF()
        defer { try? FileManager.default.removeItem(at: frame) }
        let loaded = try SidecarStore.load(path: frame.path)
        #expect(loaded.hasSidecar == false)
        #expect(loaded.config["process_mode"] as? String == "Color Negative")
        #expect((loaded.config["grade"] as? NSNumber)?.doubleValue == 100)
        #expect(loaded.config["auto_density_uses_crop"] as? Bool == true)
        #expect(loaded.config["crop_from_auto"] as? Bool == true)
    }

    @Test func saveRoundTripMergesAndKeepsUnsetFields() throws {
        let frame = try writeTempTIFF()
        defer { removeFrameAndSidecar(frame) }
        let sidecar = try SidecarStore.save(
            path: frame.path,
            overrides: ["density": 1.25, "wb_cyan": 0.1, "auto_exposure": false]
        )
        #expect(URL(fileURLWithPath: sidecar).pathExtension == "negpy")
        #expect(FileManager.default.fileExists(atPath: sidecar))

        let loaded = try SidecarStore.load(path: frame.path)
        #expect(loaded.hasSidecar)
        #expect((loaded.config["density"] as? NSNumber)?.doubleValue == 1.25)
        #expect((loaded.config["wb_cyan"] as? NSNumber)?.doubleValue == 0.1)
        #expect(loaded.config["auto_exposure"] as? Bool == false)
        #expect((loaded.config["grade"] as? NSNumber)?.doubleValue == 100)
        #expect((loaded.config["analysis_buffer"] as? NSNumber)?.doubleValue == 0.05)
    }

    @Test func savePreservesHiddenAndUnknownKeys() throws {
        let frame = try writeTempTIFF()
        defer { removeFrameAndSidecar(frame) }
        _ = try SidecarStore.writeRaw(
            forScanPath: frame.path,
            payload: [
                "density": 1.0,
                "clahe_strength": 0.4,
                "selenium_strength": 0.2,
                "scratch_lines": [[[0.1, 0.2], [0.3, 0.4]]],
                "desktop_only_note": "keep-me",
            ]
        )
        _ = try SidecarStore.save(path: frame.path, overrides: ["density": 1.3])
        let loaded = try SidecarStore.load(path: frame.path)
        #expect((loaded.config["density"] as? NSNumber)?.doubleValue == 1.3)
        #expect((loaded.config["clahe_strength"] as? NSNumber)?.doubleValue == 0.4)
        #expect((loaded.config["selenium_strength"] as? NSNumber)?.doubleValue == 0.2)
        #expect(loaded.config["desktop_only_note"] as? String == "keep-me")
    }

    @Test func resetRemovesSidecarThenLoadDefaults() throws {
        let frame = try writeTempTIFF()
        defer { removeFrameAndSidecar(frame) }
        _ = try SidecarStore.save(path: frame.path, overrides: ["density": 1.5])
        #expect(try SidecarStore.reset(path: frame.path))
        #expect(try SidecarStore.reset(path: frame.path) == false)
        let loaded = try SidecarStore.load(path: frame.path)
        #expect(loaded.hasSidecar == false)
        #expect((loaded.config["density"] as? NSNumber)?.doubleValue == 1)
    }

    @Test func migrateLegacyKeysOnSave() throws {
        let frame = try writeTempTIFF()
        defer { removeFrameAndSidecar(frame) }
        _ = try SidecarStore.save(
            path: frame.path,
            overrides: ["manual_crop_rect": [0.2, 0.2, 0.8, 0.8], "grade": 2.5]
        )
        let loaded = try SidecarStore.load(path: frame.path)
        let rect = (loaded.config["crop_rect"] as? [NSNumber])?.map(\.doubleValue)
        #expect(rect == [0.2, 0.2, 0.8, 0.8])
        #expect(loaded.config["manual_crop_rect"] == nil)
        #expect((loaded.config["grade"] as? NSNumber)?.doubleValue == 100)
    }
}

private func writeTempTIFF() throws -> URL {
    let samples = [UInt16](repeating: 20_000, count: 8 * 8 * 3)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s7-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: 8, height: 8, samples: samples, to: url)
    return url
}

private func removeFrameAndSidecar(_ frame: URL) {
    try? FileManager.default.removeItem(at: frame)
    try? FileManager.default.removeItem(at: SidecarStore.url(forScanPath: frame.path))
}
