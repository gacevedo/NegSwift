import Foundation

/// S13k: longer-lived in-memory working sets (aligned with NegPy preview cache defaults).
enum CacheBudget {
    /// Reprint bake / orient / analyze entries (was 8).
    static let reprintEntries = 16
    /// Decoded linear LRU count (was 8).
    static let linearEntries = 16
    /// Approximate RSS cap for decoded linear samples.
    static let linearMaxBytes = 1_200_000_000
    /// Resident post-dust/heal Metal textures (was 6).
    static let metalWorkingSet = 12
    /// On-disk processed preview entries.
    static let diskPreviewEntries = 32
    /// On-disk processed preview byte cap (~512 MB).
    static let diskPreviewMaxBytes = 512_000_000
}
