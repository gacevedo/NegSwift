//
//  DebounceSchedulerTests.swift
//  NegSwiftTests
//

import Testing
@testable import NegSwift

@MainActor
struct DebounceSchedulerTests {
    @Test func coalescesRapidCalls() async {
        let scheduler = DebounceScheduler(interval: .milliseconds(50))
        var count = 0
        for _ in 0 ..< 5 {
            scheduler.schedule {
                count += 1
            }
        }
        for _ in 0 ..< 50 {
            if count == 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(count == 1)
    }
}
