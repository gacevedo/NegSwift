//
//  NormalizedRect.swift
//  NegSwift
//

import Foundation

/// Normalized crop bounds in transformed image space — ``(x1, y1, x2, y2)``, each 0…1.
struct NormalizedRect: Equatable, Sendable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    var width: Double { x2 - x1 }
    var height: Double { y2 - y1 }

    static let full = NormalizedRect(x1: 0, y1: 0, x2: 1, y2: 1)

    init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = min(x1, x2)
        self.y1 = min(y1, y2)
        self.x2 = max(x1, x2)
        self.y2 = max(y1, y2)
    }

    func clamped() -> NormalizedRect {
        let w = min(width, 1)
        let h = min(height, 1)
        let nx1 = min(max(x1, 0), 1 - w)
        let ny1 = min(max(y1, 0), 1 - h)
        return NormalizedRect(x1: nx1, y1: ny1, x2: nx1 + w, y2: ny1 + h)
    }

    func arrayValue() -> [Double] { [x1, y1, x2, y2] }

    static func fromFlatValue(_ value: Any?) -> NormalizedRect? {
        guard let parts = value as? [Any], parts.count == 4 else { return nil }
        let nums = parts.compactMap { item -> Double? in
            if let d = item as? Double { return d }
            if let i = item as? Int { return Double(i) }
            if let n = item as? NSNumber { return n.doubleValue }
            return nil
        }
        guard nums.count == 4 else { return nil }
        return NormalizedRect(x1: nums[0], y1: nums[1], x2: nums[2], y2: nums[3])
    }

    /// Match NegPy ``mirror_normalized_rect`` — mirror across vertical (horizontal) or horizontal (vertical) center.
    func mirrored(horizontal: Bool) -> NormalizedRect {
        if horizontal {
            return NormalizedRect(x1: 1 - x2, y1: y1, x2: 1 - x1, y2: y2)
        }
        return NormalizedRect(x1: x1, y1: 1 - y2, x2: x2, y2: 1 - y1)
    }

    /// Match NegPy ``rotate_normalized_rect`` — quarter-turns CCW on normalized UV.
    func rotated(quarterTurnsCCW: Int) -> NormalizedRect {
        var corners: [(Double, Double)] = [
            (x1, y1), (x2, y1), (x2, y2), (x1, y2),
        ]
        let turns = ((quarterTurnsCCW % 4) + 4) % 4
        for _ in 0 ..< turns {
            corners = corners.map { (u, v) in (v, 1 - u) }
        }
        let xs = corners.map(\.0)
        let ys = corners.map(\.1)
        return NormalizedRect(
            x1: xs.min() ?? 0,
            y1: ys.min() ?? 0,
            x2: xs.max() ?? 1,
            y2: ys.max() ?? 1
        )
    }

    /// Centered crop rect matching ``ratioLabel`` within the unit square; ``imageAspect`` is width/height in pixels.
    static func centered(ratioLabel: String, imageAspect: Double) -> NormalizedRect {
        let ratio = CropAspectRatio.canonical(ratioLabel)
        guard let widthOverHeight = ratio.widthOverHeight else { return .full }
        let target = widthOverHeight / max(imageAspect, 0.01)
        var w = 1.0
        var h = w / target
        if h > 1 {
            h = 1
            w = h * target
        }
        let x1 = (1 - w) / 2
        let y1 = (1 - h) / 2
        return NormalizedRect(x1: x1, y1: y1, x2: x1 + w, y2: y1 + h).clamped()
    }

    /// Closest film-format ratio label for this rect — mirrors NegPy ``detect_closest_aspect_ratio``.
    func closestFilmAspectRatioLabel(imageAspect: Double) -> String {
        let detected = (width / max(height, 1e-6)) * max(imageAspect, 1e-6)
        let filmRatios: [CropAspectRatio] = [.r1x1, .r3x2, .r4x3, .r5x4, .r6x7, .r7x5, .r65x24]

        var bestRatio = CropAspectRatio.r3x2
        var bestDistance = Double.infinity
        for ratio in filmRatios {
            guard let widthOverHeight = ratio.widthOverHeight else { continue }
            let targets = ratio == .r1x1 ? [1.0] : [widthOverHeight, 1.0 / widthOverHeight]
            for target in targets {
                let distance = abs(log(max(detected, 1e-6)) - log(max(target, 1e-6)))
                if distance < bestDistance {
                    bestDistance = distance
                    bestRatio = ratio
                }
            }
        }

        if bestDistance > 0.15 {
            return CropAspectRatio.free.rawValue
        }
        return bestRatio.rawValue
    }
}

enum CropAspectRatio: String, CaseIterable, Identifiable {
    case free = "Free"
    case r1x1 = "1:1"
    case r3x2 = "3:2"
    case r4x3 = "4:3"
    case r5x4 = "5:4"
    case r4x5 = "4:5"
    case r6x7 = "6:7"
    case r7x5 = "7:5"
    case r65x24 = "65:24"
    case r16x9 = "16:9"
    case r9x16 = "9:16"
    case r191x100 = "1.91:1"
    case r16x10 = "16:10"
    case r85x11 = "8.5:11"

    var id: String { rawValue }

    /// Menu label for the crop ratio picker (Instagram ratios use feed/story naming).
    var pickerLabel: String {
        switch self {
        case .r1x1: "1:1 · Instagram"
        case .r4x5: "4:5 · Instagram"
        case .r9x16: "9:16 · Instagram"
        case .r191x100: "1.91:1 · Instagram"
        default: rawValue
        }
    }

    var widthOverHeight: Double? {
        switch self {
        case .free: nil
        case .r1x1: 1
        case .r3x2: 3.0 / 2.0
        case .r4x3: 4.0 / 3.0
        case .r5x4: 5.0 / 4.0
        case .r4x5: 4.0 / 5.0
        case .r6x7: 6.0 / 7.0
        case .r7x5: 7.0 / 5.0
        case .r65x24: 65.0 / 24.0
        case .r16x9: 16.0 / 9.0
        case .r9x16: 9.0 / 16.0
        case .r191x100: 1.91
        case .r16x10: 16.0 / 10.0
        case .r85x11: 8.5 / 11.0
        }
    }

    static func parse(_ label: String) -> CropAspectRatio? {
        allCases.first { $0.rawValue == label }
    }

    static func canonical(_ label: String) -> CropAspectRatio {
        let portraitMap: [String: CropAspectRatio] = [
            "2:3": .r3x2, "3:4": .r4x3, "7:6": .r6x7,
            "5:7": .r7x5, "24:65": .r65x24, "100:191": .r191x100,
            "10:16": .r16x10, "11:8.5": .r85x11,
        ]
        if let mapped = portraitMap[label] { return mapped }
        return parse(label) ?? .r3x2
    }
}
