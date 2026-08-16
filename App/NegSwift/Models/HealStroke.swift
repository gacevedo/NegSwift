//
//  HealStroke.swift
//  NegSwift
//

import Foundation

struct HealStrokePoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
}

/// NegPy ``manual_heal_strokes`` entry: ``[[nx, ny], ...], size, 0.0, 0.0`` in source space.
struct HealStroke: Equatable, Codable, Sendable {
    var points: [HealStrokePoint]
    var size: Double

    init(points: [HealStrokePoint], size: Double) {
        self.points = points
        self.size = size
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let rawPoints = try container.decode([[Double]].self)
        points = rawPoints.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return HealStrokePoint(x: pair[0], y: pair[1])
        }
        size = try container.decode(Double.self)
        _ = try container.decode(Double.self)
        _ = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(points.map { [$0.x, $0.y] })
        try container.encode(size)
        try container.encode(0.0)
        try container.encode(0.0)
    }

    static func fromFlatValue(_ value: Any?) -> [HealStroke] {
        guard let rows = value as? [Any] else { return [] }
        var strokes: [HealStroke] = []
        for row in rows {
            guard let tuple = row as? [Any], tuple.count >= 2 else { continue }
            guard let rawPoints = tuple[0] as? [Any] else { continue }
            let size = double(tuple[1], default: 6)
            var points: [HealStrokePoint] = []
            for pt in rawPoints {
                guard let pair = pt as? [Any], pair.count >= 2 else { continue }
                points.append(HealStrokePoint(x: double(pair[0]), y: double(pair[1])))
            }
            guard !points.isEmpty else { continue }
            strokes.append(HealStroke(points: points, size: size))
        }
        return strokes
    }

    private static func double(_ value: Any?, default defaultValue: Double = 0) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return defaultValue
    }
}
