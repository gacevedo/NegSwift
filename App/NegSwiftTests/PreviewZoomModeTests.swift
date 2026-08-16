//
//  PreviewZoomModeTests.swift
//  NegSwiftTests
//

import Testing
@testable import NegSwift

@Suite struct PreviewZoomModeTests {
    @Test func toggleSwitchesBetweenFitAndOneToOne() {
        var mode = PreviewZoomMode.fit
        mode.toggle()
        #expect(mode == .oneToOne)
        mode.toggle()
        #expect(mode == .fit)
    }
}
