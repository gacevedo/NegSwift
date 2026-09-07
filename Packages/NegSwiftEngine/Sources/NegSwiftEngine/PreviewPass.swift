import Foundation

/// S13g: first-paint quality vs the settled canvas / refine pass.
public enum PreviewPass: String, Sendable, Equatable {
    /// Fast first paint: ≤512 long edge, no analysis oversample, skip Lab sharpen and optical dust.
    case draft
    /// Settled canvas / slider reprint / Analysis Buffer: requested long edge + oversample when ≥800.
    case settled

    public static let draftLongEdge = 512
    /// ImageIO thumbnail at the preview edge blurs film/holder boundaries; oversample from this size.
    public static let oversampleLongEdgeGate = 800

    public func resolvedLongEdge(_ requested: Int?) -> Int? {
        switch self {
        case .draft:
            return min(requested ?? Self.draftLongEdge, Self.draftLongEdge)
        case .settled:
            return requested
        }
    }

    public func shouldOversample(longEdgePx: Int?) -> Bool {
        switch self {
        case .draft:
            return false
        case .settled:
            return (longEdgePx ?? 0) >= Self.oversampleLongEdgeGate
        }
    }

    public func applyingDraftShortcuts(_ config: PrintConfig) -> PrintConfig {
        guard self == .draft else { return config }
        var copy = config
        copy.sharpen = 0
        copy.dustRemove = false
        return copy
    }
}
