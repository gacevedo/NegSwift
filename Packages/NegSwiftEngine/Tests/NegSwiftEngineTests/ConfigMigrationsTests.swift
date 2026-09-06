import Foundation
import Testing
@testable import NegSwiftEngine

struct ConfigMigrationsTests {
    @Test func renamesManualCropAndAutoCrop() {
        var data: [String: Any] = [
            "manual_crop_rect": [0.1, 0.2, 0.8, 0.9],
            "auto_crop_enabled": true,
            "true_black": true,
            "cast_removal": true,
            "grade": 2.5,
        ]
        ConfigMigrations.migrateFlatConfig(&data)
        ConfigMigrations.applyConstructionCoercions(&data)
        #expect(data["crop_rect"] as? [Double] == [0.1, 0.2, 0.8, 0.9] || (data["crop_rect"] as? [NSNumber])?.map(\.doubleValue) == [0.1, 0.2, 0.8, 0.9])
        #expect(data["crop_from_auto"] as? Bool == true)
        #expect(data["paper_black"] as? Bool == false)
        #expect(data["manual_crop_rect"] == nil)
        #expect(data["auto_crop_enabled"] == nil)
        #expect(data["true_black"] == nil)
        #expect((data["grade"] as? NSNumber)?.doubleValue == 100)
        #expect((data["cast_removal_strength"] as? NSNumber)?.doubleValue == 1)
    }

    @Test func dropsRetiredKeysAndMapsDNG() {
        var data: [String: Any] = [
            "flare": 0.2,
            "vibrance": 0.5,
            "export_fmt": "DNG",
            "crosstalk_profile": "Default",
            "process_mode": "E-6",
            "cast_removal_strength": 0.5,
        ]
        ConfigMigrations.migrateFlatConfig(&data)
        #expect(data["flare"] == nil)
        #expect(data["vibrance"] == nil)
        #expect(data["export_fmt"] as? String == "TIFF")
        #expect(data["crosstalk_profile"] as? String == "Generic C41")
        #expect((data["cast_removal_strength"] as? NSNumber)?.doubleValue == 0)
    }

    @Test func shippedDefaultsMatchNegPyLoadConfig() {
        let flat = WorkspaceFlatConfig.shippedDefaults()
        #expect(flat["process_mode"] as? String == "Color Negative")
        #expect((flat["density"] as? NSNumber)?.doubleValue == 1)
        #expect((flat["grade"] as? NSNumber)?.doubleValue == 100)
        #expect(flat["auto_exposure"] as? Bool == true)
        #expect(flat["auto_normalize_contrast"] as? Bool == true)
        #expect((flat["saturation"] as? NSNumber)?.doubleValue == 1)
        #expect((flat["analysis_buffer"] as? NSNumber)?.doubleValue == 0.05)
        #expect(flat["auto_density_uses_crop"] as? Bool == true)
        #expect(flat["crop_from_auto"] as? Bool == true)
        #expect(flat["dust_remove"] as? Bool == false)
        #expect((flat["dust_threshold"] as? NSNumber)?.doubleValue == 0.66)
        #expect((flat["dust_size"] as? NSNumber)?.intValue == 4)
    }
}
