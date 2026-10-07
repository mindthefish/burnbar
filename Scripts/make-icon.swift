#!/usr/bin/env swift
// Renders Assets/AppIcon.icns: three stacked quota bars on a dark rounded tile,
// using the same accent colours as the menu bar.
import AppKit
import Foundation

let accents: [(color: NSColor, fill: CGFloat)] = [
    (NSColor(srgbRed: 0.91, green: 0.43, blue: 0.02, alpha: 1), 0.66),
    (NSColor(srgbRed: 0.16, green: 0.76, blue: 0.44, alpha: 1), 0.30),
    (NSColor(srgbRed: 0.49, green: 0.20, blue: 0.91, alpha: 1), 0.88)
]

func renderIcon(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let bitmap = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    // Tile: macOS icons sit inside a rounded square with a margin.
    let inset = size * 0.06
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.width * 0.22)
    NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
    tilePath.fill()

    let barHeight = tile.height * 0.13
    let gap = tile.height * 0.09
    let block = 3 * barHeight + 2 * gap
    let left = tile.minX + tile.width * 0.16
    let width = tile.width * 0.68
    var top = tile.midY + block / 2 - barHeight

    for accent in accents {
        let track = NSRect(x: left, y: top, width: width, height: barHeight)
        let radius = barHeight / 2
        accent.color.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let fill = NSRect(x: left, y: top, width: width * accent.fill, height: barHeight)
        accent.color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()

        top -= barHeight + gap
    }

    context.flushGraphics()
    return bitmap.representation(using: .png, properties: [:])
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = repoRoot.appendingPathComponent("Assets/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(base * scale)
        guard let data = renderIcon(size: pixels) else {
            FileHandle.standardError.write(Data("error: could not render \(pixels)px\n".utf8))
            exit(1)
        }
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(base)x\(base)\(suffix).png"
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

print("wrote \(iconset.path)")
