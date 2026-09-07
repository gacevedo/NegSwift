import Foundation
import Testing
@testable import NegSwiftEngine

/// S13i is PPG + a shared libraw handle, with OpenMP left on.
/// Pinning `OMP_NUM_THREADS=1` made a RAF click slower and is not the production path.
///
/// Skip-if-missing local X-Trans. Not part of `make compare-s13` (too slow).
/// `swift test --filter XTransPreviewTimingTests`
@Suite(.serialized)
struct XTransPreviewTimingTests {
    @Test(.enabled(if: RawDecode.isAvailable && XTransPreviewTimingTests.localRAF() != nil))
    func oneThreadPPGIsTheRegressionOpenMPPPGIsTheWin() throws {
        guard let url = Self.localRAF() else { return }
        let cores = max(2, RawDecode.openMPProcCount)
        defer { restoreLibRaw() }

        let ahdMulti = try timePreviewDemosaic(url: url, demosaic: .ahd, threads: cores)
        let ppgOne = try timePreviewDemosaic(url: url, demosaic: .ppg, threads: 1)
        let ppgMulti = try timePreviewDemosaic(url: url, demosaic: .ppg, threads: cores)

        print(
            """
            XTransPreviewTiming demosaic \(url.lastPathComponent):
              AHD  \(cores) threads (pre-S13i preview): \(fmt(ahdMulti)) s
              PPG  1 thread  (do not ship):             \(fmt(ppgOne)) s
              PPG  \(cores) threads (S13i production):  \(fmt(ppgMulti)) s
            """
        )

        #expect(
            ppgOne > ahdMulti * 1.2,
            "1-thread PPG is why the RAF click got slower (got PPG1=\(fmt(ppgOne))s AHD\(cores)=\(fmt(ahdMulti))s)"
        )
        #expect(
            ppgMulti < ahdMulti,
            "PPG with OpenMP should beat pre-S13i AHD (got PPG=\(fmt(ppgMulti))s AHD=\(fmt(ahdMulti))s)"
        )
    }

    @Test(.enabled(if: RawDecode.isAvailable && XTransPreviewTimingTests.localRAF() != nil))
    func ppgOpenMPFirstOpenBeatsPreS13iAhd() throws {
        guard let url = Self.localRAF() else { return }
        let cores = max(2, RawDecode.openMPProcCount)
        defer { restoreLibRaw() }

        let pre = try timeFirstOpen(url: url, demosaic: .ahd, threads: cores)
        let s13i = try timeFirstOpen(url: url, demosaic: .ppg, threads: cores)

        print(
            """
            XTransPreviewTiming first-open no sidecar \(url.lastPathComponent):
              AHD  \(cores) threads (pre-S13i): \(fmt(pre)) s
              PPG  \(cores) threads (S13i):     \(fmt(s13i)) s
            """
        )

        #expect(
            s13i < pre,
            "No-sidecar RAF first open should be faster with PPG+OpenMP (got S13i=\(fmt(s13i))s pre=\(fmt(pre))s)"
        )
    }

    private func restoreLibRaw() {
        LinearDecode.previewDemosaicOverride = nil
        RawDecode.setOpenMPThreads(max(1, RawDecode.openMPProcCount))
        NativePipeline.resetWorkingSets()
    }

    private func timePreviewDemosaic(url: URL, demosaic: RawDecode.Demosaic, threads: Int) throws -> Double {
        RawDecode.setOpenMPThreads(threads)
        NativePipeline.resetWorkingSets()
        let start = CFAbsoluteTimeGetCurrent()
        let result = try RawDecode.decodeDetailed(url: url, halfSize: true, demosaic: demosaic)
        let seconds = CFAbsoluteTimeGetCurrent() - start
        #expect(result.isXTrans)
        #expect(result.demosaic == demosaic)
        #expect(!result.usedHalfSize)
        return seconds
    }

    private func timeFirstOpen(url: URL, demosaic: RawDecode.Demosaic, threads: Int) throws -> Double {
        RawDecode.setOpenMPThreads(threads)
        LinearDecode.previewDemosaicOverride = demosaic
        NativePipeline.resetWorkingSets()
        var armed = PrintConfig.s8Pin
        armed.autoCropEnabled = true
        armed.cropFromAuto = true
        let pipeline = NativePipeline(pixelBackend: .auto)
        let start = CFAbsoluteTimeGetCurrent()
        _ = try pipeline.detectProcessMode(path: url.path)
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: PreviewPass.draftLongEdge,
            processMode: .colorNegative,
            config: armed,
            previewPass: .draft
        )
        _ = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: Int(Autocrop.previewRenderSize),
            processMode: .colorNegative,
            config: armed,
            previewPass: .settled
        )
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func fmt(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }

    static func localRAF() -> URL? {
        let preferred = URL(fileURLWithPath: "/Users/gacevedo/Downloads/sample-raw-scans/_DSF9243.RAF")
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        return RawDecodeTests.localXTrans()
    }
}
