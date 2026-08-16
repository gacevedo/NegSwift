//
//  PerformanceLogger.swift
//  NegSwift
//

import Foundation
import os

/// Debug-only timing for M12 baselines. Enable with env `NEGSWIFT_PERF_LOG=1`.
enum PerformanceLogger {
    private static let log = Logger(subsystem: "com.negswift", category: "perf")

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NEGSWIFT_PERF_LOG"] == "1"
        #else
        false
        #endif
    }

    static func event(_ label: String, milliseconds: Double) {
        guard isEnabled else { return }
        log.info("[perf] \(label, privacy: .public): \(milliseconds, format: .fixed(precision: 2)) ms")
    }

    static func measureSync<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
        guard isEnabled else { return try work() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try work()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        event(label, milliseconds: ms)
        return result
    }

    static func measure<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        guard isEnabled else { return try await work() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await work()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        event(label, milliseconds: ms)
        return result
    }
}
