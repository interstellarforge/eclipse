// Draws the Lumacut app icon: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func icon(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), r = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let body = NSBezierPath(roundedRect: r, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.55, green: 0.36, blue: 0.97, alpha: 1), NSColor(red: 0.13, green: 0.10, blue: 0.30, alpha: 1)])!.draw(in: body, angle: -60)
    body.addClip()
    // light sweep
    let sweep = NSBezierPath(); sweep.move(to: NSPoint(x: 0, y: s * 0.62)); sweep.line(to: NSPoint(x: s, y: s * 0.95)); sweep.line(to: NSPoint(x: s, y: s)); sweep.line(to: NSPoint(x: 0, y: s)); sweep.close()
    NSColor.white.withAlphaComponent(0.10).setFill(); sweep.fill()
    // play triangle cut by a diagonal "cut" line
    let t = NSBezierPath()
    t.move(to: NSPoint(x: s * 0.38, y: s * 0.28)); t.line(to: NSPoint(x: s * 0.38, y: s * 0.72)); t.line(to: NSPoint(x: s * 0.74, y: s * 0.50)); t.close()
    NSColor.white.setFill(); t.fill()
    let cut = NSBezierPath(); cut.move(to: NSPoint(x: s * 0.30, y: s * 0.22)); cut.line(to: NSPoint(x: s * 0.70, y: s * 0.80)); cut.lineWidth = s * 0.035
    NSColor(red: 0.30, green: 0.18, blue: 0.62, alpha: 1).setStroke(); cut.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1], dir = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! icon(px).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", dir, "-o", out]; try! p.run(); p.waitUntilExit()
