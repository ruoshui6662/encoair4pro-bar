import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let width = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: width * 0.05, y: width * 0.05, width: width * 0.9, height: width * 0.9), xRadius: width * 0.21, yRadius: width * 0.21)
        NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.67, blue: 0.48, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.39, blue: 0.29, alpha: 1))!.draw(in: tile, angle: -70)
        let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: width * 0.5, weight: .regular))!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        let iconSize = symbol.size
        let ratio = min(width * 0.57 / iconSize.width, width * 0.62 / iconSize.height)
        let rect = NSRect(x: (width - iconSize.width * ratio) / 2, y: (width - iconSize.height * ratio) / 2,
                          width: iconSize.width * ratio, height: iconSize.height * ratio)
        symbol.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS supports PNG-backed large icon entries; package them without iconutil's XPC dependency.
var entries = Data()
for (tag, filename) in [("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"),
                        ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(filename))
    entries.append(Data(tag.utf8))
    var length = UInt32(png.count + 8).bigEndian
    withUnsafeBytes(of: &length) { entries.append(contentsOf: $0) }
    entries.append(png)
}
var result = Data("icns".utf8)
var length = UInt32(entries.count + 8).bigEndian
withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
result.append(entries)
try result.write(to: URL(fileURLWithPath: "Resources/AppIcon.icns"))
