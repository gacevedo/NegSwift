//
//  UITestSupportTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct UITestSupportTests {
    @Test func scratchSeedPointsParsesPipeSeparatedPairs() {
        let points = UITestSupport.parseScratchSeedPoints("0.2,0.3|0.8,0.7")
        #expect(points?.count == 2)
        #expect(points?[0].x == 0.2)
        #expect(points?[0].y == 0.3)
        #expect(points?[1].x == 0.8)
        #expect(points?[1].y == 0.7)
    }

    @Test func scratchSeedPointsRejectsMalformedInput() {
        #expect(UITestSupport.parseScratchSeedPoints("") == nil)
        #expect(UITestSupport.parseScratchSeedPoints("0.5") == nil)
        #expect(UITestSupport.parseScratchSeedPoints("bad,data") == nil)
    }
}
