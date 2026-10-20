import AVFoundation
import CoreGraphics
import Foundation

typealias RGB = (CGFloat, CGFloat, CGFloat)
let W = 1280, H = 720

private func col(_ c: RGB, _ a: CGFloat = 1) -> CGColor { CGColor(red: c.0, green: c.1, blue: c.2, alpha: a) }
private let space = CGColorSpaceCreateDeviceRGB()

private func vgrad(_ c: CGContext, _ rect: CGRect, _ stops: [(CGFloat, RGB)]) {
    let g = CGGradient(colorsSpace: space, colors: stops.map { col($0.1) } as CFArray, locations: stops.map { $0.0 })!
    c.saveGState(); c.clip(to: rect)
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    c.restoreGState()
}

private func glow(_ c: CGContext, _ center: CGPoint, _ radius: CGFloat, _ color: RGB, _ alpha: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: [col(color, alpha), col(color, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

private func hills(_ c: CGContext, base: CGFloat, amp: CGFloat, freq: CGFloat, drift: CGFloat, color: RGB) {
    let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: CGFloat(H)))
    var x: CGFloat = 0
    while x <= CGFloat(W) + 8 { p.addLine(to: CGPoint(x: x, y: base + amp * sin((x + drift) * freq) + amp * 0.4 * sin((x + drift) * freq * 2.3 + 1))); x += 8 }
    p.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); p.closeSubpath()
    c.setFillColor(col(color)); c.addPath(p); c.fillPath()
}

private func balloon(_ c: CGContext, x: CGFloat, y: CGFloat, color: RGB) {
    c.setStrokeColor(col((0.1, 0.08, 0.12), 0.7)); c.setLineWidth(2)
    c.move(to: CGPoint(x: x, y: y + 40)); c.addCurve(to: CGPoint(x: x + 6, y: y + 130), control1: CGPoint(x: x - 12, y: y + 70), control2: CGPoint(x: x + 14, y: y + 100)); c.strokePath()
    glow(c, CGPoint(x: x, y: y), 90, color, 0.25)
    c.setFillColor(col(color)); c.fillEllipse(in: CGRect(x: x - 30, y: y - 40, width: 60, height: 80))
    c.setFillColor(col((1, 1, 1), 0.35)); c.fillEllipse(in: CGRect(x: x - 16, y: y - 26, width: 14, height: 22))
}

private func rnd(_ n: Int) -> CGFloat { let x = sin(Double(n) * 127.1 + 311.7) * 43758.5453; return CGFloat(x - floor(x)) }

enum Scene: String, CaseIterable {
    case sunset, ocean, city, forest

