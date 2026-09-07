import Foundation

/// S13j: split native work so TIFF/JPEG decode can overlap, RAW stays serial, and
/// selected-frame jobs are not stuck behind strip thumbs / neighbor prefetch.
public enum NativeJobKind: Sendable {
    /// Canvas preview, detect, export, armed-crop open.
    case selected
    /// Strip thumbs and neighbor linear prefetch.
    case strip
}

/// Resource lane. Raster prefetch/thumbs overlap; RAW and Metal print stay serial.
public enum NativeJobLane: Sendable {
    /// TIFF/JPEG linear prefetch and cheap ImageIO / embedded-JPEG thumbs.
    case raster
    /// LibRaw decode + RAW print/detect/export. One worker (OpenMP is not parallel-safe here).
    case raw
    /// TIFF/JPEG print / detect / export (Metal working set is single-owner).
    case print
}

public struct NativeJobQueueStats: Sendable, Equatable {
    public var rasterStarted = 0
    public var rawStarted = 0
    public var printStarted = 0
    public var stripCancelled = 0
    public var peakRasterConcurrent = 0

    public init() {}
}

/// Process-wide scheduler used by the in-process Swift backend.
public final class NativeJobQueue: @unchecked Sendable {
    public static let shared = NativeJobQueue()

    public var rasterConcurrency: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return rasterLimit
        }
        set {
            lock.lock()
            rasterLimit = max(1, newValue)
            lock.unlock()
        }
    }

    public func stats() -> NativeJobQueueStats {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Drop pending strip jobs and reset counters. In-flight work still finishes.
    public func reset() {
        cancelStripJobs()
        lock.lock()
        recorded = NativeJobQueueStats()
        rasterLimit = Self.defaultRasterConcurrency
        lock.unlock()
    }

    /// Queued (not started) strip jobs fail with ``CancellationError``.
    public func cancelStripJobs() {
        lock.lock()
        epoch += 1
        let cancelled = pending.filter { $0.kind == .strip }
        pending.removeAll { $0.kind == .strip }
        recorded.stripCancelled += cancelled.count
        lock.unlock()
        for job in cancelled {
            job.fail(CancellationError())
        }
    }

    public func submit<T: Sendable>(
        kind: NativeJobKind,
        lane: NativeJobLane,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let jobEpoch: Int = {
            lock.lock()
            defer { lock.unlock() }
            return epoch
        }()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let job = Job(kind: kind, lane: lane, epoch: jobEpoch) {
                try operation()
            } resume: { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value as! T)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            enqueue(job)
        }
    }

    public static func selectedLane(forScan path: String) -> NativeJobLane {
        ScanFormat.isCameraRaw(path) ? .raw : .print
    }

    public static func prefetchLane(forScan path: String) -> NativeJobLane {
        ScanFormat.isCameraRaw(path) ? .raw : .raster
    }

    private final class Job: @unchecked Sendable {
        let kind: NativeJobKind
        let lane: NativeJobLane
        let epoch: Int
        private let work: () throws -> Any
        private let resume: (Result<Any, Error>) -> Void
        private let resumeLock = NSLock()
        private var resumed = false

        init(
            kind: NativeJobKind,
            lane: NativeJobLane,
            epoch: Int,
            work: @escaping () throws -> Any,
            resume: @escaping (Result<Any, Error>) -> Void
        ) {
            self.kind = kind
            self.lane = lane
            self.epoch = epoch
            self.work = work
            self.resume = resume
        }

        func run() {
            let result: Result<Any, Error>
            do {
                result = .success(try work())
            } catch {
                result = .failure(error)
            }
            finish(result)
        }

        func fail(_ error: Error) {
            finish(.failure(error))
        }

        private func finish(_ result: Result<Any, Error>) {
            resumeLock.lock()
            defer { resumeLock.unlock() }
            guard !resumed else { return }
            resumed = true
            resume(result)
        }
    }

    private let lock = NSLock()
    private var pending: [Job] = []
    private var epoch = 0
    private var runningRaster = 0
    private var runningRaw = 0
    private var runningPrint = 0
    private var rasterLimit = defaultRasterConcurrency
    private var recorded = NativeJobQueueStats()

    private static var defaultRasterConcurrency: Int {
        min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))
    }

    private init() {}

    private func enqueue(_ job: Job) {
        lock.lock()
        if job.kind == .strip, job.epoch != epoch {
            recorded.stripCancelled += 1
            lock.unlock()
            job.fail(CancellationError())
            return
        }
        pending.append(job)
        let scheduled = takeRunnableUnlocked()
        lock.unlock()
        for cancelled in scheduled.cancelled {
            cancelled.fail(CancellationError())
        }
        for item in scheduled.ready {
            start(item)
        }
    }

    private func finish(_ job: Job) {
        lock.lock()
        switch job.lane {
        case .raster:
            runningRaster = max(0, runningRaster - 1)
        case .raw:
            runningRaw = 0
        case .print:
            runningPrint = 0
        }
        let scheduled = takeRunnableUnlocked()
        lock.unlock()
        for cancelled in scheduled.cancelled {
            cancelled.fail(CancellationError())
        }
        for item in scheduled.ready {
            start(item)
        }
    }

    private func takeRunnableUnlocked() -> (ready: [Job], cancelled: [Job]) {
        var queue = pending
        pending = []
        var ready: [Job] = []
        var kept: [Job] = []
        var cancelled: [Job] = []

        func hasSelectedPending(lane: NativeJobLane) -> Bool {
            kept.contains { $0.kind == .selected && $0.lane == lane }
                || queue.contains { $0.kind == .selected && $0.lane == lane }
        }

        func canStart(_ job: Job) -> Bool {
            switch job.lane {
            case .raster:
                if job.kind == .selected { return true }
                return runningRaster < rasterLimit && !hasSelectedPending(lane: .raster)
            case .raw:
                guard runningRaw == 0 else { return false }
                if job.kind == .strip {
                    return !hasSelectedPending(lane: .raw)
                }
                return true
            case .print:
                guard runningPrint == 0 else { return false }
                if job.kind == .strip {
                    return !hasSelectedPending(lane: .print)
                }
                return true
            }
        }

        func consider(_ job: Job) {
            if job.kind == .strip, job.epoch != epoch {
                recorded.stripCancelled += 1
                cancelled.append(job)
                return
            }
            if canStart(job) {
                markRunningUnlocked(job)
                ready.append(job)
            } else {
                kept.append(job)
            }
        }

        var strips: [Job] = []
        for job in queue {
            if job.kind == .selected {
                consider(job)
            } else {
                strips.append(job)
            }
        }
        queue = strips
        for job in queue {
            consider(job)
        }
        pending = kept
        return (ready, cancelled)
    }

    private func markRunningUnlocked(_ job: Job) {
        switch job.lane {
        case .raster:
            runningRaster += 1
            recorded.rasterStarted += 1
            recorded.peakRasterConcurrent = max(recorded.peakRasterConcurrent, runningRaster)
        case .raw:
            runningRaw = 1
            recorded.rawStarted += 1
        case .print:
            runningPrint = 1
            recorded.printStarted += 1
        }
    }

    private func start(_ job: Job) {
        let priority: TaskPriority = job.kind == .selected ? .userInitiated : .utility
        Task.detached(priority: priority) { [weak self] in
            if job.kind == .strip {
                let current = self?.currentEpoch()
                if current != job.epoch {
                    self?.noteStripCancelled()
                    job.fail(CancellationError())
                    self?.finish(job)
                    return
                }
            }
            job.run()
            self?.finish(job)
        }
    }

    private func currentEpoch() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    private func noteStripCancelled() {
        lock.lock()
        recorded.stripCancelled += 1
        lock.unlock()
    }
}
