import Foundation

/// Minimal uncompressed RGB TIFF writer for goldens (no ICC). 16-bit stays linear.
public enum UncompressedTIFF: Sendable {
    public static func writeRGB16(width: Int, height: Int, samples: [UInt16], to url: URL) throws {
        precondition(samples.count == width * height * 3)
        var data = Data()
        // II little-endian TIFF
        data.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        let ifdOffset = 8
        appendU32(&data, UInt32(ifdOffset))

        let bitsPerSampleOffset = 8 + 2 + 11 * 12 + 4
        let stripOffset = bitsPerSampleOffset + 6
        let stripBytes = width * height * 6

        var ifd = Data()
        appendU16(&ifd, 11)
        writeEntry(&ifd, tag: 256, type: 3, count: 1, value: UInt32(width))
        writeEntry(&ifd, tag: 257, type: 3, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 258, type: 3, count: 3, value: UInt32(bitsPerSampleOffset))
        writeEntry(&ifd, tag: 259, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 262, type: 3, count: 1, value: 2)
        writeEntry(&ifd, tag: 273, type: 4, count: 1, value: UInt32(stripOffset))
        writeEntry(&ifd, tag: 277, type: 3, count: 1, value: 3)
        writeEntry(&ifd, tag: 278, type: 4, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 279, type: 4, count: 1, value: UInt32(stripBytes))
        writeEntry(&ifd, tag: 284, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 296, type: 3, count: 1, value: 2)
        appendU32(&ifd, 0)

        data.append(ifd)
        appendU16(&data, 16)
        appendU16(&data, 16)
        appendU16(&data, 16)
        for sample in samples {
            appendU16(&data, sample)
        }
        try data.write(to: url, options: .atomic)
    }

    /// LinearRaw DNG for S14 CI (photometric 34892 + DNGVersion). LibRaw rejects edges under 22.
    public static func writeLinearRawDNG16(width: Int, height: Int, samples: [UInt16], to url: URL) throws {
        precondition(samples.count == width * height * 3)
        var data = Data()
        data.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        appendU32(&data, 8)
        let entryCount = 14
        let bitsPerSampleOffset = 8 + 2 + entryCount * 12 + 4
        let stripOffset = bitsPerSampleOffset + 6
        let stripBytes = width * height * 6
        var ifd = Data()
        appendU16(&ifd, UInt16(entryCount))
        writeEntry(&ifd, tag: 254, type: 4, count: 1, value: 0)
        writeEntry(&ifd, tag: 256, type: 3, count: 1, value: UInt32(width))
        writeEntry(&ifd, tag: 257, type: 3, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 258, type: 3, count: 3, value: UInt32(bitsPerSampleOffset))
        writeEntry(&ifd, tag: 259, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 262, type: 3, count: 1, value: 34892)
        writeEntry(&ifd, tag: 273, type: 4, count: 1, value: UInt32(stripOffset))
        writeEntry(&ifd, tag: 274, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 277, type: 3, count: 1, value: 3)
        writeEntry(&ifd, tag: 278, type: 4, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 279, type: 4, count: 1, value: UInt32(stripBytes))
        writeEntry(&ifd, tag: 284, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 296, type: 3, count: 1, value: 2)
        writeEntry(&ifd, tag: 50706, type: 1, count: 4, value: 0x0000_0401)
        appendU32(&ifd, 0)
        data.append(ifd)
        appendU16(&data, 16)
        appendU16(&data, 16)
        appendU16(&data, 16)
        for sample in samples {
            appendU16(&data, sample)
        }
        try data.write(to: url, options: .atomic)
    }

    public static func writeRGB8(width: Int, height: Int, samples: [UInt8], to url: URL) throws {
        precondition(samples.count == width * height * 3)
        var data = Data()
        data.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        appendU32(&data, 8)
        let stripOffset = 8 + 2 + 11 * 12 + 4
        let stripBytes = width * height * 3
        var ifd = Data()
        appendU16(&ifd, 11)
        writeEntry(&ifd, tag: 256, type: 3, count: 1, value: UInt32(width))
        writeEntry(&ifd, tag: 257, type: 3, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 258, type: 3, count: 1, value: 8)
        writeEntry(&ifd, tag: 259, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 262, type: 3, count: 1, value: 2)
        writeEntry(&ifd, tag: 273, type: 4, count: 1, value: UInt32(stripOffset))
        writeEntry(&ifd, tag: 277, type: 3, count: 1, value: 3)
        writeEntry(&ifd, tag: 278, type: 4, count: 1, value: UInt32(height))
        writeEntry(&ifd, tag: 279, type: 4, count: 1, value: UInt32(stripBytes))
        writeEntry(&ifd, tag: 284, type: 3, count: 1, value: 1)
        writeEntry(&ifd, tag: 296, type: 3, count: 1, value: 2)
        appendU32(&ifd, 0)
        data.append(ifd)
        data.append(contentsOf: samples)
        try data.write(to: url, options: .atomic)
    }

    private static func writeEntry(_ data: inout Data, tag: UInt16, type: UInt16, count: UInt32, value: UInt32) {
        appendU16(&data, tag)
        appendU16(&data, type)
        appendU32(&data, count)
        appendU32(&data, value)
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: 2))
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: 4))
    }
}
