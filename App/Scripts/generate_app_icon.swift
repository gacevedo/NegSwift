#!/usr/bin/env swift

import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_32@1x.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_256@1x.png", 256),
    ("icon_512.png", 512),
    ("icon_512@1x.png", 512),
    ("icon_1024.png", 1024),
]

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2237
    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1).setFill()
    background.fill()

    let symbolPointSize = size * 0.44
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
    if
        let symbol = NSImage(systemSymbolName: "film", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    {
        let symbolSize = symbol.size
        let drawRect = NSRect(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate_app_icon", code: 1)
    }
    try png.write(to: url)
}

for entry in sizes {
    let url = outputDir.appendingPathComponent(entry.name)
    try writePNG(renderIcon(pixels: entry.pixels), to: url)
    print("Wrote \(url.path)")
}
