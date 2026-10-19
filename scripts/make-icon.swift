// Original Clipline artwork: selection corners around text, with one hanging tab.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let background = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 184, yRadius: 184)
NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.18, blue: 0.26, alpha: 1),
    ending: NSColor(srgbRed: 0.02, green: 0.07, blue: 0.15, alpha: 1))!
    .draw(in: background, angle: -90)
let mint = NSColor(srgbRed: 0.40, green: 0.94, blue: 0.78, alpha: 1)
mint.setStroke()
for (x, y, dx, dy) in [(280.0, 300.0, 1.0, 1.0), (744, 300, -1, 1),
                       (280, 724, 1, -1), (744, 724, -1, -1)] {
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: x, y: y + dy * 100))
    corner.line(to: NSPoint(x: x, y: y))
    corner.line(to: NSPoint(x: x + dx * 100, y: y))
    corner.lineWidth = 34
    corner.lineCapStyle = .round
    corner.lineJoinStyle = .round
    corner.stroke()
}
NSColor.white.setFill()
for (y, width) in [(580.0, 264.0), (490, 264), (400, 170)] {
    NSBezierPath(roundedRect: NSRect(x: 380, y: y, width: width, height: 30),
        xRadius: 15, yRadius: 15).fill()
}
mint.setFill()
NSBezierPath(roundedRect: NSRect(x: 482, y: 684, width: 60, height: 118),
    xRadius: 24, yRadius: 24).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
