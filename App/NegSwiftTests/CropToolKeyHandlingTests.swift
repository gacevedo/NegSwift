//
//  CropToolKeyHandlingTests.swift
//  NegSwiftTests
//

import Testing
@testable import NegSwift

struct CropToolKeyHandlingTests {
    @Test func returnKeyAppliesCrop() {
        #expect(CropToolKeyHandling.isApplyKey(36))
    }

    @Test func keypadEnterAppliesCrop() {
        #expect(CropToolKeyHandling.isApplyKey(76))
    }

    @Test func unrelatedKeysPassThrough() {
        #expect(!CropToolKeyHandling.isApplyKey(0))
        #expect(!CropToolKeyHandling.isApplyKey(53))
    }
}
