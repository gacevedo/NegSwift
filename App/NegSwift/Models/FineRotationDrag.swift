//
//  FineRotationDrag.swift
//  NegSwift
//

import CoreGraphics
import Foundation

enum FineRotationDrag {
    static let limit = EditControlRanges.fineRotation.upperBound
    static let fineSensitivity = 0.2

    /// Signed fine-rotation angle for a crop-tool rotation-handle drag.
    static func rotationDragAngle(
        startAngleDeg: Double,
        center: CGPoint,
        press: CGPoint,
        cursor: CGPoint,
        sensitivity: Double = 1.0,
        limit: Double = Self.limit
    ) -> Double {
        let a0 = atan2(Double(press.y - center.y), Double(press.x - center.x))
        let a1 = atan2(Double(cursor.y - center.y), Double(cursor.x - center.x))
        let delta = atan2(sin(a1 - a0), cos(a1 - a0)) * 180 / Double.pi
        let newAngle = startAngleDeg - delta * sensitivity
        return min(max(newAngle, -limit), limit)
    }
}
