/// Where per-pixel stages (normalize, H&D, Lab, OETF) run.
///
/// Analysis (bounds, metering, curve params) always stays on CPU. `.auto` uses
/// Metal when a device and the S12 kernels compiled; otherwise CPU.
public enum PixelBackend: String, Sendable, Equatable {
    case cpu
    case metal
    case auto

    public func resolved() -> PixelBackend {
        switch self {
        case .cpu:
            .cpu
        case .metal, .auto:
            MetalDevice.isAvailable ? .metal : .cpu
        }
    }
}
