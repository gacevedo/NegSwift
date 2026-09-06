import Foundation

/// One `manual_heal_strokes` entry: source-normalized polyline + brush diameter.
public struct HealStroke: Sendable, Equatable {
    public var points: [HealPoint]
    public var size: Double

    public init(points: [HealPoint], size: Double) {
        self.points = points
        self.size = size
    }

    public func jsonTuple() -> [Any] {
        [points.map { [$0.x, $0.y] }, size, 0.0, 0.0]
    }

    public static func parseList(_ value: Any?) -> [HealStroke] {
        guard let rows = value as? [Any] else { return [] }
        var strokes: [HealStroke] = []
        for row in rows {
            guard let tuple = row as? [Any], tuple.count >= 2 else { continue }
            guard let rawPoints = tuple[0] as? [Any] else { continue }
            let size = ConfigJSON.doubleValue(tuple[1]) ?? 6
            var points: [HealPoint] = []
            for pt in rawPoints {
                guard let pair = pt as? [Any], pair.count >= 2,
                      let x = ConfigJSON.doubleValue(pair[0]),
                      let y = ConfigJSON.doubleValue(pair[1])
                else { continue }
                points.append(HealPoint(x: x, y: y))
            }
            guard !points.isEmpty else { continue }
            strokes.append(HealStroke(points: points, size: size))
        }
        return strokes
    }
}

public struct HealPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Legacy `manual_dust_spots` `(nx, ny, size)`.
public struct HealSpot: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
    }

    public func jsonTuple() -> [Any] {
        [x, y, size]
    }

    public static func parseList(_ value: Any?) -> [HealSpot] {
        guard let rows = value as? [Any] else { return [] }
        var spots: [HealSpot] = []
        for row in rows {
            guard let tuple = row as? [Any], tuple.count >= 3,
                  let x = ConfigJSON.doubleValue(tuple[0]),
                  let y = ConfigJSON.doubleValue(tuple[1]),
                  let size = ConfigJSON.doubleValue(tuple[2])
            else { continue }
            spots.append(HealSpot(x: x, y: y, size: size))
        }
        return spots
    }
}
