import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: make_app_icon.swift <output.iconset> <emoji>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let emoji = arguments[2]
let fm = FileManager.default

try? fm.removeItem(at: outputURL)
try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()

    let tileRect = rect.insetBy(dx: CGFloat(pixels) * 0.055, dy: CGFloat(pixels) * 0.055)
    let cornerRadius = CGFloat(pixels) * 0.215
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Bee-themed gradient (warm yellow → amber)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowBlurRadius = CGFloat(pixels) * 0.040
    tileShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.018)
    tileShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.22)
    tileShadow.set()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.66, blue: 0.10, alpha: 1)
    ])
    gradient?.draw(in: tile, angle: -28)
    NSGraphicsContext.restoreGraphicsState()

    // Soft diagonal honey stripes inside the tile (low contrast, just texture)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    let stripeSpacing = CGFloat(pixels) * 0.16
    let stripeWidth = CGFloat(pixels) * 0.018
    let count = Int(ceil(CGFloat(pixels) * 2 / stripeSpacing))
    for i in -count...count {
        let path = NSBezierPath()
        path.lineWidth = stripeWidth
        let offset = CGFloat(i) * stripeSpacing
        path.move(to: NSPoint(x: -CGFloat(pixels) + offset, y: -CGFloat(pixels)))
        path.line(to: NSPoint(x: CGFloat(pixels) * 2 + offset, y: CGFloat(pixels) * 2))
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Subtle inner highlight on top edge
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let highlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.30),
        NSColor(calibratedWhite: 1.0, alpha: 0.0)
    ])
    let highlightRect = NSRect(
        x: tileRect.origin.x,
        y: tileRect.origin.y + tileRect.height * 0.55,
        width: tileRect.width,
        height: tileRect.height * 0.45
    )
    highlight?.draw(in: highlightRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Emoji centered, sized ~62% of icon
    let emojiSize = CGFloat(pixels) * 0.62
    let font = NSFont(name: "Apple Color Emoji", size: emojiSize)
        ?? NSFont.systemFont(ofSize: emojiSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let textSize = str.size()
    // Slight optical centering nudge: emoji has internal padding, lift a hair.
    let drawRect = NSRect(
        x: (size.width - textSize.width) / 2,
        y: (size.height - textSize.height) / 2 - CGFloat(pixels) * 0.005,
        width: textSize.width,
        height: textSize.height
    )

    NSGraphicsContext.saveGraphicsState()
    let emojiShadow = NSShadow()
    emojiShadow.shadowBlurRadius = CGFloat(pixels) * 0.025
    emojiShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.010)
    emojiShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.30)
    emojiShadow.set()
    str.draw(in: drawRect)
    NSGraphicsContext.restoreGraphicsState()

    return image
}

for size in sizes {
    let image = drawIcon(pixels: size.pixels)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        fputs("failed to render \(size.name)\n", stderr)
        exit(1)
    }
    let url = outputURL.appendingPathComponent(size.name)
    try png.write(to: url)
}

print("wrote 10 icon sizes to \(outputURL.path)")
