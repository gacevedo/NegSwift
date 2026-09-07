import Foundation

/// S13a: last preview working set so slider-only edits skip bake / orient / analyze.
final class ReprintCache: @unchecked Sendable {
    static let shared = ReprintCache()

    struct Entry {
        var bakeKey: String
        var analysisKey: String
        var baked: LinearRGBBuffer
        var oriented: LinearRGBBuffer
        var processMode: FilmProcessMode
        var bounds: LogNegativeBounds
        var analysis: PhotometricPrint.MeteringAnalysis
        var armed: AutocropArmedResult
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let limit = CacheBudget.reprintEntries

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    func lookup(analysisKey: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.analysisKey == analysisKey }
    }

    func lookupBaked(bakeKey: String) -> LinearRGBBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.bakeKey == bakeKey }?.baked
    }

    func store(_ entry: Entry) {
        lock.lock()
        entries.removeAll { $0.analysisKey == entry.analysisKey }
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast()
        }
        lock.unlock()
    }

    static func fileStamp(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? NSNumber ?? 0
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return "\(size.intValue)|\(modified.timeIntervalSince1970)"
    }

    static func bakeKey(path: String, stamp: String, longEdgePx: Int?, config: PrintConfig) -> String {
        let heals = config.healStrokes.map { stroke in
            let pts = stroke.points.map { "\($0.x),\($0.y)" }.joined(separator: ";")
            return "\(pts)|\(stroke.size)"
        }.joined(separator: "/")
        let spots = config.dustSpots.map { "\($0.x),\($0.y),\($0.size)" }.joined(separator: ";")
        return [
            path,
            stamp,
            "\(longEdgePx ?? 0)",
            config.dustRemove ? "1" : "0",
            "\(config.dustThreshold)",
            "\(config.dustSize)",
            heals,
            spots,
        ].joined(separator: "|")
    }

    static func analysisKey(
        bakeKey: String,
        config: PrintConfig,
        processMode: FilmProcessMode?
    ) -> String {
        let crop = config.cropRect.map { "\($0.x1),\($0.y1),\($0.x2),\($0.y2)" } ?? ""
        let analysisRect = config.analysisRect.map { "\($0.x1),\($0.y1),\($0.x2),\($0.y2)" } ?? ""
        return [
            bakeKey,
            "\(config.rotation)",
            config.flipHorizontal ? "1" : "0",
            config.flipVertical ? "1" : "0",
            "\(config.fineRotation)",
            "\(config.analysisBuffer)",
            analysisRect,
            crop,
            config.autoExposure ? "1" : "0",
            config.autoNormalizeContrast ? "1" : "0",
            config.autoDensityUsesCrop ? "1" : "0",
            config.cropFromAuto ? "1" : "0",
            config.autoCropEnabled ? "1" : "0",
            config.cropDetectKey,
            config.autocropRatio,
            config.autocropMode,
            "\(config.autocropRebateTrim)",
            "\(config.convergeV)",
            "\(config.convergeH)",
            "\(config.castRemovalStrength)",
            processMode?.rawValue ?? "auto",
        ].joined(separator: "|")
    }

    static func geometryKey(_ config: PrintConfig) -> String {
        "\(config.rotation)|\(config.flipHorizontal ? 1 : 0)|\(config.flipVertical ? 1 : 0)|\(config.fineRotation)"
    }
}
