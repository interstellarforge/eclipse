import AppKit
import CoreImage

/// Draws the overlay layers (confetti, snow, ...). Every particle is a pure function of its number and the time,
/// so preview, export and the Overlays tab thumbnails always match.
public enum GeneratorRenderer {
    /// `amount` 0...1 is the density. The result is transparent where nothing is drawn.
    public static func image(_ kind: GeneratorKind, amount: Double, size: CGSize, seconds: Double) -> CIImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(kind, ctx, amount: min(max(amount, 0), 1), W: size.width, H: size.height, t: seconds)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    private static func rnd(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40_503 &+ 97)
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        return Double((x &* 0x2545F4914F6CDD1D) >> 11) / Double(1 << 53)
    }

    private static func wrap(_ v: Double, _ range: Double) -> Double { v - range * floor(v / range) }

    private static func draw(_ kind: GeneratorKind, _ ctx: CGContext, amount: Double, W: Double, H: Double, t: Double) {
        let unit = H / 1080   // sizes are designed for 1080 p
        switch kind {
        case .confetti:
            let colors: [(Double, Double, Double)] = [(1, 0.25, 0.35), (1, 0.8, 0.1), (0.2, 0.8, 0.5), (0.25, 0.55, 1), (0.8, 0.35, 1), (1, 0.55, 0.15)]
            for i in 0..<Int(40 + 180 * amount) {
                let speed = H * (0.22 + 0.3 * rnd(i, 2))
                let y = H + 30 - wrap(rnd(i, 3) * (H + 60) + t * speed, H + 60)
                let x = rnd(i, 1) * W + sin(t * 2 + Double(i)) * 14 * unit
                let c = colors[i % colors.count], size = (8 + 8 * rnd(i, 4)) * unit
                ctx.saveGState()
                ctx.translateBy(x: x, y: y); ctx.rotate(by: t * (rnd(i, 5) * 8 - 4) + rnd(i, 6) * 6)
                ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 0.95)
                ctx.fill(CGRect(x: -size / 2, y: -size / 4, width: size, height: size / 2))
                ctx.restoreGState()
            }
        case .snow:
            for i in 0..<Int(60 + 260 * amount) {
                let depth = 0.3 + 0.7 * rnd(i, 2)
                let y = H + 10 - wrap(rnd(i, 3) * (H + 20) + t * H * 0.08 * (0.5 + depth), H + 20)
                let x = rnd(i, 1) * W + sin(t * (0.5 + rnd(i, 4)) + Double(i)) * 24 * unit
                let r = (1.5 + 3.5 * depth) * unit
                ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.35 + 0.55 * depth)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        case .rain:
            ctx.setLineCap(.round)
            for i in 0..<Int(120 + 480 * amount) {
                let speed = H * (1.1 + 0.6 * rnd(i, 2)), length = (22 + 26 * rnd(i, 4)) * unit
                let y = H + 40 - wrap(rnd(i, 3) * (H + 80) + t * speed, H + 80)
                let x = wrap(rnd(i, 1) * (W + 200) - 100 + (H - y) * 0.15, W + 200) - 100
                ctx.setStrokeColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.18 + 0.3 * rnd(i, 5))
                ctx.setLineWidth(1.4 * unit)
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x - length * 0.15, y: y + length)); ctx.strokePath()
            }
        case .sparkles:
            for i in 0..<Int(20 + 80 * amount) {
                let twinkle = pow(max(0, sin(t * (2 + 3 * rnd(i, 4)) + rnd(i, 5) * 6.28)), 3)
                guard twinkle > 0.02 else { continue }
                let x = rnd(i, 1) * W, y = rnd(i, 2) * H, r = (6 + 16 * rnd(i, 3)) * unit * (0.4 + 0.6 * twinkle)
                ctx.setFillColor(red: 1, green: 0.96, blue: 0.8, alpha: twinkle)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y + r)); ctx.addLine(to: CGPoint(x: x + r * 0.18, y: y + r * 0.18)); ctx.addLine(to: CGPoint(x: x + r, y: y))
                ctx.addLine(to: CGPoint(x: x + r * 0.18, y: y - r * 0.18)); ctx.addLine(to: CGPoint(x: x, y: y - r)); ctx.addLine(to: CGPoint(x: x - r * 0.18, y: y - r * 0.18))
                ctx.addLine(to: CGPoint(x: x - r, y: y)); ctx.addLine(to: CGPoint(x: x - r * 0.18, y: y + r * 0.18)); ctx.closePath(); ctx.fillPath()
            }
        case .bokeh:
            let space = CGColorSpaceCreateDeviceRGB()
            let palette: [(Double, Double, Double)] = [(1, 0.75, 0.4), (1, 0.55, 0.6), (0.6, 0.8, 1), (1, 0.9, 0.7)]
            for i in 0..<Int(8 + 26 * amount) {
                let r = (30 + 90 * rnd(i, 3)) * unit
                let x = wrap(rnd(i, 1) * W + t * 12 * unit * (rnd(i, 6) - 0.5) * 4, W + 2 * r) - r
                let y = wrap(rnd(i, 2) * H + t * 10 * unit * (0.3 + rnd(i, 7)), H + 2 * r) - r
                let c = palette[i % palette.count], a = 0.10 + 0.2 * rnd(i, 4)
                let colors = [CGColor(red: c.0, green: c.1, blue: c.2, alpha: a), CGColor(red: c.0, green: c.1, blue: c.2, alpha: a * 0.7), CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.75, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
                }
            }
        case .dust:
            let frame = Int(t * 12)
            for i in 0..<Int(60 + 240 * amount) {
                let k = i &+ frame &* 977
                let r = (0.6 + 1.6 * rnd(k, 3)) * unit
                ctx.setFillColor(red: 1, green: 0.98, blue: 0.9, alpha: 0.25 + 0.5 * rnd(k, 4))
                ctx.fillEllipse(in: CGRect(x: rnd(k, 1) * W, y: rnd(k, 2) * H, width: 2 * r, height: 2 * r))
            }
            for i in 0..<3 where rnd(frame, 90 + i) < 0.12 + 0.3 * amount {
                let x = rnd(frame, 80 + i) * W, y = rnd(frame, 70 + i) * H, length = (60 + 380 * rnd(frame, 60 + i)) * unit
                ctx.setStrokeColor(red: 1, green: 1, blue: 0.95, alpha: 0.35); ctx.setLineWidth(1.2 * unit)
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + (rnd(frame, 50 + i) - 0.5) * 6 * unit, y: y - length)); ctx.strokePath()
            }
        case .sunbeams:
            let source = CGPoint(x: W * 0.92, y: H * 1.02)
            let rays = 14
            for i in 0..<rays {
                let angle = Double.pi * (1.08 + 0.42 * (Double(i) / Double(rays - 1))) + sin(t * 0.4 + Double(i)) * 0.03
                let width = 0.03 + 0.05 * rnd(i, 2)
                let a = (0.06 + 0.16 * rnd(i, 3)) * (0.4 + 0.8 * amount)
                ctx.setFillColor(red: 1, green: 0.85, blue: 0.5, alpha: min(0.5, a))
                ctx.beginPath(); ctx.move(to: source)
                ctx.addLine(to: CGPoint(x: source.x + cos(angle - width) * W * 2, y: source.y + sin(angle - width) * W * 2))
                ctx.addLine(to: CGPoint(x: source.x + cos(angle + width) * W * 2, y: source.y + sin(angle + width) * W * 2)); ctx.closePath(); ctx.fillPath()
            }
            let glow = [CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 0.55), CGColor(red: 1, green: 0.8, blue: 0.4, alpha: 0)] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: source, startRadius: 0, endCenter: source, endRadius: H * 0.7, options: [])
            }
        case .frame:
            let border = H * (0.025 + 0.045 * amount)
            ctx.setFillColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
            let outer = CGRect(x: 0, y: 0, width: W, height: H), inner = outer.insetBy(dx: border, dy: border).offsetBy(dx: 0, dy: border * 0.4)
            ctx.beginPath(); ctx.addRect(outer); ctx.addRect(inner); ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 0.15); ctx.setLineWidth(2 * unit); ctx.stroke(inner)
        case .hearts:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            for i in 0..<Int(6 + 24 * amount) {
                let progress = wrap(rnd(i, 3) + t * (0.08 + 0.08 * rnd(i, 2)), 1)
                let x = rnd(i, 1) * W + sin(t * 1.5 + Double(i)) * 30 * unit, y = -40 + progress * (H + 80)
                let size = (28 + 44 * rnd(i, 4)) * unit
                ctx.setAlpha(min(1, progress * 4) * min(1, (1 - progress) * 3) * 0.9)
                ("❤️" as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size)])
            }
            ctx.setAlpha(1)
            NSGraphicsContext.restoreGraphicsState()
        case .fireflies:
            let space = CGColorSpaceCreateDeviceRGB()
            for i in 0..<Int(10 + 40 * amount) {
                let x = W * (0.5 + 0.48 * sin(t * (0.15 + 0.2 * rnd(i, 2)) + rnd(i, 1) * 6.28)), y = H * (0.5 + 0.45 * sin(t * (0.12 + 0.18 * rnd(i, 4)) + rnd(i, 3) * 6.28))
                let pulse = 0.35 + 0.65 * pow(max(0, sin(t * (1 + 2 * rnd(i, 5)) + rnd(i, 6) * 6.28)), 2), r = (10 + 14 * rnd(i, 7)) * unit
                let colors = [CGColor(red: 1, green: 0.95, blue: 0.5, alpha: 0.9 * pulse), CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
                }
            }
        case .stars:
            for i in 0..<Int(50 + 250 * amount) {
                let x = rnd(i, 1) * W, y = rnd(i, 2) * H, r = (0.8 + 2.2 * rnd(i, 3)) * unit
                let tw = 0.3 + 0.7 * pow(max(0, sin(t * (0.8 + 2 * rnd(i, 4)) + rnd(i, 5) * 6.28)), 2)
                ctx.setFillColor(red: 1, green: 0.98, blue: 0.9, alpha: tw)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                if rnd(i, 6) > 0.9 { ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: tw * 0.6); ctx.setLineWidth(unit)
                    ctx.move(to: CGPoint(x: x - r * 4, y: y)); ctx.addLine(to: CGPoint(x: x + r * 4, y: y)); ctx.move(to: CGPoint(x: x, y: y - r * 4)); ctx.addLine(to: CGPoint(x: x, y: y + r * 4)); ctx.strokePath() }
            }
        case .embers:
            let space = CGColorSpaceCreateDeviceRGB()
            for i in 0..<Int(30 + 150 * amount) {
                let life = wrap(rnd(i, 3) + t * (0.08 + 0.12 * rnd(i, 2)), 1)
                let x = rnd(i, 1) * W + sin(t * 1.3 + Double(i)) * 40 * unit * life, y = life * H * 1.05 - 10
                let r = (2 + 5 * rnd(i, 4)) * unit * (1 - life * 0.6), a = (1 - life) * 0.9
                let colors = [CGColor(red: 1, green: 0.65 - 0.3 * life, blue: 0.15, alpha: a), CGColor(red: 1, green: 0.3, blue: 0.05, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) { ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r * 2.5, options: []) }
            }
        case .petals:
            for i in 0..<Int(12 + 60 * amount) {
                let life = wrap(rnd(i, 3) + t * (0.05 + 0.05 * rnd(i, 2)), 1)
                let x = rnd(i, 1) * W + sin(t * (0.6 + rnd(i, 4)) + Double(i)) * 60 * unit, y = H + 20 - life * (H + 40), size = (10 + 12 * rnd(i, 5)) * unit
                ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: t * (rnd(i, 6) * 2 - 1) + rnd(i, 7) * 6)
                ctx.setFillColor(red: 1, green: 0.72 + 0.15 * rnd(i, 8), blue: 0.8, alpha: 0.85)
                ctx.fillEllipse(in: CGRect(x: -size / 2, y: -size / 4, width: size, height: size / 2)); ctx.restoreGState()
            }
        case .bubbles:
            for i in 0..<Int(8 + 36 * amount) {
                let life = wrap(rnd(i, 3) + t * (0.06 + 0.08 * rnd(i, 2)), 1)
                let x = rnd(i, 1) * W + sin(t * 1.1 + Double(i)) * 20 * unit, y = -30 + life * (H + 60), r = (10 + 34 * rnd(i, 4)) * unit
                ctx.setStrokeColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.7); ctx.setLineWidth(1.6 * unit)
                ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                ctx.setFillColor(red: 0.8, green: 0.92, blue: 1, alpha: 0.12); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.7); ctx.fillEllipse(in: CGRect(x: x - r * 0.55, y: y + r * 0.2, width: r * 0.3, height: r * 0.2))
            }
        case .leaves:
            let colors: [(Double, Double, Double)] = [(0.85, 0.35, 0.1), (0.95, 0.6, 0.15), (0.7, 0.2, 0.1), (0.8, 0.7, 0.2)]
            for i in 0..<Int(10 + 50 * amount) {
                let life = wrap(rnd(i, 3) + t * (0.05 + 0.06 * rnd(i, 2)), 1)
                let x = rnd(i, 1) * W + sin(t * (0.5 + rnd(i, 4)) + Double(i)) * 80 * unit, y = H + 30 - life * (H + 60), size = (14 + 18 * rnd(i, 5)) * unit
                let c = colors[i % colors.count]
                ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: sin(t * (0.8 + rnd(i, 6)) + Double(i)) * 1.2)
                ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 0.9)
                ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: size)); ctx.addQuadCurve(to: CGPoint(x: 0, y: -size), control: CGPoint(x: size * 0.9, y: 0)); ctx.addQuadCurve(to: CGPoint(x: 0, y: size), control: CGPoint(x: -size * 0.9, y: 0)); ctx.fillPath()
                ctx.restoreGState()
            }
        case .fireworks:
            let space = CGColorSpaceCreateDeviceRGB()
            let bursts = 2 + Int(4 * amount)
            for b in 0..<bursts {
                let period = 2.6, local = wrap(t + rnd(b, 1) * period, period) / period
                guard local > 0.12 else { continue }
                let age = (local - 0.12) / 0.88, cx = W * (0.15 + 0.7 * rnd(b + Int(t / period), 2)), cy = H * (0.45 + 0.4 * rnd(b + Int(t / period), 3))
                let hue = rnd(b + Int(t / period), 4), color = (0.6 + 0.4 * sin(hue * 6.28), 0.6 + 0.4 * sin(hue * 6.28 + 2), 0.6 + 0.4 * sin(hue * 6.28 + 4))
                for i in 0..<48 {
                    let angle = Double(i) / 48 * 6.283, dist = (1 - pow(1 - age, 2.2)) * H * 0.3 * (0.7 + 0.3 * rnd(i, 5))
                    let x = cx + cos(angle) * dist, y = cy + sin(angle) * dist - age * age * H * 0.08
                    let colors = [CGColor(red: color.0, green: color.1, blue: color.2, alpha: (1 - age) * 0.95), CGColor(red: color.0, green: color.1, blue: color.2, alpha: 0)] as CFArray
                    if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) { ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: 7 * unit, options: []) }
                }
            }
        case .smoke:
            let space = CGColorSpaceCreateDeviceRGB()
            for i in 0..<Int(5 + 9 * amount) {
                let x = wrap(rnd(i, 1) * W * 1.4 + t * W * (0.015 + 0.02 * rnd(i, 2)), W * 1.4) - W * 0.2, y = H * (0.15 + 0.7 * rnd(i, 3)) + sin(t * 0.3 + Double(i)) * 30 * unit, r = H * (0.25 + 0.3 * rnd(i, 4))
                let colors = [CGColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 0.2), CGColor(red: 0.85, green: 0.85, blue: 0.9, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) { ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: []) }
            }
        case .streaks:
            let space = CGColorSpaceCreateDeviceRGB()
            for i in 0..<Int(2 + 4 * amount) {
                let pos = wrap(t * (0.12 + 0.1 * rnd(i, 2)) + rnd(i, 1), 1.6) - 0.3, y = H * (0.15 + 0.7 * rnd(i, 3)), x = W * pos, len = W * (0.3 + 0.3 * rnd(i, 4))
                let colors = [CGColor(red: 1, green: 0.8, blue: 0.5, alpha: 0), CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.5), CGColor(red: 1, green: 0.8, blue: 0.5, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) {
                    ctx.saveGState(); ctx.clip(to: CGRect(x: x - len / 2, y: y - 2 * unit, width: len, height: 4 * unit))
                    ctx.drawLinearGradient(g, start: CGPoint(x: x - len / 2, y: y), end: CGPoint(x: x + len / 2, y: y), options: []); ctx.restoreGState()
                }
            }
        case .digitalRain:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let cell = 22 * unit, columns = Int(W / cell), glyphs = Array("01ｱｲｳｴｵｶｷｸｹｺ+=<>")
            let font = NSFont.monospacedSystemFont(ofSize: cell * 0.9, weight: .bold)
            for c in 0..<columns where rnd(c, 1) < 0.35 + 0.6 * amount {
                let speed = 4 + 8 * rnd(c, 2), head = wrap(t * speed + rnd(c, 3) * 40, 40 + H / cell)
                for k in 0..<14 {
                    let row = head - Double(k), y = H - row * cell
                    guard y > -cell, y < H + cell else { continue }
                    let g = String(glyphs[Int(rnd(c * 31 + Int(row) + 1, 4) * Double(glyphs.count)) % glyphs.count])
                    let alpha = k == 0 ? 1.0 : max(0, 0.8 - Double(k) * 0.06)
                    (g as NSString).draw(at: CGPoint(x: Double(c) * cell, y: y), withAttributes: [.font: font, .foregroundColor: k == 0 ? NSColor.white : NSColor(red: 0.2, green: 1, blue: 0.4, alpha: alpha)])
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Looping preview over the demo scene (or your picture): 3 s of the overlay.
    public static func previewFrames(_ kind: GeneratorKind, source: CGImage?, size: CGSize = CGSize(width: 240, height: 135), count: Int = 36) -> [CGImage] {
        let rect = CGRect(origin: .zero, size: size)
        let base: CIImage
        if let source {
            let img = CIImage(cgImage: source), s = max(size.width / img.extent.width, size.height / img.extent.height)
            let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
            base = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX, y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY)).cropped(to: rect)
        } else { base = EffectRenderer.demoScene(size, greenScreen: false) }
        let context = CIContext()
        return (0..<count).compactMap { i in
            guard let overlay = image(kind, amount: 0.6, size: size, seconds: Double(i) / 12 + 2) else { return nil }
            return context.createCGImage(overlay.composited(over: base).cropped(to: rect), from: rect)
        }
    }
}
