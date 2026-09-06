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
    public var presentEncode = 0

    public init() {}
}

public enum PipelineStage: String, Sendable {
    case decode
    case dust
    case heal
    case orient
    case analyze
    case print
    case upload
    case presentEncode
}

/// Process-wide reprint-stage counters. Locked; safe from the native render queue.
public enum PipelineStats: Sendable {
    public static func reset() {
        lock.lock()
        counts = PipelineStageCounters()
        lock.unlock()
    }

    public static func snapshot() -> PipelineStageCounters {
        lock.lock()
        defer { lock.unlock() }
        return counts
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
        case .presentEncode: counts.presentEncode += amount
        }
        lock.unlock()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts = PipelineStageCounters()
}
