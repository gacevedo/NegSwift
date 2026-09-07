import Foundation
import NegSwiftLibRaw

/// LibRaw sensor-native linear RGB. Not ImageIO / Core Image (those apply a camera matrix).
///
/// Matches NegPy `output_color=raw`, `gamma=(1,1)`, unity white balance,
/// `adjust_maximum_thr=0`, `user_flip=0`, then bake EXIF orientation from the file
/// (not LibRaw `sizes.flip`, which can disagree on Canon CR2). Preview/thumb: Bayer
/// `half_size` + LINEAR; X-Trans full-size PPG (NegPy). Export is AHD.
/// One `libraw` handle per file shares `open` / `unpack` across probe, splash, and decode.
public enum RawDecode: Sendable {
    public enum Demosaic: Sendable, Equatable {
        case linear
        case ppg
        case ahd
        case other(Int)

        public init(userQual: Int) {
            switch userQual {
            case Int(NEGSWIFT_RAW_QUAL_LINEAR): self = .linear
            case Int(NEGSWIFT_RAW_QUAL_PPG): self = .ppg
            case Int(NEGSWIFT_RAW_QUAL_AHD): self = .ahd
            default: self = .other(userQual)
            }
        }

        public var userQual: Int {
            switch self {
            case .linear: Int(NEGSWIFT_RAW_QUAL_LINEAR)
            case .ppg: Int(NEGSWIFT_RAW_QUAL_PPG)
            case .ahd: Int(NEGSWIFT_RAW_QUAL_AHD)
            case let .other(value): value
            }
        }
    }

    public struct Result: Sendable {
        public var buffer: LinearRGBBuffer
        public var usedHalfSize: Bool
        public var demosaic: Demosaic
        public var isXTrans: Bool
    }

    public static var isAvailable: Bool {
        negswift_raw_available() != 0
    }

    /// Process-wide `libraw_open_file` count since ``resetStats()``.
    public static var openCount: Int { Int(negswift_raw_stat_opens()) }

    /// Process-wide `libraw_unpack` count since ``resetStats()``.
    public static var unpackCount: Int { Int(negswift_raw_stat_unpacks()) }

    public static func resetStats() {
        negswift_raw_reset_stats()
    }

    /// Drop cached handles (unpacked RAW is large). Tests call this with working-set reset.
    public static func resetSessions() {
        RawSessionCache.shared.reset()
    }

    /// Homebrew LibRaw Markesteijn uses libomp. Keep all cores on the selected
    /// frame. Concurrent `dcraw_process` is serialized by ``librawProcessLock``.
    public static func setOpenMPThreads(_ count: Int) {
        negswift_raw_set_omp_threads(Int32(max(1, count)))
    }

    public static var openMPMaxThreads: Int { Int(negswift_raw_omp_max_threads()) }

    public static var openMPProcCount: Int { Int(negswift_raw_omp_num_procs()) }

    /// One OpenMP team at a time. Do not pin `OMP_NUM_THREADS=1` — that made S13i slower.
    fileprivate static let librawProcessLock = NSLock()

    public static func probe(url: URL) -> (width: Int, height: Int)? {
        guard isAvailable else { return nil }
        let orientation = exifOrientation(at: url)
        return RawSessionCache.shared.withSession(url: url) { session in
            session.probe(exifOrientation: orientation)
        }
    }

    public static func probe(path: String) -> (width: Int, height: Int)? {
        probe(url: URL(fileURLWithPath: path))
    }

    public static func decode(url: URL, halfSize: Bool = false) throws -> LinearRGBBuffer {
        try decodeDetailed(url: url, halfSize: halfSize).buffer
    }

    public static func decodeDetailed(
        url: URL,
        halfSize: Bool = false,
        demosaic: Demosaic? = nil
    ) throws -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LinearDecodeError.fileNotFound(url)
        }
        guard isAvailable else {
            throw LinearDecodeError.rawUnavailable
        }
        let orientation = exifOrientation(at: url)
        return try RawSessionCache.shared.withSession(url: url) { session in
            try session.decode(halfSize: halfSize, demosaic: demosaic, exifOrientation: orientation)
        }
    }

    public static func decode(path: String, halfSize: Bool = false) throws -> LinearRGBBuffer {
        try decode(url: URL(fileURLWithPath: path), halfSize: halfSize)
    }

    /// LibRaw embedded preview. JPEG bytes only — BITMAP is reported without pixel data.
    public struct Thumb: Sendable {
        public var format: Format
        public var jpeg: Data?
        public var width: Int
        public var height: Int
        public var orientation: Int

        public enum Format: Sendable {
            case jpeg
            case bitmap
        }
    }

    public static func extractThumb(url: URL) -> Thumb? {
        guard isAvailable else { return nil }
        let orientation = exifOrientation(at: url)
        return RawSessionCache.shared.withSession(url: url) { session in
            session.extractThumb(exifOrientation: orientation)
        }
    }

    public static func extractThumb(path: String) -> Thumb? {
        extractThumb(url: URL(fileURLWithPath: path))
    }

    private static func exifOrientation(at url: URL) -> Int {
        ImageCoding.exifOrientation(at: url)
    }
}

