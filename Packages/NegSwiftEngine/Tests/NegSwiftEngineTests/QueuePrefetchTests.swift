import Foundation
import Testing
@testable import NegSwiftEngine

/// S13j: parallel TIFF/JPEG decode, selected-frame priority, neighbor linear prefetch.
@Suite(.serialized)
struct QueuePrefetchTests {
    @Test func rasterStripJobsRunInParallel() async throws {
        NativeJobQueue.shared.reset()
        NativeJobQueue.shared.rasterConcurrency = 2
        async let first: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            Thread.sleep(forTimeInterval: 0.06)
        }
        async let second: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            Thread.sleep(forTimeInterval: 0.06)
        }
        try await first
        try await second
        #expect(NativeJobQueue.shared.stats().peakRasterConcurrent >= 2)
    }

    @Test func rawJobsStaySerial() async throws {
        NativeJobQueue.shared.reset()
        let intervals = LockedIntervals()
        async let first: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raw) {
            intervals.record { Thread.sleep(forTimeInterval: 0.04) }
        }
        async let second: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raw) {
            intervals.record { Thread.sleep(forTimeInterval: 0.04) }
        }
        try await first
        try await second
        #expect(intervals.count == 2)
        #expect(!intervals.overlap())
    }

    @Test func selectedPrintDoesNotWaitBehindRasterStrip() async throws {
        NativeJobQueue.shared.reset()
        NativeJobQueue.shared.rasterConcurrency = 1
        async let strip: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            Thread.sleep(forTimeInterval: 0.2)
        }
        try await Task.sleep(for: .milliseconds(30))
        let started = Date()
        try await NativeJobQueue.shared.submit(kind: .selected, lane: .print) {}
        #expect(Date().timeIntervalSince(started) < 0.05)
        try await strip
        #expect(NativeJobQueue.shared.stats().printStarted == 1)
    }

    @Test func cancelQueuedStripDropsJobsThatHaveNotStarted() async throws {
        NativeJobQueue.shared.reset()
        NativeJobQueue.shared.rasterConcurrency = 1
        async let inflight: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            Thread.sleep(forTimeInterval: 0.25)
        }
        try await Task.sleep(for: .milliseconds(30))
        async let queued: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            Issue.record("queued strip job should have been cancelled")
        }
        try await Task.sleep(for: .milliseconds(20))
        NativeJobQueue.shared.cancelStripJobs()
        do {
            try await queued
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // expected
        }
        try await inflight
        #expect(NativeJobQueue.shared.stats().stripCancelled >= 1)
    }

    @Test func selectedRawStartsBeforeQueuedRawPrefetch() async throws {
        NativeJobQueue.shared.reset()
        let order = LockedOrder()
        async let dummy: Void = NativeJobQueue.shared.submit(kind: .selected, lane: .raw) {
            Thread.sleep(forTimeInterval: 0.12)
        }
        try await Task.sleep(for: .milliseconds(30))
        async let prefetch: Void = NativeJobQueue.shared.submit(kind: .strip, lane: .raw) {
            order.append("prefetch")
        }
        async let selected: Void = NativeJobQueue.shared.submit(kind: .selected, lane: .raw) {
            order.append("selected")
        }
        try await dummy
        try await selected
        try await prefetch
        #expect(order.snapshot() == ["selected", "prefetch"])
    }

    @Test func prefetchLinearServesLaterPrintWithoutASecondDecode() throws {
        let url = try writeQueuePrefetchTIFF(width: 80, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        let pipeline = NativePipeline(pixelBackend: .cpu)
        _ = try pipeline.prefetchLinear(path: url.path, maxLongEdge: 64, analysisOversample: true)
        #expect(PipelineStats.snapshot().decode == 1)
        #expect(LinearBufferCache.shared.contains(path: url.path))
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: 64,
            processMode: .colorNegative,
            config: .s8Pin
        )
        #expect(PipelineStats.snapshot().decode == 1)
    }

    @Test func parallelSameFilePrefetchDecodesOnce() async throws {
        let url = try writeQueuePrefetchTIFF(width: 72, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }
        NativePipeline.resetWorkingSets()
        async let first: LinearRGBBuffer = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            try NativePipeline().prefetchLinear(path: url.path, maxLongEdge: 64, analysisOversample: true)
        }
        async let second: LinearRGBBuffer = NativeJobQueue.shared.submit(kind: .strip, lane: .raster) {
            try NativePipeline().prefetchLinear(path: url.path, maxLongEdge: 64, analysisOversample: true)
        }
        let buffers = try await (first, second)
        #expect(buffers.0.width > 0 && buffers.1.width > 0)
        #expect(PipelineStats.snapshot().decode == 1)
    }
}

private final class LockedOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ value: String) {
        lock.lock()
        items.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private final class LockedIntervals: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(start: Date, end: Date)] = []

    func record(_ body: () -> Void) {
        let start = Date()
        body()
        let end = Date()
        lock.lock()
        items.append((start, end))
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func overlap() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard items.count == 2 else { return false }
        return items[0].start < items[1].end && items[1].start < items[0].end
    }
}

private func writeQueuePrefetchTIFF(width: Int, height: Int) throws -> URL {
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    for i in stride(from: 0, to: samples.count, by: 3) {
        samples[i] = 42000
        samples[i + 1] = 22000
        samples[i + 2] = 9000
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s13j-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}
