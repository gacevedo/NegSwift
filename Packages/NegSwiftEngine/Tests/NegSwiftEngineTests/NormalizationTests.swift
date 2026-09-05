import Foundation
import Testing
@testable import NegSwiftEngine

struct NormalizationTests {
    @Test func unclampedOutOfBoundsHigh() {
        let floors = (-1.0, -1.0, -1.0)
        let ceils = (-0.2, -0.2, -0.2)
        let bounds = LogNegativeBounds(floors: floors, ceils: ceils)
        let linear = filled(width: 4, height: 4, value: Float(pow(10.0, -0.1)))
        let res = LogNormalization.process(linear: linear, bounds: bounds)
        #expect(res.pixels[0] > 1)
        #expect(abs(res.pixels[0] - 1.125) < 1e-5)
        #expect(abs(res.pixels[1] - 1.125) < 1e-5)
        #expect(abs(res.pixels[2] - 1.125) < 1e-5)
    }

    @Test func unclampedOutOfBoundsLow() {
        let bounds = LogNegativeBounds(
            floors: (-1.0, -1.0, -1.0),
            ceils: (-0.2, -0.2, -0.2)
        )
        let linear = filled(width: 4, height: 4, value: Float(pow(10.0, -1.5)))
        let res = LogNormalization.process(linear: linear, bounds: bounds)
        #expect(res.pixels[0] < 0)
        #expect(abs(res.pixels[0] - (-0.625)) < 1e-5)
    }

    @Test func explicitBoundsMidtoneIsHalf() {
        let bounds = LogNegativeBounds(
            floors: (-0.5, -0.5, -0.5),
            ceils: (-0.1, -0.1, -0.1)
        )
        let linear = filled(width: 10, height: 10, value: Float(pow(10.0, -0.3)))
        let res = LogNormalization.process(linear: linear, bounds: bounds)
        #expect(abs(res.pixels[0] - 0.5) < 1e-5)
    }

    @Test func percentileFromSortedMatchesNumpy() {
        let sorted = [0.0, 3.0, 6.0, 9.0]
        #expect(abs(LogNormalization.percentileFromSorted(sorted, q: 0.01) - 0.0009) < 1e-12)
        #expect(abs(LogNormalization.percentileFromSorted(sorted, q: 1) - 0.09) < 1e-12)
        #expect(abs(LogNormalization.percentileFromSorted(sorted, q: 50) - 4.5) < 1e-12)
        #expect(abs(LogNormalization.percentileFromSorted(sorted, q: 99) - 8.91) < 1e-12)
        #expect(abs(LogNormalization.percentileFromSorted(sorted, q: 99.99) - 8.9991) < 1e-12)
    }

    @Test func blockMedianOfFour() {
        var pixels = [Float](repeating: 0, count: 6 * 6 * 3)
        for y in 0..<6 {
            for x in 0..<6 {
                let v = Float(y * 10 + x)
                let i = (y * 6 + x) * 3
                pixels[i] = v
                pixels[i + 1] = v + 0.5
                pixels[i + 2] = v + 1
            }
        }
        let grid = LogNormalization.blockMedianGrid(
            LinearRGBBuffer(width: 6, height: 6, pixels: pixels),
            analysisGrid: 3
        )
        #expect(grid.width == 3)
        #expect(grid.height == 3)
        #expect(abs(grid.pixels[0] - 5.5) < 1e-6)
        #expect(abs(grid.pixels[1] - 6.0) < 1e-6)
        #expect(abs(grid.pixels[2] - 6.5) < 1e-6)
        #expect(abs(grid.pixels[3] - 7.5) < 1e-6)
        #expect(abs(grid.pixels[9] - 25.5) < 1e-6)
    }

