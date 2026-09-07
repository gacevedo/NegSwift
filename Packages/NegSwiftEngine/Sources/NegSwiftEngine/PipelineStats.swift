import Foundation

/// S13 stage counters. Tests assert a density-only reprint skips bake / orient / analyze / upload.
public struct PipelineStageCounters: Sendable, Equatable {
    public var decode = 0
    public var dust = 0
    public var heal = 0
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

public enum PipelineTiming: String, Sendable {
    case firstPaint
    case fullPreview
}

public enum PipelineStage: String, Sendable {
    case decode
    case dust
    case heal
    case orient
    case analyze
    case print
    case upload
    case download
    case presentEncode
}

/// Process-wide reprint-stage counters. Locked; safe from the native render queue.
public enum PipelineStats: Sendable {
    public static func reset() {
        lock.lock()
        counts = PipelineStageCounters()
        recordedTimings = PipelineTimings()
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

    public static func record(_ timing: PipelineTiming, milliseconds: Double) {
        lock.lock()
        switch timing {
        case .firstPaint: recordedTimings.firstPaintMs = milliseconds
        case .fullPreview: recordedTimings.fullPreviewMs = milliseconds
        }
        lock.unlock()
    }

    public static func increment(_ stage: PipelineStage, by amount: Int = 1) {
        guard amount != 0 else { return }
        lock.lock()
        switch stage {
        case .decode: counts.decode += amount
        case .dust: counts.dust += amount
        case .heal: counts.heal += amount
        case .orient: counts.orient += amount
        case .analyze: counts.analyze += amount
        case .print: counts.print += amount
        case .upload: counts.upload += amount
        case .download: counts.download += amount
        case .presentEncode: counts.presentEncode += amount
        }
        lock.unlock()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts = PipelineStageCounters()
    nonisolated(unsafe) private static var recordedTimings = PipelineTimings()
}
