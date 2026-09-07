import Foundation

/// S13d: LRU of decoded linear samples, keyed by path + file stamp — not exact long-edge.
/// A larger sample serves a smaller preview request (detect 512 / autocrop 1800 / print 1600
/// share one ImageIO or LibRaw pass). Full-res export and RAW half-size stay separate slots.
final class LinearBufferCache: @unchecked Sendable {
    static let shared = LinearBufferCache()

    struct Entry {
        var path: String
        var stamp: String
        var buffer: LinearRGBBuffer
        var isCameraRaw: Bool
        var isFullResolution: Bool
        var usedHalfSize: Bool
        var sourceLongEdge: Int?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let limit = 8

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    func buffer(
        path: String,
        maxLongEdge: Int?,
        analysisOversample: Bool
    ) throws -> LinearRGBBuffer {
        let stamp = ReprintCache.fileStamp(path)
        let wantFull = maxLongEdge == nil

        lock.lock()
        if let hit = lookupUnlocked(
            path: path,
            stamp: stamp,
            maxLongEdge: maxLongEdge,
            analysisOversample: analysisOversample,
            wantFull: wantFull
        ) {
            let sample = hit.buffer
            let cameraRaw = hit.isCameraRaw
            lock.unlock()
            return LinearDecode.shrink(sample, toLongEdge: maxLongEdge, cameraRaw: cameraRaw)
        }
        lock.unlock()

        PipelineStats.increment(.decode)
        let sample = try LinearDecode.decodeSample(
            path: path,
            maxLongEdge: maxLongEdge,
            analysisOversample: analysisOversample
        )
        lock.lock()
        storeUnlocked(
            Entry(
                path: path,
                stamp: stamp,
                buffer: sample.buffer,
                isCameraRaw: sample.isCameraRaw,
                isFullResolution: sample.isFullResolution,
                usedHalfSize: sample.usedHalfSize,
                sourceLongEdge: sample.sourceLongEdge
            )
        )
        lock.unlock()
        return LinearDecode.shrink(sample.buffer, toLongEdge: maxLongEdge, cameraRaw: sample.isCameraRaw)
    }

    private func lookupUnlocked(
        path: String,
        stamp: String,
        maxLongEdge: Int?,
        analysisOversample: Bool,
        wantFull: Bool
    ) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.path == path && $0.stamp == stamp }) else {
            return nil
        }
        let entry = entries[index]
        guard canServe(
            entry,
            maxLongEdge: maxLongEdge,
            analysisOversample: analysisOversample,
            wantFull: wantFull
        ) else {
            return nil
        }
        if index > 0 {
            entries.remove(at: index)
            entries.insert(entry, at: 0)
        }
        return entry
    }

    private func canServe(
        _ entry: Entry,
        maxLongEdge: Int?,
        analysisOversample: Bool,
        wantFull: Bool
    ) -> Bool {
        if entry.isCameraRaw {
            // Preview vs export are different demosaics (PPG / half LINEAR vs AHD).
            // X-Trans preview is full-size, so do not key the slot on usedHalfSize.
            return wantFull == entry.isFullResolution
        }
        if wantFull { return entry.isFullResolution }
        // Preview must not inherit a full-res extract — ImageIO thumbnail look differs.
        if entry.isFullResolution { return false }
        let source = entry.sourceLongEdge ?? entry.buffer.longEdge
        let have = entry.buffer.longEdge
        let need: Int
        if analysisOversample, let maxLongEdge, maxLongEdge > 0 {
            need = LinearDecode.analysisSampleLongEdge(requested: maxLongEdge, sourceLongEdge: source)
        } else {
            need = maxLongEdge ?? source
        }
        return have >= need
    }

    private func storeUnlocked(_ entry: Entry) {
        entries.removeAll { $0.path == entry.path && $0.stamp == entry.stamp }
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast()
        }
    }
}