    func draw(_ c: CGContext, t: CGFloat) {
        let w = CGFloat(W), h = CGFloat(H)
        switch self {
        case .sunset:
            vgrad(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, (0.10, 0.08, 0.32)), (0.45, (0.62, 0.22, 0.52)), (0.72, (1.0, 0.55, 0.32)), (1, (1.0, 0.80, 0.48))])
            let sun = CGPoint(x: w * 0.68, y: h * (0.50 + 0.025 * t))
            glow(c, sun, 380, (1.0, 0.7, 0.4), 0.7); c.setFillColor(col((1, 0.94, 0.68))); c.fillEllipse(in: CGRect(x: sun.x - 74, y: sun.y - 74, width: 148, height: 148))
            for i in 0..<5 {
                let bx = (CGFloat(i) * 210 + t * 55).truncatingRemainder(dividingBy: w + 120) - 60, by = 120 + CGFloat(i) * 38 + 12 * sin(t * 3 + CGFloat(i))
                let flap = 6 * sin(t * 9 + CGFloat(i) * 2)
                c.setStrokeColor(col((0.12, 0.07, 0.2))); c.setLineWidth(3); c.move(to: CGPoint(x: bx - 14, y: by - flap)); c.addQuadCurve(to: CGPoint(x: bx, y: by), control: CGPoint(x: bx - 6, y: by - 8 - flap)); c.addQuadCurve(to: CGPoint(x: bx + 14, y: by - flap), control: CGPoint(x: bx + 6, y: by - 8 - flap)); c.strokePath()
            }
            hills(c, base: h * 0.74, amp: 26, freq: 0.006, drift: t * 8, color: (0.30, 0.13, 0.33))
            hills(c, base: h * 0.82, amp: 30, freq: 0.0045, drift: t * 16, color: (0.16, 0.08, 0.26))
            hills(c, base: h * 0.92, amp: 22, freq: 0.0035, drift: t * 30, color: (0.07, 0.04, 0.15))
            balloon(c, x: w * 0.26 + 26 * sin(t * 1.4), y: h * 0.78 - 54 * t, color: (0.9, 0.12, 0.20))
        case .ocean:
            vgrad(c, CGRect(x: 0, y: 0, width: w, height: h * 0.58), [(0, (0.02, 0.04, 0.16)), (1, (0.08, 0.20, 0.42))])
            for i in 0..<90 { let a = rnd(i), b = rnd(i + 500); c.setFillColor(col((1, 1, 1), 0.3 + 0.6 * abs(sin(t * 2 + CGFloat(i))))); c.fillEllipse(in: CGRect(x: a * w, y: b * h * 0.5, width: 2.4, height: 2.4)) }
            let moon = CGPoint(x: w * 0.30, y: h * 0.22 + 4 * t)
            glow(c, moon, 260, (0.7, 0.85, 1), 0.55); c.setFillColor(col((0.95, 0.97, 1))); c.fillEllipse(in: CGRect(x: moon.x - 52, y: moon.y - 52, width: 104, height: 104))
            vgrad(c, CGRect(x: 0, y: h * 0.58, width: w, height: h * 0.42), [(0, (0.06, 0.18, 0.36)), (1, (0.01, 0.05, 0.14))])
            for row in 0..<26 {
                let y = h * 0.58 + CGFloat(row * row) * 0.62 + 6, spread = 30 + CGFloat(row) * 7
                let reflect = abs(sin(t * 2 + CGFloat(row) * 0.7)) * (spread * 1.2)
                c.setFillColor(col((0.8, 0.92, 1), max(0, 0.55 - CGFloat(row) * 0.018))); c.fill(CGRect(x: moon.x - reflect / 2 + 14 * sin(t * 1.8 + CGFloat(row)), y: y, width: reflect, height: 2 + CGFloat(row) * 0.18))
                c.setFillColor(col((0.4, 0.6, 0.9), 0.10)); c.fill(CGRect(x: (CGFloat(row) * 97 + t * 40).truncatingRemainder(dividingBy: w), y: y + 8, width: 150 + spread, height: 2))
            }
            balloon(c, x: w * 0.78 + 20 * sin(t * 1.1), y: h * 0.62 - 40 * t, color: (1.0, 0.55, 0.12))
        case .city:
            vgrad(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, (0.03, 0.03, 0.14)), (0.7, (0.20, 0.10, 0.38)), (1, (0.55, 0.20, 0.45))])
            for layer in 0..<2 {
                var x: CGFloat = -CGFloat(Int(t * (layer == 0 ? 6 : 14)) % 120)
                var i = layer * 40
                while x < w {
                    let bw = 70 + rnd(i) * 90, bh = (layer == 0 ? 160 : 90) + rnd(i + 9) * (layer == 0 ? 280 : 200)
                    c.setFillColor(col(layer == 0 ? (0.07, 0.06, 0.20) : (0.04, 0.03, 0.12))); c.fill(CGRect(x: x, y: h - bh - (layer == 0 ? 60 : 0), width: bw, height: bh + 60))
                    var wy = h - bh - (layer == 0 ? 60 : 0) + 18
                    var r = 0
                    while wy < h - 50 { var wx = x + 10; var k = 0; while wx < x + bw - 14 { let on = rnd(i * 31 + r * 7 + k) > 0.45 + 0.1 * sin(t * 0.9 + CGFloat(r + k)); if on { c.setFillColor(col((1, 0.82, 0.45), layer == 0 ? 0.85 : 0.6)); c.fill(CGRect(x: wx, y: wy, width: 9, height: 12)) }; wx += 20; k += 1 }; wy += 26; r += 1 }
                    x += bw + 6; i += 1
                }
            }
            c.setFillColor(col((0.02, 0.02, 0.07))); c.fill(CGRect(x: 0, y: h - 62, width: w, height: 62))
            for car in 0..<6 {
                let cx = (CGFloat(car) * 260 + t * (car % 2 == 0 ? 220 : -180)).truncatingRemainder(dividingBy: w + 200); let x = cx < 0 ? cx + w + 200 : cx
                let warm: RGB = car % 2 == 0 ? (1, 0.3, 0.3) : (1, 0.95, 0.75)
                glow(c, CGPoint(x: x, y: h - 30 - CGFloat(car % 2) * 14), 70, warm, 0.6)
                c.setFillColor(col(warm)); c.fillEllipse(in: CGRect(x: x - 5, y: h - 34 - CGFloat(car % 2) * 14, width: 10, height: 8))
            }
        case .forest:
            vgrad(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, (0.55, 0.86, 0.78)), (0.5, (0.82, 0.93, 0.62)), (1, (0.98, 0.95, 0.60))])
            let sun = CGPoint(x: w * 0.8, y: h * 0.16 + 6 * t)
            glow(c, sun, 340, (1, 1, 0.8), 0.8)
            for ray in 0..<7 { c.saveGState(); c.translateBy(x: sun.x, y: sun.y); c.rotate(by: 0.3 + CGFloat(ray) * 0.16 + 0.03 * sin(t + CGFloat(ray))); c.setFillColor(col((1, 1, 0.85), 0.08)); c.fill(CGRect(x: -22, y: 0, width: 44, height: 900)); c.restoreGState() }
            for layer in 0..<3 {
                let shade: CGFloat = 0.34 - CGFloat(layer) * 0.12, speed: CGFloat = 10 + CGFloat(layer) * 22, size: CGFloat = 150 + CGFloat(layer) * 90, baseY = h * (0.72 + CGFloat(layer) * 0.10)
                var x: CGFloat = -size - CGFloat(Int(t * speed) % Int(size))
                var i = layer * 50
                while x < w + size {
                    let th = size * (1.1 + rnd(i) * 0.7)
                    c.setFillColor(col((0.05 + shade * 0.2, 0.22 + shade * 0.6, 0.12 + shade * 0.25)))
                    for tier in 0..<4 { let ty = baseY - CGFloat(tier) * th * 0.22, tw = size * (0.62 - CGFloat(tier) * 0.12); c.move(to: CGPoint(x: x - tw / 2, y: ty)); c.addLine(to: CGPoint(x: x, y: ty - th * 0.45)); c.addLine(to: CGPoint(x: x + tw / 2, y: ty)); c.closePath(); c.fillPath() }
                    c.fill(CGRect(x: x - 6, y: baseY, width: 12, height: h - baseY))
                    x += size * (0.55 + rnd(i + 3) * 0.3); i += 1
                }
                c.setFillColor(col((0.05 + shade * 0.2, 0.22 + shade * 0.6, 0.12 + shade * 0.25))); c.fill(CGRect(x: 0, y: baseY, width: w, height: h - baseY))
            }
            c.setFillColor(col((0.03, 0.14, 0.08))); c.fill(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.07))
            balloon(c, x: w * 0.5 + 30 * sin(t * 1.2), y: h * 0.70 - 50 * t, color: (0.95, 0.18, 0.35))
        }
    }
}

/// Writes a silent 1280x720, 30 fps H.264 clip of `scene` (`seconds` long).
func writeScene(_ scene: Scene, seconds: Int, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
    w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
    for i in 0..<(seconds * 30) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, W, H, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!),
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)   // top-left origin
        scene.draw(ctx, t: CGFloat(i) / 30)
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
    }
    input.markAsFinished()
    await w.finishWriting()
    if w.status != .completed { throw w.error ?? NSError(domain: "footage", code: 1) }
}