/// LRU of open LibRaw handles. Probe + splash + preview share `open`/`unpack`.
final class RawSessionCache: @unchecked Sendable {
    static let shared = RawSessionCache()

    private struct Entry {
        var path: String
        var stamp: String
        var session: RawSession
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let limit = 4

    func reset() {
        lock.lock()
        let sessions = entries.map(\.session)
        entries.removeAll()
        lock.unlock()
        for session in sessions {
            session.close()
        }
    }

    func withSession<T>(url: URL, _ body: (RawSession) throws -> T) rethrows -> T {
        let session = session(for: url)
        return try body(session)
    }

    private func session(for url: URL) -> RawSession {
        let path = url.path
        let stamp = ReprintCache.fileStamp(path)
        lock.lock()
        if let index = entries.firstIndex(where: { $0.path == path && $0.stamp == stamp }) {
            let entry = entries[index]
            if index > 0 {
                entries.remove(at: index)
                entries.insert(entry, at: 0)
            }
            lock.unlock()
            return entry.session
        }
        let session = RawSession(path: path)
        entries.insert(Entry(path: path, stamp: stamp, session: session), at: 0)
        var evicted: RawSession?
        if entries.count > limit {
            evicted = entries.removeLast().session
        }
        lock.unlock()
        evicted?.close()
        return session
    }
}

final class RawSession: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var handle: OpaquePointer?

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let handle {
            negswift_raw_close(handle)
            self.handle = nil
        }
    }

    func probe(exifOrientation: Int) -> (width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = openedHandle() else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        var orientation: Int32 = 1
        let rc = negswift_raw_handle_probe(handle, &width, &height, &orientation)
        guard rc == 0, width > 0, height > 0 else { return nil }
        if ScanFormat.orientationSwapsDimensions(exifOrientation) {
            return (Int(height), Int(width))
        }
        return (Int(width), Int(height))
    }

    func decode(
        halfSize: Bool,
        demosaic: RawDecode.Demosaic? = nil,
        exifOrientation: Int
    ) throws -> RawDecode.Result {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = openedHandle() else {
            throw LinearDecodeError.rawDecodeFailed("libraw_init failed.")
        }
        var raw = NegSwiftRawBuffer()
        var message = [CChar](repeating: 0, count: 256)
        let userQual = Int32(demosaic?.userQual ?? -1)
        RawDecode.librawProcessLock.lock()
        let rc = message.withUnsafeMutableBufferPointer { err in
            negswift_raw_handle_decode_ex(handle, halfSize ? 1 : 0, userQual, &raw, err.baseAddress, err.count)
        }
        RawDecode.librawProcessLock.unlock()
        defer { negswift_raw_free(&raw) }
        if rc != 0 {
            throw LinearDecodeError.rawDecodeFailed(cMessage(message))
        }
        guard raw.width > 0, raw.height > 0, let pointer = raw.pixels else {
            throw LinearDecodeError.rawDecodeFailed("LibRaw returned an empty buffer.")
        }
        let pixels = Array(UnsafeBufferPointer(start: pointer, count: Int(raw.count)))
        let buffer = LinearRGBBuffer(width: Int(raw.width), height: Int(raw.height), pixels: pixels)
        return RawDecode.Result(
            buffer: buffer.applyingExifOrientation(exifOrientation),
            usedHalfSize: raw.used_half_size != 0,
            demosaic: RawDecode.Demosaic(userQual: Int(raw.user_qual)),
            isXTrans: raw.is_xtrans != 0
        )
    }

    func extractThumb(exifOrientation: Int) -> RawDecode.Thumb? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = openedHandle() else { return nil }
        var raw = NegSwiftRawThumb()
        var message = [CChar](repeating: 0, count: 256)
        let rc = message.withUnsafeMutableBufferPointer { err in
            negswift_raw_handle_thumb(handle, &raw, err.baseAddress, err.count)
        }
        defer { negswift_raw_free_thumb(&raw) }
        guard rc == 0 else { return nil }
        if raw.format == 1, let pointer = raw.data, raw.size > 0 {
            return RawDecode.Thumb(
                format: .jpeg,
                jpeg: Data(bytes: pointer, count: Int(raw.size)),
                width: Int(raw.width),
                height: Int(raw.height),
                orientation: exifOrientation
            )
        }
        if raw.format == 2 {
            return RawDecode.Thumb(
                format: .bitmap,
                jpeg: nil,
                width: Int(raw.width),
                height: Int(raw.height),
                orientation: exifOrientation
            )
        }
        return nil
    }

    private func openedHandle() -> OpaquePointer? {
        if let handle { return handle }
        var message = [CChar](repeating: 0, count: 256)
        let opened = path.withCString { cPath in
            message.withUnsafeMutableBufferPointer { err in
                negswift_raw_open(cPath, err.baseAddress, err.count)
            }
        }
        handle = opened
        return opened
    }

    private func cMessage(_ message: [CChar]) -> String {
        let text = message.withUnsafeBufferPointer { buf in
            String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return text.isEmpty ? "LibRaw could not decode the camera RAW." : text
    }
}
