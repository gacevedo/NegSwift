import Foundation
import Testing
@testable import NegSwiftEngine

/// S13l profiling gate: native Swift stage timings on a real scan before optional Metal dust /
/// autocrop / histogram work. Not part of `make compare-s13` (too slow for CI).
///
/// Run:
///   NEGSWIFT_PERF_SCAN=/path/to/scan.tif make bench-native
///   swift test --filter NativeStageTimingTests
@Suite(.serialized)
struct NativeStageTimingTests {
    @Test(.enabled(if: NativeStageTimingTests.localScan() != nil))
    func emitBaselineReport() throws {
        guard let scan = Self.localScan() else { return }
        let report = try Self.buildReport(scan: scan, secondScan: Self.localSecondScan())
        let json = Self.encodeJSON(report)
        print(json)

        if let output = ProcessInfo.processInfo.environment["NEGSWIFT_PERF_OUTPUT"] {
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try json.write(to: url, atomically: true, encoding: .utf8)
            print("wrote \(output)")
        }

        #expect(report["version"] as? Int == 1)
        let cold = report["scenarios"] as? [String: Any]
        let firstOpen = cold?["cold_first_open"] as? [String: Any]
        #expect((firstOpen?["settled_full_preview_ms"] as? Double ?? 0) > 0)
    }

    static func buildReport(scan: URL, secondScan: URL?) throws -> [String: Any] {
        var config = PrintConfig.s8Pin
        config.autoCropEnabled = true
        config.cropFromAuto = true
        config.dustRemove = true
        let pipeline = NativePipeline(pixelBackend: .auto)
        let longEdge = Int(Autocrop.previewRenderSize)

        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let coldStart = CFAbsoluteTimeGetCurrent()
        let mode = try pipeline.detectProcessMode(path: scan.path)
        _ = try pipeline.renderPrintDetailed(
            path: scan.path,
            longEdgePx: PreviewPass.draftLongEdge,
            processMode: mode,
            config: config,
            previewPass: .draft,
            readback: false
        )
        let draftMs = PipelineStats.timings().firstPaintMs
        let draftStages = PipelineStats.stageTimings()
        let draftCounters = PipelineStats.snapshot()

        PipelineStats.reset()
        let settledResult = try pipeline.renderPrintDetailed(
            path: scan.path,
            longEdgePx: longEdge,
            processMode: mode,
            config: config,
            previewPass: .settled,
            readback: false
        )
        let settledMs = PipelineStats.timings().fullPreviewMs
        let settledStages = PipelineStats.stageTimings()
        let settledCounters = PipelineStats.snapshot()
        let coldTotalMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

        PipelineStats.reset()
        var reprint = config
        if let crop = settledResult.cropRect {
            reprint.cropRect = crop
            reprint.cropFromAuto = true
            reprint.autoCropEnabled = true
        }
        reprint.density = 1.12
        let reprintResult = try pipeline.renderPrintDetailed(
            path: scan.path,
            longEdgePx: longEdge,
            processMode: mode,
            config: reprint,
            previewPass: .settled,
            readback: false
        )
        let reprintMs = PipelineStats.timings().fullPreviewMs
        let reprintStages = PipelineStats.stageTimings()
        let reprintCounters = PipelineStats.snapshot()

        NativePipeline.resetWorkingSets()
        PipelineStats.reset()
        let detectStart = CFAbsoluteTimeGetCurrent()
        _ = try pipeline.detectProcessMode(path: scan.path)
        let detectOnlyMs = (CFAbsoluteTimeGetCurrent() - detectStart) * 1000
        let afterDetect = PipelineStats.stageTimings()

        var frameSwitch: [String: Any]?
        if let second = secondScan {
            NativePipeline.resetWorkingSets()
            PipelineStats.reset()
            let switchStart = CFAbsoluteTimeGetCurrent()
            _ = try pipeline.detectProcessMode(path: second.path)
            _ = try pipeline.renderPrintDetailed(
                path: second.path,
                longEdgePx: longEdge,
                processMode: mode,
                config: config,
                previewPass: .settled,
                readback: false
            )
            let switchMs = (CFAbsoluteTimeGetCurrent() - switchStart) * 1000
            frameSwitch = [
                "total_ms": roundMs(switchMs),
                "stages": PipelineStats.stageTimings().dictionary().mapValues(roundMs),
                "counters": countersDict(PipelineStats.snapshot()),
            ]
        }

        let machine = ProcessInfo.processInfo.hostName
        let metal = MetalDevice.isAvailable

        return [
            "version": 1,
            "profile": "real_scan",
            "scan": scan.path,
            "second_scan": secondScan?.path as Any,
            "machine": machine,
            "metal_available": metal,
            "pixel_backend": pipeline.pixelBackend.resolved().rawValue,
            "scenarios": [
                "detect_only": [
                    "detect_ms": roundMs(detectOnlyMs),
                    "stages": afterDetect.dictionary().mapValues(roundMs),
                ],
                "cold_first_open": [
                    "total_ms": roundMs(coldTotalMs),
                    "draft_first_paint_ms": roundMs(draftMs),
                    "settled_full_preview_ms": roundMs(settledMs),
                    "draft_stages": draftStages.dictionary().mapValues(roundMs),
                    "draft_counters": countersDict(draftCounters),
                    "settled_stages": settledStages.dictionary().mapValues(roundMs),
                    "settled_counters": countersDict(settledCounters),
                ],
                "density_reprint": [
                    "full_preview_ms": roundMs(reprintMs),
                    "reused_bake": reprintResult.reusedBake,
                    "reused_analysis": reprintResult.reusedAnalysis,
                    "stages": reprintStages.dictionary().mapValues(roundMs),
                    "counters": countersDict(reprintCounters),
                ],
                "frame_switch": frameSwitch as Any,
            ],
            "s13l_hot_stages": s13lSummary(
                settled: settledStages,
                settledCounters: settledCounters
            ),
        ]
    }

