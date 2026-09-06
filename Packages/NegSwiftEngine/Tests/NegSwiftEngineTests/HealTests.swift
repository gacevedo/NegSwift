import Foundation
import Testing
@testable import NegSwiftEngine

struct HealTests {
    @Test func identityMappingLeavesViewportPoints() {
        let grid = CoordinateMapping.createUVGrid(sourceWidth: 48, sourceHeight: 32)
        let p = CoordinateMapping.mapClickToRaw(nx: 0.25, ny: 0.5, grid: grid)
        #expect(abs(p.0 - 0.25) < 0.05)
        #expect(abs(p.1 - 0.5) < 0.05)
    }

    @Test func rotationChangesMapping() {
        let viewport = (0.5, 0.25)
        let identity = CoordinateMapping.createUVGrid(sourceWidth: 48, sourceHeight: 32, rotation: 0)
        let rotated = CoordinateMapping.createUVGrid(sourceWidth: 48, sourceHeight: 32, rotation: 1)
        let p0 = CoordinateMapping.mapClickToRaw(nx: viewport.0, ny: viewport.1, grid: identity)
        let p1 = CoordinateMapping.mapClickToRaw(nx: viewport.0, ny: viewport.1, grid: rotated)
        #expect(hypot(p0.0 - p1.0, p0.1 - p1.1) > 0.02)
    }

    @Test func flipHorizontalMirrorsSourceU() {
        let grid = CoordinateMapping.createUVGrid(
            sourceWidth: 40,
            sourceHeight: 40,
            flipHorizontal: true
        )
        let p = CoordinateMapping.mapClickToRaw(nx: 0.25, ny: 0.5, grid: grid)
        #expect(abs(p.0 - 0.75) < 0.05)
        #expect(abs(p.1 - 0.5) < 0.05)
    }

    @Test func appendHealStrokeMapsIdentityViaProtocol() throws {
        let frame = try writeHealTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let line = """
        {"id":"heal-id","method":"append_heal_stroke","params":{"path":"\(frame.path)","points":[[0.25,0.5],[0.75,0.5]],"brush_size":6,"config":{"rotation":0}}}
        """
        let msg = server.handleMessage(line)
        #expect(msg["ok"] as? Bool == true)
        let strokes = (msg["result"] as? [String: Any])?["manual_heal_strokes"] as? [Any]
        #expect(strokes?.count == 1)
        let stroke = strokes?[0] as? [Any]
        let mapped = stroke?[0] as? [[Double]]
        #expect(mapped?.count == 2)
        #expect(abs((mapped?[0][0] ?? -1) - 0.25) < 0.05)
        #expect(abs((mapped?[0][1] ?? -1) - 0.5) < 0.05)
        #expect((stroke?[1] as? NSNumber)?.doubleValue == 6)
    }

    @Test func appendHealStrokeRotationChangesMappingViaProtocol() throws {
        let frame = try writeHealTIFF(width: 48, height: 32)
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let base = server.handleMessage(
            """
            {"id":"heal-rot0","method":"append_heal_stroke","params":{"path":"\(frame.path)","points":[[0.5,0.25]],"config":{"rotation":0}}}
            """
        )
        let rotated = server.handleMessage(
            """
            {"id":"heal-rot1","method":"append_heal_stroke","params":{"path":"\(frame.path)","points":[[0.5,0.25]],"config":{"rotation":1}}}
            """
        )
        #expect(base["ok"] as? Bool == true)
        #expect(rotated["ok"] as? Bool == true)
        let p0 = firstMappedPoint(base)
        let p1 = firstMappedPoint(rotated)
        #expect(hypot(p0.0 - p1.0, p0.1 - p1.1) > 0.02)
    }

    @Test func appendHealStrokeRejectsEmptyPoints() throws {
        let frame = try writeHealTIFF(width: 8, height: 8)
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let msg = server.handleMessage(
            """
            {"id":"heal-empty","method":"append_heal_stroke","params":{"path":"\(frame.path)","points":[]}}
            """
        )
        #expect(msg["ok"] as? Bool == false)
        #expect((msg["error"] as? [String: Any])?["code"] as? String == "INVALID_REQUEST")
    }

