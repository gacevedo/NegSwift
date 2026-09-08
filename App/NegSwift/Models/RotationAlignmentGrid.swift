//
//  RotationAlignmentGrid.swift
//  NegSwift
//

import CoreGraphics
import SwiftUI

enum RotationAlignmentGrid {
    static let divisions = 10
    static let lineOpacity = 70.0 / 255.0

    static func interiorFractions(divisions: Int) -> [CGFloat] {
        guard divisions > 1 else { return [] }
        return (1..<divisions).map { CGFloat($0) / CGFloat(divisions) }
    }
}

struct RotationAlignmentGridView: View {
    let rect: CGRect
    var divisions: Int = RotationAlignmentGrid.divisions
    var lineOpacity: Double = RotationAlignmentGrid.lineOpacity

    var body: some View {
        Path { path in
            for fraction in RotationAlignmentGrid.interiorFractions(divisions: divisions) {
                let x = rect.minX + rect.width * fraction
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(lineOpacity), lineWidth: 1)
        .allowsHitTesting(false)
        .accessibilityIdentifier("negSwift.rotationAlignmentGrid")
    }
}
