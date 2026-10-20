// Builds app icons from the approved Eclipse artwork:
//   swift scripts/make-icon.swift Resources/Brand/icon.png Resources/AppIcon.icns Resources/AppLogo.png android/app/src/main/res/drawable-nodpi
import AppKit

let a = CommandLine.arguments
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
// the artwork's rounded tile sits inside a black frame: crop it, then re-cut the corners so the outside is transparent
let crop = src.cgImage!.cropping(to: CGRect(x: 66, y: 66, width: 1122, height: 1122))!

func render(_ px: Int, margin: CGFloat, rounded: Bool = true) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), r = NSRect(x: s * margin, y: s * margin, width: s * (1 - 2 * margin), height: s * (1 - 2 * margin))
    if rounded { NSBezierPath(roundedRect: r, xRadius: r.width * 0.23, yRadius: r.width * 0.23).addClip() }
    NSGraphicsContext.current!.cgContext.draw(crop, in: r)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func write(_ d: Data, _ path: String) { try! d.write(to: URL(fileURLWithPath: path)) }

let dir = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    write(render(px, margin: 0.06), "\(dir)/icon_\(name).png")
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", dir, "-o", a[2]]; try! p.run(); p.waitUntilExit()
write(render(256, margin: 0), a[3])
write(render(432, margin: 0.14), a[4] + "/ic_launcher_foreground.png")   // adaptive foreground: tile inside the safe zone
write(render(192, margin: 0), a[4] + "/logo_tile.png")
