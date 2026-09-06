import Foundation

/// Viewport (display) ↔ source (raw) mapping via NegPy `uv_grid`.
///
/// The grid is source UV at each **output** pixel after rotation / flip / fine-rot / crop,
/// so a click on the preview samples the raw-frame coordinate stored there.
public struct UVGrid: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// Interleaved `(u, v)` source-normalized samples, row-major.
    public var uv: [SIMD2<Float>]

    public init(width: Int, height: Int, uv: [SIMD2<Float>]) {
        precondition(width > 0 && height > 0)
        precondition(uv.count == width * height)
        self.width = width
        self.height = height
        self.uv = uv
    }

    public subscript(x: Int, y: Int) -> SIMD2<Float> {
        uv[y * width + x]
    }
}

public enum CoordinateMapping: Sendable {
    /// NegPy `APP_CONFIG.preview_render_size` / `HEAL_SIZE_REF`.
    public static let previewLongEdge = 1600

    /// Preview-buffer size after NegPy `int(w * scale)` downsample.
    public static func previewGridSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > previewLongEdge else { return (width, height) }
        let scale = Double(previewLongEdge) / Double(longest)
        return (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
    }

    /// `CoordinateMapping.create_uv_grid` for the lite geometry set (no k1 / keystone).
    public static func createUVGrid(
        sourceWidth: Int,
        sourceHeight: Int,
        rotation: Int = 0,
        fineRotation: Float = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        cropRect: NormalizedCropRect? = nil,
        applyCrop: Bool = true
    ) -> UVGrid {
        let sized = previewGridSize(width: sourceWidth, height: sourceHeight)
        var grid = identityGrid(width: sized.width, height: sized.height)
        let turns = ((rotation % 4) + 4) % 4
        if turns != 0 {
            grid = rotatedQuarterTurnsCCW(grid, turns: turns)
        }
        if flipHorizontal {
            grid = flipped(grid, horizontal: true)
        }
        if flipVertical {
            grid = flipped(grid, horizontal: false)
        }
        if fineRotation != 0 {
            grid = fineRotated(grid, degrees: fineRotation)
        }
        if applyCrop, let cropRect {
            grid = cropped(grid, normalized: cropRect)
        }
        return grid
    }

    /// Viewport `(nx, ny)` in 0–1 display space → source-normalized `(u, v)`.
    public static func mapClickToRaw(nx: Double, ny: Double, grid: UVGrid) -> (Double, Double) {
        if nx >= 0, nx <= 1, ny >= 0, ny <= 1 {
            // NegPy: `uv_grid[int(ny * (h-1)), int(nx * (w-1))]`
            let ix = min(max(Int(nx * Double(grid.width - 1)), 0), grid.width - 1)
            let iy = min(max(Int(ny * Double(grid.height - 1)), 0), grid.height - 1)
            let sample = grid[ix, iy]
            return (Double(sample.x), Double(sample.y))
        }
        return applyHomography(gridHomography(grid), nx: nx, ny: ny)
    }

    public static func identityGrid(width: Int, height: Int) -> UVGrid {
        var uv = [SIMD2<Float>](repeating: .zero, count: width * height)
        let denomX = Float(max(width - 1, 1))
        let denomY = Float(max(height - 1, 1))
        for y in 0..<height {
            for x in 0..<width {
                uv[y * width + x] = SIMD2(Float(x) / denomX, Float(y) / denomY)
            }
        }
        return UVGrid(width: width, height: height, uv: uv)
    }

    /// Same index map as `LinearRGBBuffer.rotatedQuarterTurnsCCW` / `np.rot90`.
    public static func rotatedQuarterTurnsCCW(_ grid: UVGrid, turns: Int) -> UVGrid {
        let k = ((turns % 4) + 4) % 4
        if k == 0 { return grid }
        if k == 2 {
            return UVGrid(width: grid.width, height: grid.height, uv: grid.uv.reversed())
        }
        let srcW = grid.width
        let srcH = grid.height
        let dstW = srcH
        let dstH = srcW
        var out = [SIMD2<Float>](repeating: .zero, count: dstW * dstH)
        for y in 0..<srcH {
            for x in 0..<srcW {
                let dx: Int
                let dy: Int
                if k == 1 {
                    dx = y
                    dy = srcW - 1 - x
                } else {
                    dx = srcH - 1 - y
                    dy = x
                }
                out[dy * dstW + dx] = grid[x, y]
            }
        }
        return UVGrid(width: dstW, height: dstH, uv: out)
    }

