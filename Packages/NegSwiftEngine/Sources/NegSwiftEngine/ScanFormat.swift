import Foundation

/// Extensions the Swift backend will list and open.
///
/// Raster TIFF/JPEG stay on ImageIO (S1). Camera RAW goes through LibRaw (S14).
/// Matches NegPy `SUPPORTED_RAW_EXTENSIONS` minus TIFF/JPEG/JXL — JXL is still later;
/// Coolscan NEF / Flextight FFF / Pakon special loaders are not ported (LibRaw may
/// still open a file it understands).
public enum ScanFormat: Sendable {
    public static let rasterExtensions: Set<String> = ["tif", "tiff", "jpg", "jpeg"]

    public static let cameraRawExtensions: Set<String> = [
        "3fr", "ari", "arw", "bay", "braw", "crw", "cr2", "cr3", "cap", "data",
        "dcs", "dcr", "dng", "drf", "eip", "erf", "fff", "gpr", "iiq", "k25",
        "kdc", "mdc", "mef", "mos", "mrw", "nef", "nrw", "obm", "orf", "pef",
        "ptx", "pxn", "r3d", "raf", "raw", "rwl", "rw2", "rwz", "sr2", "srf",
        "srw", "x3f",
    ]

    public static let scanExtensions: Set<String> = rasterExtensions.union(cameraRawExtensions)

    public static func pathExtension(of path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    public static func isSupportedScan(_ path: String) -> Bool {
        scanExtensions.contains(pathExtension(of: path))
    }

    public static func isCameraRaw(_ path: String) -> Bool {
        cameraRawExtensions.contains(pathExtension(of: path))
    }

    public static func isRaster(_ path: String) -> Bool {
        rasterExtensions.contains(pathExtension(of: path))
    }

    /// EXIF 5/6/7/8 swap width and height after bake.
    public static func orientationSwapsDimensions(_ orientation: Int) -> Bool {
        (5 ... 8).contains(orientation)
    }
}