    private static func s13lSummary(
        settled: PipelineStageTimings,
        settledCounters: PipelineStageCounters
    ) -> [String: Any] {
        let candidates: [(String, Double, Int)] = [
            ("dust", settled.dustMs, settledCounters.dust),
            ("autocrop", settled.autocropMs, settledCounters.autocrop),
            ("analyze", settled.analyzeMs, settledCounters.analyze),
        ]
        let total = settled.dustMs + settled.autocropMs + settled.analyzeMs
        let sorted = candidates.sorted { $0.1 > $1.1 }
        return [
            "dust_ms": roundMs(settled.dustMs),
            "autocrop_ms": roundMs(settled.autocropMs),
            "analyze_ms": roundMs(settled.analyzeMs),
            "combined_ms": roundMs(total),
            "decode_ms": roundMs(settled.decodeMs),
            "print_ms": roundMs(settled.printMs),
            "ranking": sorted.map { ["stage": $0.0, "ms": roundMs($0.1), "count": $0.2] },
        ]
    }

    private static func countersDict(_ counters: PipelineStageCounters) -> [String: Int] {
        [
            "decode": counters.decode,
            "dust": counters.dust,
            "heal": counters.heal,
            "autocrop": counters.autocrop,
            "orient": counters.orient,
            "analyze": counters.analyze,
            "print": counters.print,
            "upload": counters.upload,
            "download": counters.download,
            "present_encode": counters.presentEncode,
        ]
    }

    private static func roundMs(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func encodeJSON(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)! + "\n"
    }

    static func localScan() -> URL? {
        if let env = ProcessInfo.processInfo.environment["NEGSWIFT_PERF_SCAN"],
           FileManager.default.fileExists(atPath: env)
        {
            return URL(fileURLWithPath: env)
        }
        let preferred = URL(
            fileURLWithPath: "/Users/gacevedo/Downloads/Kodak Portra Gold 120 K6500-008.TIFF"
        )
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        return sampleTIFF()
    }

    static func localSecondScan() -> URL? {
        if let env = ProcessInfo.processInfo.environment["NEGSWIFT_PERF_SECOND_SCAN"],
           FileManager.default.fileExists(atPath: env)
        {
            return URL(fileURLWithPath: env)
        }
        return nil
    }

    private static func sampleTIFF() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("App/NegSwiftUITests/Fixtures/sample.tif")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