    public static func flipped(_ grid: UVGrid, horizontal: Bool) -> UVGrid {
        var out = [SIMD2<Float>](repeating: .zero, count: grid.uv.count)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let sx = horizontal ? (grid.width - 1 - x) : x
                let sy = horizontal ? y : (grid.height - 1 - y)
                out[y * grid.width + x] = grid[sx, sy]
            }
        }
        return UVGrid(width: grid.width, height: grid.height, uv: out)
    }

    /// `cv2.getRotationMatrix2D` + `warpAffine` (`INTER_LINEAR`, constant 0 border).
    public static func fineRotated(_ grid: UVGrid, degrees: Float) -> UVGrid {
        if degrees == 0 { return grid }
        let theta = Double(degrees) * Double.pi / 180
        let cosine = cos(theta)
        let sine = sin(theta)
        let cx = Double(grid.width) / 2
        let cy = Double(grid.height) / 2
        var out = [SIMD2<Float>](repeating: .zero, count: grid.uv.count)
        let maxX = grid.width - 1
        let maxY = grid.height - 1
        for y in 0..<grid.height {
            let dy = Double(y) - cy
            for x in 0..<grid.width {
                let dx = Double(x) - cx
                // OpenCV: src = R(-θ) · (dest − c) + c
                let sx = cx + cosine * dx + sine * dy
                let sy = cy - sine * dx + cosine * dy
                out[y * grid.width + x] = sampleLinear(grid, sx: sx, sy: sy, maxX: maxX, maxY: maxY)
            }
        }
        return UVGrid(width: grid.width, height: grid.height, uv: out)
    }

    public static func cropped(_ grid: UVGrid, normalized rect: NormalizedCropRect) -> UVGrid {
        guard let roi = LinearRGBBuffer.storedCropPixelROI(
            width: grid.width,
            height: grid.height,
            rect: rect.tuple
        ) else {
            return grid
        }
        let newW = roi.x2 - roi.x1
        let newH = roi.y2 - roi.y1
        if newW == grid.width, newH == grid.height { return grid }
        var out = [SIMD2<Float>](repeating: .zero, count: newW * newH)
        for y in 0..<newH {
            for x in 0..<newW {
                out[y * newW + x] = grid[roi.x1 + x, roi.y1 + y]
            }
        }
        return UVGrid(width: newW, height: newH, uv: out)
    }

    private static func sampleLinear(
        _ grid: UVGrid,
        sx: Double,
        sy: Double,
        maxX: Int,
        maxY: Int
    ) -> SIMD2<Float> {
        if sx < 0 || sy < 0 || sx > Double(maxX) || sy > Double(maxY) {
            return .zero
        }
        let x0 = Int(floor(sx))
        let y0 = Int(floor(sy))
        let fx = Float(sx - Double(x0))
        let fy = Float(sy - Double(y0))
        let x1 = min(x0 + 1, maxX)
        let y1 = min(y0 + 1, maxY)
        let p00 = grid[x0, y0]
        let p10 = grid[x1, y0]
        let p01 = grid[x0, y1]
        let p11 = grid[x1, y1]
        return p00 * (1 - fx) * (1 - fy)
            + p10 * fx * (1 - fy)
            + p01 * (1 - fx) * fy
            + p11 * fx * fy
    }

    /// NegPy `_grid_homography`: four interior samples, viewport 0–1 → raw 0–1.
    public static func gridHomography(_ grid: UVGrid) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        let w = grid.width
        let h = grid.height
        let x0 = w / 4
        let x1 = w - 1 - w / 4
        let y0 = h / 4
        let y1 = h - 1 - h / 4
        let src: [(Double, Double)] = [
            (Double(x0) / Double(w - 1), Double(y0) / Double(h - 1)),
            (Double(x1) / Double(w - 1), Double(y0) / Double(h - 1)),
            (Double(x1) / Double(w - 1), Double(y1) / Double(h - 1)),
            (Double(x0) / Double(w - 1), Double(y1) / Double(h - 1)),
        ]
        let dst: [(Double, Double)] = [
            pair(grid[x0, y0]),
            pair(grid[x1, y0]),
            pair(grid[x1, y1]),
            pair(grid[x0, y1]),
        ]
        return perspectiveTransform(from: src, to: dst)
    }

    public static func applyHomography(
        _ m: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>),
        nx: Double,
        ny: Double
    ) -> (Double, Double) {
        let den = m.2.x * nx + m.2.y * ny + m.2.z
        if abs(den) < 1e-12 { return (nx, ny) }
        return (
            (m.0.x * nx + m.0.y * ny + m.0.z) / den,
            (m.1.x * nx + m.1.y * ny + m.1.z) / den
        )
    }

    private static func pair(_ v: SIMD2<Float>) -> (Double, Double) {
        (Double(v.x), Double(v.y))
    }

    /// `cv2.getPerspectiveTransform` (h22 = 1) via 8×8 DLT.
    static func perspectiveTransform(
        from src: [(Double, Double)],
        to dst: [(Double, Double)]
    ) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        var a = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var b = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let (x, y) = src[i]
            let (u, v) = dst[i]
            a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y]
            b[i * 2] = u
            a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y]
            b[i * 2 + 1] = v
        }
        let h = solve8(a, b) ?? [1, 0, 0, 0, 1, 0, 0, 0]
        return (
            SIMD3(h[0], h[1], h[2]),
            SIMD3(h[3], h[4], h[5]),
            SIMD3(h[6], h[7], 1)
        )
    }

    private static func solve8(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        let n = 8
        for k in 0..<n {
            var pivot = k
            var best = abs(a[k][k])
            for i in (k + 1)..<n {
                let v = abs(a[i][k])
                if v > best {
                    best = v
                    pivot = i
                }
            }
            if best < 1e-14 { return nil }
            if pivot != k {
                a.swapAt(k, pivot)
                b.swapAt(k, pivot)
            }
            let diag = a[k][k]
            for j in k..<n {
                a[k][j] /= diag
            }
            b[k] /= diag
            for i in 0..<n where i != k {
                let f = a[i][k]
                for j in k..<n {
                    a[i][j] -= f * a[k][j]
                }
                b[i] -= f * b[k]
            }
        }
        return b
    }
}
