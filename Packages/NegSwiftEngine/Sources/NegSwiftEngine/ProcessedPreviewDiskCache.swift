import CryptoKit
import Foundation

/// S13k: settled processed preview on disk — path + file mtime + sidecar mtime + config fingerprint.
final class ProcessedPreviewDiskCache: @unchecked Sendable {
    static let shared = ProcessedPreviewDiskCache()

    private let lock = NSLock()
    private var rootDirectory: URL?
    private var order: [String] = []
    private var sizes: [String: Int] = [:]

    func configure(rootDirectory: URL?) {
        lock.lock()
        self.rootDirectory = rootDirectory
        lock.unlock()
        if let rootDirectory {
            try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
    }

    func reset() {
        lock.lock()
        order.removeAll()
        sizes.removeAll()
        lock.unlock()
    }

    /// Test-only: drop every cached file and in-memory index.
    func clearAll() {
        lock.lock()
        let root = rootDirectory
        rootDirectory = nil
        order.removeAll()
        sizes.removeAll()
        lock.unlock()
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }

    func lookup(
        path: String,
        longEdgePx: Int?,
        config: PrintConfig,
        processMode: FilmProcessMode?
    ) -> LinearRGBBuffer? {
        guard let root = configuredRoot() else { return nil }
        let key = Self.cacheKey(path: path, longEdgePx: longEdgePx, config: config, processMode: processMode)
        let fileName = Self.fileName(for: key)
        let url = root.appendingPathComponent(fileName)
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = Self.read(url: url, expectedKey: key) else { return nil }
        touchLocked(fileName)
        return buffer
    }

    func store(
        path: String,
        longEdgePx: Int?,
        config: PrintConfig,
        processMode: FilmProcessMode?,
        buffer: LinearRGBBuffer
    ) {
        guard let root = configuredRoot() else { return }
        let key = Self.cacheKey(path: path, longEdgePx: longEdgePx, config: config, processMode: processMode)
        let fileName = Self.fileName(for: key)
        let url = root.appendingPathComponent(fileName)
        let byteSize = Self.encodedByteSize(for: buffer, key: key)
        guard byteSize <= CacheBudget.diskPreviewMaxBytes else { return }
        do {
            try Self.write(url: url, key: key, buffer: buffer)
        } catch {
            return
        }
        lock.lock()
        touchLocked(fileName)
        sizes[fileName] = byteSize
        evictIfNeededLocked()
        lock.unlock()
    }

    static func cacheKey(
        path: String,
        longEdgePx: Int?,
        config: PrintConfig,
        processMode: FilmProcessMode?
    ) -> String {
        let stamp = ReprintCache.fileStamp(path)
        let sidecar = sidecarStamp(path)
        let bakeKey = ReprintCache.bakeKey(
            path: path,
            stamp: stamp,
            longEdgePx: longEdgePx,
            config: config
        )
        let analysisKey = ReprintCache.analysisKey(
            bakeKey: bakeKey,
            config: config,
            processMode: processMode
        )
        return [
            analysisKey,
            sidecar,
            config.applyPixelCrop ? "1" : "0",
        ].joined(separator: "|")
    }

    static func sidecarStamp(_ path: String) -> String {
        let sidecar = SidecarStore.url(forScanPath: path)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return "0" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: sidecar.path)
        let size = attrs?[.size] as? NSNumber ?? 0
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return "\(size.intValue)|\(modified.timeIntervalSince1970)"
    }

    private func configuredRoot() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return rootDirectory
    }

    private func touchLocked(_ fileName: String) {
        order.removeAll { $0 == fileName }
        order.append(fileName)
    }

    private func evictIfNeededLocked() {
        func totalBytes() -> Int {
            order.reduce(0) { $0 + (sizes[$1] ?? 0) }
        }
        while order.count > CacheBudget.diskPreviewEntries, !order.isEmpty {
            let evicted = order.removeFirst()
            sizes.removeValue(forKey: evicted)
            if let root = rootDirectory {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(evicted))
            }
        }
        while totalBytes() > CacheBudget.diskPreviewMaxBytes, !order.isEmpty {
            let evicted = order.removeFirst()
            sizes.removeValue(forKey: evicted)
            if let root = rootDirectory {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(evicted))
            }
        }
    }

    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).nspc"
    }

    private static let magic = Data("NSPC".utf8)
    private static let formatVersion: UInt32 = 1

    private static func encodedByteSize(for buffer: LinearRGBBuffer, key: String) -> Int {
        20 + key.utf8.count + buffer.pixels.count * MemoryLayout<Float>.size
    }

    private static func write(url: URL, key: String, buffer: LinearRGBBuffer) throws {
        let keyData = Data(key.utf8)
        var header = Data(capacity: 20 + keyData.count)
        header.append(magic)
        var version = formatVersion.littleEndian
        var width = UInt32(buffer.width).littleEndian
        var height = UInt32(buffer.height).littleEndian
        var keyLen = UInt32(keyData.count).littleEndian
        withUnsafeBytes(of: &version) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &width) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &height) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &keyLen) { header.append(contentsOf: $0) }
        header.append(keyData)
        let pixelData = buffer.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent("\(url.lastPathComponent).\(UUID().uuidString).part")
        var payload = header
        payload.append(pixelData)
        try payload.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    private static func read(url: URL, expectedKey: String) -> LinearRGBBuffer? {
        guard let data = try? Data(contentsOf: url), data.count >= 20 else { return nil }
        guard data.prefix(4) == magic else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let version = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }.littleEndian
        guard version == formatVersion else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let width = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }.littleEndian)
        let height = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }.littleEndian)
        let keyLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self) }.littleEndian)
        let headerSize = 20 + keyLen
        guard width > 0, height > 0, keyLen >= 0, data.count >= headerSize else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let keyData = data.subdata(in: 20..<(20 + keyLen))
        guard String(data: keyData, encoding: .utf8) == expectedKey else { return nil }
        let pixelBytes = data.count - headerSize
        let expectedBytes = width * height * 3 * MemoryLayout<Float>.size
        guard pixelBytes == expectedBytes else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let floats = data.subdata(in: headerSize..<data.count).withUnsafeBytes {
            Array(UnsafeBufferPointer<Float>(
                start: $0.baseAddress?.assumingMemoryBound(to: Float.self),
                count: expectedBytes / MemoryLayout<Float>.size
            ))
        }
        return LinearRGBBuffer(width: width, height: height, pixels: floats)
    }
}