    @Test func c41SyntheticNeutralizesOrangeAndStaysUninverted() {
        let linear = c41Synthetic()
        let bounds = LogNormalization.analyzeBounds(
            linear: linear,
            processMode: .colorNegative,
            analysisBuffer: 0.05
        )
        #expect(abs(bounds.floors.0 - (-0.7933626572291057)) < 1e-5)
        #expect(abs(bounds.floors.1 - (-1.0586770574251811)) < 1e-5)
        #expect(abs(bounds.floors.2 - (-1.4343406955401103)) < 1e-5)
        #expect(abs(bounds.ceils.0 - (-0.5212529500325521)) < 1e-5)
        #expect(abs(bounds.ceils.1 - (-0.7865674098332723)) < 1e-5)
        #expect(abs(bounds.ceils.2 - (-1.1622310479482016)) < 1e-5)

        let res = LogNormalization.process(
            linear: linear,
            processMode: .colorNegative,
            analysisBuffer: 0.05
        )
        let means = channelMeans(res)
        #expect(abs(means.0 - means.1) < 1e-5)
        #expect(abs(means.1 - means.2) < 1e-5)
        #expect(abs(means.0 - 0.6094989) < 1e-4)

        let linMeans = channelMeans(linear)
        #expect(linMeans.0 - linMeans.2 > 0.1)

        let center = pixel(res, x: 20, y: 16)
        let corner = pixel(res, x: 0, y: 0)
        #expect(center.0 < corner.0)
        #expect(abs(center.0 - 0.13517743) < 1e-5)
        #expect(abs(corner.0 - 1.2708814) < 1e-5)

        let mid = pixel(res, x: 15, y: 10)
        #expect(abs(mid.0 - 0.27545845) < 1e-5)
    }

    @Test func e6SwapsPolaritySoHighlightsStayBright() {
        var pixels = [Float](repeating: 0.1, count: 2 * 1 * 3)
        pixels[3] = 0.9
        pixels[4] = 0.9
        pixels[5] = 0.9
        let linear = LinearRGBBuffer(width: 2, height: 1, pixels: pixels)
        let bounds = LogNormalization.analyzeBounds(
            linear: linear,
            processMode: .transparency,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0
        )
        #expect(abs(bounds.floors.0 - (-0.045)) < 0.1)
        #expect(abs(bounds.ceils.0 - (-1.0)) < 0.1)

        let res = LogNormalization.process(
            linear: linear,
            processMode: .transparency,
            analysisBuffer: 0,
            lumaRangeClip: 0,
            colorRangeClip: 0,
            bounds: bounds
        )
        #expect(abs(res.pixels[3] - 0) < 0.05)
        #expect(abs(res.pixels[0] - 1) < 0.05)
    }

    @Test func bwKeepsChannelsEqual() {
        var pixels = [Float](repeating: 0, count: 32 * 32 * 3)
        for i in 0..<(32 * 32) {
            let g = 0.05 + 0.9 * Float(i) / Float(32 * 32 - 1)
            pixels[i * 3] = g
            pixels[i * 3 + 1] = g
            pixels[i * 3 + 2] = g
        }
        let linear = LinearRGBBuffer(width: 32, height: 32, pixels: pixels)
        let res = LogNormalization.process(linear: linear, processMode: .bwNegative, analysisBuffer: 0)
        for i in 0..<(32 * 32) {
            #expect(abs(res.pixels[i * 3] - res.pixels[i * 3 + 1]) < 1e-5)
            #expect(abs(res.pixels[i * 3 + 1] - res.pixels[i * 3 + 2]) < 1e-5)
        }
        #expect(res.pixels[0] < res.pixels[(32 * 32 - 1) * 3])
    }

    @Test func analysisBufferZeroReadsFullFrame() {
        var pixels = [Float](repeating: 0.2, count: 40 * 40 * 3)
        for y in 0..<40 {
            for x in 0..<40 {
                let i = (y * 40 + x) * 3
                let border = y < 6 || y >= 34 || x < 6 || x >= 34
                if border {
                    pixels[i] = 0.95
                    pixels[i + 1] = 0.95
                    pixels[i + 2] = 0.95
                }
            }
        }
        let linear = LinearRGBBuffer(width: 40, height: 40, pixels: pixels)
        let full = LogNormalization.analyzeBounds(linear: linear, analysisBuffer: 0, colorRangeClip: 0)
        let inset = LogNormalization.analyzeBounds(linear: linear, analysisBuffer: 0.2, colorRangeClip: 0)
        #expect(abs(full.ceils.0 - inset.ceils.0) > 1e-4)
    }