    @Test func undoLastHealRemovesStroke() throws {
        let frame = try writeHealTIFF(width: 8, height: 8)
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let appended = server.handleMessage(
            """
            {"id":"undo-setup","method":"append_heal_stroke","params":{"path":"\(frame.path)","points":[[0.2,0.2],[0.8,0.8]],"brush_size":6}}
            """
        )
        let strokes = (appended["result"] as? [String: Any])?["manual_heal_strokes"] as? [Any] ?? []
        let payload: [String: Any] = [
            "id": "undo-stroke",
            "method": "undo_last_heal",
            "params": [
                "path": frame.path,
                "config": ["manual_heal_strokes": strokes],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let line = String(data: data, encoding: .utf8)!
        let msg = server.handleMessage(line)
        #expect(msg["ok"] as? Bool == true)
        #expect((msg["result"] as? [String: Any])?["removed"] as? String == "stroke")
        #expect(((msg["result"] as? [String: Any])?["manual_heal_strokes"] as? [Any])?.isEmpty == true)
    }

    @Test func brushRepairsBrightSpeckAndLeavesOutsideUntouched() {
        var pixels = grainy(width: 100, height: 100, level: 0.5, sigma: 0.01, seed: 21)
        for y in 49..<52 {
            for x in 49..<52 {
                let i = (y * 100 + x) * 3
                pixels[i] = 0.95
                pixels[i + 1] = 0.95
                pixels[i + 2] = 0.95
            }
        }
        let image = LinearRGBBuffer(width: 100, height: 100, pixels: pixels)
        let size = HealInpaint.sizeAtRef(diameterPx: 15, width: 100, height: 100)
        let out = HealInpaint.bake(
            image,
            strokes: [HealStroke(points: [HealPoint(x: 0.5, y: 0.5)], size: size)]
        )
        var repairedMax: Float = 0
        for y in 49..<52 {
            for x in 49..<52 {
                let i = (y * 100 + x) * 3
                repairedMax = max(repairedMax, out.pixels[i], out.pixels[i + 1], out.pixels[i + 2])
            }
        }
        #expect(repairedMax < 0.7)
        // Outside the painted capsule the source must stay byte-identical.
        // In-brush clean grain depends on the exact grain field (NegPy uses
        // numpy PCG64); different noise can put a 2σ bump on the ring.
        for y in 0..<100 {
            for x in 0..<100 {
                let dist = hypot(Double(x) - 50, Double(y) - 50)
                if dist > 9 {
                    let i = (y * 100 + x) * 3
                    #expect(out.pixels[i] == image.pixels[i])
                    #expect(out.pixels[i + 1] == image.pixels[i + 1])
                    #expect(out.pixels[i + 2] == image.pixels[i + 2])
                }
            }
        }
    }

    @Test func brushRepairsBrightScratch() {
        var pixels = grainy(width: 160, height: 100, level: 0.5, sigma: 0.01, seed: 21)
        for x in 30..<130 {
            for y in 58..<61 {
                let i = (y * 160 + x) * 3
                pixels[i] = 0.85
                pixels[i + 1] = 0.85
                pixels[i + 2] = 0.85
            }
        }
        let image = LinearRGBBuffer(width: 160, height: 100, pixels: pixels)
        let size = HealInpaint.sizeAtRef(diameterPx: 10, width: 160, height: 100)
        let out = HealInpaint.bake(
            image,
            strokes: [HealStroke(
                points: [
                    HealPoint(x: 30.0 / 160, y: 59.0 / 100),
                    HealPoint(x: 80.0 / 160, y: 59.0 / 100),
                    HealPoint(x: 129.0 / 160, y: 59.0 / 100),
                ],
                size: size
            )]
        )
        var errBefore: Double = 0
        var errAfter: Double = 0
        var count = 0
        for x in 30..<130 {
            for y in 58..<61 {
                let i = (y * 160 + x) * 3
                errBefore += abs(Double(image.pixels[i]) - 0.5)
                errAfter += abs(Double(out.pixels[i]) - 0.5)
                count += 1
            }
        }
        errBefore /= Double(count)
        errAfter /= Double(count)
        #expect(errAfter < errBefore * 0.2)
    }

    @Test func brushOnCleanFilmIsNoop() {
        let image = LinearRGBBuffer(
            width: 100,
            height: 100,
            pixels: grainy(width: 100, height: 100, level: 0.5, sigma: 0.01, seed: 21)
        )
        let size = HealInpaint.sizeAtRef(diameterPx: 15, width: 100, height: 100)
        let score = HealInpaint.strokesToScore(
            image,
            strokes: [HealStroke(points: [HealPoint(x: 0.5, y: 0.5)], size: size)],
            spots: []
        )
        #expect(score == nil)
    }

    @Test func healBakesBeforeGeometry() throws {
        var samples = [UInt16](repeating: 20_000, count: 40 * 24 * 3)
        for x in 18..<22 {
            for y in 10..<14 {
                let i = (y * 40 + x) * 3
                samples[i] = 60_000
                samples[i + 1] = 60_000
                samples[i + 2] = 60_000
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negswift-s10a-geo-\(UUID().uuidString).tif")
        try UncompressedTIFF.writeRGB16(width: 40, height: 24, samples: samples, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let nx = (20.0 + 0.5) / 40.0
        let ny = (12.0 + 0.5) / 24.0
        var config = PrintConfig.s8Pin
        config.healStrokes = [HealStroke(points: [HealPoint(x: nx, y: ny)], size: 40)]
        config.rotation = 1
        let pipeline = NativePipeline()
        let healed = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: config
        )
        var untouched = config
        untouched.healStrokes = []
        let base = try pipeline.renderPrint(
            path: url.path,
            longEdgePx: nil,
            processMode: .colorNegative,
            config: untouched
        )
        #expect(healed.pixels != base.pixels)
        #expect(healed.width == base.height || healed.width == base.width)
    }
}

private func firstMappedPoint(_ msg: [String: Any]) -> (Double, Double) {
    let strokes = (msg["result"] as? [String: Any])?["manual_heal_strokes"] as? [Any]
    let stroke = strokes?.first as? [Any]
    guard let rawPoints = stroke?.first as? [Any],
          let pair = rawPoints.first as? [Any],
          pair.count >= 2,
          let x = ConfigJSON.doubleValue(pair[0]),
          let y = ConfigJSON.doubleValue(pair[1])
    else {
        return (0, 0)
    }
    return (x, y)
}

private func writeHealTIFF(width: Int, height: Int) throws -> URL {
    let samples = [UInt16](repeating: 40_000, count: width * height * 3)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s10a-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: width, height: height, samples: samples, to: url)
    return url
}

private func grainy(width: Int, height: Int, level: Float, sigma: Float, seed: UInt64) -> [Float] {
    var rng = SplitMix64(seed: seed)
    var pixels = [Float](repeating: level, count: width * height * 3)
    for i in 0..<pixels.count {
        pixels[i] = level + rng.nextGaussian() * sigma
    }
    return pixels
}

private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextGaussian() -> Float {
        let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
        let u2 = Double(next() >> 11) / Double(1 << 53)
        return Float(sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2))
    }
}
