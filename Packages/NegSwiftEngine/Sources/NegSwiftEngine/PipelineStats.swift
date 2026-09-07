import Foundation

/// S13 stage counters. Tests assert a density-only reprint skips bake / orient / analyze / upload.
public struct PipelineStageCounters: Sendable, Equatable {
    public var decode = 0
    public var dust = 0
    public var heal = 0
    public var autocrop = 0
    public var orient = 0
    public var analyze = 0
    public var print = 0
    public var upload = 0
    public var download = 0
    public var presentEncode = 0

    public init() {}
}

/// S13g first-paint vs settled-preview durations (milliseconds). Last write wins.
public struct PipelineTimings: Sendable, Equatable {
    public var firstPaintMs: Double = 0
    public var fullPreviewMs: Double = 0

    public init() {}
}

/// Per-stage CPU/GPU time (milliseconds) accumulated since the last ``reset()``.
public struct PipelineStageTimings: Sendable, Equatable {
    public var detectMs: Double = 0
    public var decodeMs: Double = 0
    public var dustMs: Double = 0
    public var healMs: Double = 0
    public var autocropMs: Double = 0
    public var orientMs: Double = 0
    public var analyzeMs: Double = 0
    public var printMs: Double = 0
    public var uploadMs: Double = 0
    public var downloadMs: Double = 0
    public var presentMs: Double = 0

    public init() {}

    public func dictionary() -> [String: Double] {
        [
            "detect_ms": detectMs,
            "decode_ms": decodeMs,
            "dust_ms": dustMs,
            "heal_ms": healMs,
            "autocrop_ms": autocropMs,
            "orient_ms": orientMs,
            "analyze_ms": analyzeMs,
            "print_ms": printMs,
            "upload_ms": uploadMs,
            "download_ms": downloadMs,
            "present_ms": presentMs,
        ]
    }
}

public enum PipelineTiming: String, Sendable {
    case firstPaint
    case fullPreview
}

public enum PipelineStage: String, Sendable {
    case detect
    case decode
    case dust
    case heal
    case autocrop
    case orient
    case analyze
    case print
    case upload
    case download
    case present
    case presentEncode
}

/// Process-wide reprint-stage counters. Locked; safe from the native render queue.
public enum PipelineStats: Sendable {
    public static func reset() {
        lock.lock()
        counts = PipelineStageCounters()
        recordedTimings = PipelineTimings()
        recordedStageTimings = PipelineStageTimings()
        lock.unlock()
    }

    public static func snapshot() -> PipelineStageCounters {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    public static func timings() -> PipelineTimings {
        lock.lock()
        defer { lock.unlock() }
        return recordedTimings
    }

    public static func stageTimings() -> PipelineStageTimings {
        lock.lock()
        defer { lock.unlock() }
        return recordedStageTimings
    }

    public static func record(_ timing: PipelineTiming, milliseconds: Double) {
        lock.lock()
        switch timing {
        case .firstPaint: recordedTimings.firstPaintMs = milliseconds
        case .fullPreview: recordedTimings.fullPreviewMs = milliseconds
        }
        lock.unlock()
    }

    public static func recordStage(_ stage: PipelineStage, milliseconds: Double) {
        guard milliseconds > 0 else { return }
        lock.lock()
        switch stage {
        case .detect: recordedStageTimings.detectMs += milliseconds
        case .decode: recordedStageTimings.decodeMs += milliseconds
        case .dust: recordedStageTimings.dustMs += milliseconds
        case .heal: recordedStageTimings.healMs += milliseconds
        case .autocrop: recordedStageTimings.autocropMs += milliseconds
        case .orient: recordedStageTimings.orientMs += milliseconds
        case .analyze: recordedStageTimings.analyzeMs += milliseconds
        case .print: recordedStageTimings.printMs += milliseconds
        case .upload: recordedStageTimings.uploadMs += milliseconds
        case .download: recordedStageTimings.downloadMs += milliseconds
        case .present: recordedStageTimings.presentMs += milliseconds
        case .presentEncode: break
        }
        lock.unlock()
    }

    public static func measure<T>(_ stage: PipelineStage, _ body: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try body()
        recordStage(stage, milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return result
    }

    public static func increment(_ stage: PipelineStage, by amount: Int = 1) {
        guard amount != 0 else { return }
        lock.lock()
        switch stage {
        case .detect: break
        case .decode: counts.decode += amount
        case .dust: counts.dust += amount
        case .heal: counts.heal += amount
        case .autocrop: counts.autocrop += amount
        case .orient: counts.orient += amount
        case .analyze: counts.analyze += amount
        case .print: counts.print += amount
        case .upload: counts.upload += amount
        case .download: counts.download += amount
        case .present: break
        case .presentEncode: counts.presentEncode += amount
        }
        lock.unlock()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts = PipelineStageCounters()
    nonisolated(unsafe) private static var recordedTimings = PipelineTimings()
    nonisolated(unsafe) private static var recordedStageTimings = PipelineStageTimings()
}
