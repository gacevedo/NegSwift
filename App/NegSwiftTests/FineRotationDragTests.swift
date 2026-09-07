//
//  FineRotationDragTests.swift
//  NegSwiftTests
//

import CoreGraphics
import Testing
@testable import NegSwift

struct FineRotationDragTests {
    @Test func rotationDragAngleFollowsCursorLikeAWheel() {
        let center = CGPoint.zero
        let press = CGPoint(x: 100, y: 0)

        #expect(abs(FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: CGPoint(x: 100, y: -100)
        ) - 45.0) < 1e-9)

        #expect(abs(FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: CGPoint(x: 100, y: 100)
        ) - (-45.0)) < 1e-9)

        #expect(FineRotationDrag.rotationDragAngle(
            startAngleDeg: 2,
            center: center,
            press: press,
            cursor: CGPoint(x: 100, y: -100)
        ) == 45.0)

        let partial = FineRotationDrag.rotationDragAngle(
            startAngleDeg: 2,
            center: center,
            press: press,
            cursor: CGPoint(x: 100, y: -10)
        )
        #expect(abs(partial - (2 + atan2(10.0, 100.0) * 180 / Double.pi)) < 1e-9)
    }

    @Test func rotationDragAngleClampsToLimit() {
        let center = CGPoint.zero
        let press = CGPoint(x: 100, y: 0)

        #expect(FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: CGPoint(x: -10, y: -100)
        ) == FineRotationDrag.limit)

        #expect(FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: CGPoint(x: -10, y: 100)
        ) == -FineRotationDrag.limit)
    }

    @Test func rotationDragAngleRobustAcrossAtan2Seam() {
        let center = CGPoint.zero
        let angle = FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: CGPoint(x: -100, y: 1),
            cursor: CGPoint(x: -100, y: -1)
        )
        let expected = -atan2(1.0, 100.0) * 180 / Double.pi * 2
        #expect(abs(angle - expected) < 1e-6)
        #expect(abs(angle) < 2)
    }

    @Test func rotationDragAngleSensitivity() {
        let center = CGPoint.zero
        let press = CGPoint(x: 100, y: 0)
        let cursor = CGPoint(x: 100, y: -20)

        let full = FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: cursor
        )
        let fine = FineRotationDrag.rotationDragAngle(
            startAngleDeg: 0,
            center: center,
            press: press,
            cursor: cursor,
            sensitivity: FineRotationDrag.fineSensitivity
        )
        #expect(abs(fine - full * FineRotationDrag.fineSensitivity) < 1e-9)
    }
}
