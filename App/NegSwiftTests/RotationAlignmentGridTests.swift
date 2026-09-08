//
//  RotationAlignmentGridTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct RotationAlignmentGridTests {
    @Test func interiorFractionsMatchNegPyTenByTenGrid() {
        let fractions = RotationAlignmentGrid.interiorFractions(divisions: 10)
        #expect(fractions.count == 9)
        #expect(fractions.first == 0.1)
        #expect(fractions.last == 0.9)
    }

    @Test func interiorFractionsEmptyForSingleDivision() {
        #expect(RotationAlignmentGrid.interiorFractions(divisions: 1).isEmpty)
        #expect(RotationAlignmentGrid.interiorFractions(divisions: 0).isEmpty)
    }
}