    @Test func logDensityClampsHighAndSanitizesNonFinite() {
        var pixels = [Float](repeating: 0.5, count: 8 * 1 * 3)
        pixels[0] = .nan
        pixels[3] = .infinity
        pixels[6] = -.infinity
        pixels[9] = 0
        pixels[12] = 1
        pixels[15] = 2
        pixels[18] = -5
        pixels[21] = 1e30
        let linear = LinearRGBBuffer(width: 8, height: 1, pixels: pixels)
        let clamped = LogNormalization.toLogDensity(linear)
        let openHigh = LogNormalization.toLogDensityUnclampedHigh(linear)
        let clampedFinite = clamped.pixels.allSatisfy { $0.isFinite }
        let openHighFinite = openHigh.pixels.allSatisfy { $0.isFinite }
        #expect(clampedFinite)
        #expect(openHighFinite)
        #expect(abs(clamped.pixels[15] - 0) < 1e-6)
        #expect(openHigh.pixels[15] > 0)
    }

    @Test func nearZeroDenomDoesNotNaN() {
        let bounds = LogNegativeBounds(floors: (-0.5, -0.5, -0.5), ceils: (-0.5, -0.5, -0.5))
        let linear = filled(width: 2, height: 2, value: 0.3)
        let res = LogNormalization.process(linear: linear, bounds: bounds)
        let finite = res.pixels.allSatisfy { $0.isFinite }
        #expect(finite)
    }

    @Test func blockMedianGeneralPathAndIdentityBelowGrid() {
        var pixels = [Float](repeating: 0, count: 8 * 8 * 3)
        for y in 0..<8 {
            for x in 0..<8 {
                let i = (y * 8 + x) * 3
                let v = Float(y * 8 + x)
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            }
        }
        let img = LinearRGBBuffer(width: 8, height: 8, pixels: pixels)
        let grid = LogNormalization.blockMedianGrid(img, analysisGrid: 2)
        #expect(grid.width == 2)
        #expect(grid.height == 2)
        #expect(abs(grid.pixels[0] - 13.5) < 1e-5)

        let small = LogNormalization.blockMedianGrid(img, analysisGrid: 1024)
        #expect(small.width == 8)
        #expect(small.pixels == img.pixels)
    }

    @Test func percentileEmptyAndSingleton() {
        #expect(LogNormalization.percentileFromSorted([], q: 50) == 0)
        #expect(LogNormalization.percentileFromSorted([7], q: 99) == 7)
    }

    private func filled(width: Int, height: Int, value: Float) -> LinearRGBBuffer {
        LinearRGBBuffer(
            width: width,
            height: height,
            pixels: [Float](repeating: value, count: width * height * 3)
        )
    }

    private func c41Synthetic() -> LinearRGBBuffer {
        let height = 32
        let width = 40
        var pixels = [Float](repeating: 0, count: width * height * 3)
        let cy = Double(height - 1) / 2
        let cx = Double(width - 1) / 2
        for y in 0..<height {
            for x in 0..<width {
                let dist = pow((Double(y) - cy) / Double(height), 2) + pow((Double(x) - cx) / Double(width), 2)
                let t = 0.25 + 0.55 * dist
                let i = (y * width + x) * 3
                pixels[i] = Float(min(1, max(1e-6, 0.70 * t)))
                pixels[i + 1] = Float(min(1, max(1e-6, 0.38 * t)))
                pixels[i + 2] = Float(min(1, max(1e-6, 0.16 * t)))
            }
        }
        return LinearRGBBuffer(width: width, height: height, pixels: pixels)
    }

    private func channelMeans(_ buffer: LinearRGBBuffer) -> (Float, Float, Float) {
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        let n = buffer.width * buffer.height
        for i in 0..<n {
            r += buffer.pixels[i * 3]
            g += buffer.pixels[i * 3 + 1]
            b += buffer.pixels[i * 3 + 2]
        }
        let count = Float(n)
        return (r / count, g / count, b / count)
    }

    private func pixel(_ buffer: LinearRGBBuffer, x: Int, y: Int) -> (Float, Float, Float) {
        let i = (y * buffer.width + x) * 3
        return (buffer.pixels[i], buffer.pixels[i + 1], buffer.pixels[i + 2])
    }
}
