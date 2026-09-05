/// Scene-linear interleaved RGB float32 buffer in [0, 1].
///
/// S0: allocated by the stub pipeline. S1 fills this from ImageIO.
public struct LinearRGBBuffer: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// `width * height * 3` samples, row-major RGB.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(width > 0 && height > 0, "LinearRGBBuffer size must be positive")
        precondition(
            pixels.count == width * height * 3,
            "LinearRGBBuffer expected \(width * height * 3) samples, got \(pixels.count)"
        )
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Mid-gray placeholder used until S1 decode lands.
    public static func stub(width: Int, height: Int, gray: Float = 0.5) -> LinearRGBBuffer {
        let count = width * height * 3
        return LinearRGBBuffer(width: width, height: height, pixels: [Float](repeating: gray, count: count))
    }

    public var sampleCount: Int { pixels.count }
}
