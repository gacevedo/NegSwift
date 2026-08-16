//
//  ScratchToolKeyHandlingTests.swift
//  NegSwiftTests
//

import Testing
@testable import NegSwift

struct ScratchToolKeyHandlingTests {
    @Test func returnKeyFinishesStroke() {
        #expect(ScratchToolKeyHandling.action(forKeyCode: 36) == .finish)
    }

    @Test func keypadEnterFinishesStroke() {
        #expect(ScratchToolKeyHandling.action(forKeyCode: 76) == .finish)
    }

    @Test func deleteKeyRemovesLastPoint() {
        #expect(ScratchToolKeyHandling.action(forKeyCode: 51) == .backspace)
    }

    @Test func escapeKeyCancelsOrExits() {
        #expect(ScratchToolKeyHandling.action(forKeyCode: 53) == .escape)
    }

    @Test func unrelatedKeysPassThrough() {
        #expect(ScratchToolKeyHandling.action(forKeyCode: 0) == nil)
        #expect(ScratchToolKeyHandling.action(forKeyCode: 49) == nil)
    }
}
