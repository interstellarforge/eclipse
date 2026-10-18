import CoreImage
import CoreGraphics

/// Draws every transition. The compositor (preview/export) and the sidebar previews both call this,
/// so what you see in the Transitions tab is what the movie gets.
public enum TransitionRenderer {
    /// `p` runs 0 (all `a`) to 1 (all `b`). Both images cover `Rect(0, 0, size)`; the result may spill outside it.
    public static func blend(_ a: CIImage, _ b: CIImage, _ type: TransitionType, _ p: Double, _ size: CGSize) -> CIImage {
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)
        let diagonal = (w * w + h * h).squareRoot()
        if p <= 0 { return a }   // the ends are always exactly the clips
        if p >= 1 { return b }
        switch type {
        case .crossfade:
            return faded(b, p).composited(over: a)
        case .fadeBlack, .fadeWhite:
            let base = CIImage(color: type == .fadeBlack ? .black : .white).cropped(to: rect)
            return (p < 0.5 ? faded(a, 1 - 2 * p) : faded(b, 2 * p - 1)).composited(over: base)
        case .blurFade:
            let r = sin(.pi * p) * w * 0.02
            return faded(blurred(b, r, rect), p).composited(over: blurred(a, r, rect))
        case .pixelate:
            let amount = sin(.pi * p) * w * 0.05
            let image = p < 0.5 ? a : b
            guard amount >= 1.5 else { return image }
            return image.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: amount]).cropped(to: rect)
        case .wipe:
            return b.cropped(to: CGRect(x: 0, y: 0, width: w * p, height: h)).composited(over: a)
        case .wipeLeft:
            return b.cropped(to: CGRect(x: w * (1 - p), y: 0, width: w * p, height: h)).composited(over: a)
        case .wipeUp:
            return b.cropped(to: CGRect(x: 0, y: 0, width: w, height: h * p)).composited(over: a)
        case .wipeDown:
            return b.cropped(to: CGRect(x: 0, y: h * (1 - p), width: w, height: h * p)).composited(over: a)
        case .slide:
            return shifted(b, (1 - p) * w, 0).composited(over: shifted(a, -p * w, 0))
        case .slideRight:
            return shifted(b, -(1 - p) * w, 0).composited(over: shifted(a, p * w, 0))
        case .slideUp:
            return shifted(b, 0, -(1 - p) * h).composited(over: shifted(a, 0, p * h))
        case .slideDown:
            return shifted(b, 0, (1 - p) * h).composited(over: shifted(a, 0, -p * h))
        case .cover:
            return shifted(b, (1 - p) * w, 0).composited(over: a)
        case .uncover:
            return shifted(a, -p * w, 0).composited(over: b)
        case .zoom:
            return faded(scaled(b, 1.6 - 0.6 * p, size), p).composited(over: scaled(a, 1 + 0.6 * p, size))
        case .spin:
            let c = CGPoint(x: w / 2, y: h / 2)
            let t = CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: p * .pi / 2))
                .concatenating(CGAffineTransform(scaleX: 1 - 0.5 * p, y: 1 - 0.5 * p))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            return faded(a.transformed(by: t), 1 - p).composited(over: b)
        case .irisOpen:
            return masked(b, over: a, mask: mask(size) { $0.fillEllipse(in: CGRect(x: w / 2 - p * diagonal / 2, y: h / 2 - p * diagonal / 2,
                                                                              width: p * diagonal, height: p * diagonal)) })
        case .irisClose:
            let r = (1 - p) * diagonal / 2
            return masked(a, over: b, mask: mask(size) { $0.fillEllipse(in: CGRect(x: w / 2 - r, y: h / 2 - r, width: 2 * r, height: 2 * r)) })
        case .barnDoorH:
            return masked(b, over: a, mask: mask(size) { $0.fill(CGRect(x: w / 2 - p * w / 2, y: 0, width: p * w, height: h)) })
        case .barnDoorV:
            return masked(b, over: a, mask: mask(size) { $0.fill(CGRect(x: 0, y: h / 2 - p * h / 2, width: w, height: p * h)) })
        case .blinds:
            let strips = 8.0
            return masked(b, over: a, mask: mask(size) { ctx in
                if p >= 1 { ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)); return }   // avoid hairline seams
                for i in 0..<Int(strips) { ctx.fill(CGRect(x: 0, y: Double(i) * h / strips, width: w, height: p * h / strips)) }
            })
        case .whipLeft, .whipRight:
            let left = type == .whipLeft
            let moved = left ? shifted(b, (1 - p) * w, 0).composited(over: shifted(a, -p * w, 0)) : shifted(b, -(1 - p) * w, 0).composited(over: shifted(a, p * w, 0))
            return moved.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: sin(.pi * p) * w * 0.06, kCIInputAngleKey: 0]).cropped(to: rect)
        case .glitchCut:
            let amount = p < 0.5 ? p * 2 : (1 - p) * 2
            let source = p < 0.5 ? a : b
            guard amount > 0.02 else { return source }
            return EffectRenderer.apply(Effect(.glitch, amount: amount), to: source, size: size, progress: p, seconds: p * 3, duration: 3)
        case .flashCut:
            let base = p < 0.5 ? a : b
            let alpha = max(0, 1 - abs(p - 0.5) / 0.2)
            return alpha > 0.001 ? CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: alpha)).cropped(to: rect).composited(over: base) : base
        case .zoomBlur:
            let first = p < 0.5
            let scale = 1 + 0.8 * (first ? p : 1 - p)
            let source = scaled(first ? a : b, scale, size)
            return source.clampedToExtent().applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: CIVector(x: w / 2, y: h / 2), kCIInputAmountKey: sin(.pi * p) * w * 0.05]).cropped(to: rect)
        case .rotateZoom:
            let c = CGPoint(x: w / 2, y: h / 2)
            let t = CGAffineTransform(translationX: -c.x, y: -c.y).concatenating(CGAffineTransform(rotationAngle: -(1 - p) * .pi / 2))
                .concatenating(CGAffineTransform(scaleX: 0.35 + 0.65 * p, y: 0.35 + 0.65 * p)).concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            return faded(b.transformed(by: t), p).composited(over: a)
        case .pixelDissolve:
            let columns = 24, rows = 14
            return masked(b, over: a, mask: mask(size) { ctx in
                for r in 0..<rows { for c in 0..<columns {
                    var x = UInt32(truncatingIfNeeded: r * 7_919 + c * 104_729 + 13); x ^= x << 13; x ^= x >> 17; x ^= x << 5
                    if Double(x % 1_000) / 1_000 < p { ctx.fill(CGRect(x: Double(c) * w / Double(columns) - 0.5, y: Double(r) * h / Double(rows) - 0.5, width: w / Double(columns) + 1, height: h / Double(rows) + 1)) }
                } }
            })
        case .diagonalWipe:
            let t = 2 * p
            return masked(b, over: a, mask: mask(size) { ctx in
                ctx.beginPath()
                if t <= 1 { ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: t * w, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: t * h)) }
                else { ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: w, y: 0)); ctx.addLine(to: CGPoint(x: w, y: (t - 1) * h)); ctx.addLine(to: CGPoint(x: (t - 1) * w, y: h)); ctx.addLine(to: CGPoint(x: 0, y: h)) }
                ctx.closePath(); ctx.fillPath()
            })
        case .diamond:
            let k = 2.05 * p
            return masked(b, over: a, mask: mask(size) { ctx in
                ctx.beginPath()
                ctx.move(to: CGPoint(x: w / 2 - k * w / 2, y: h / 2)); ctx.addLine(to: CGPoint(x: w / 2, y: h / 2 + k * h / 2))
                ctx.addLine(to: CGPoint(x: w / 2 + k * w / 2, y: h / 2)); ctx.addLine(to: CGPoint(x: w / 2, y: h / 2 - k * h / 2))
                ctx.closePath(); ctx.fillPath()
            })
        case .splitSlide:
            let top = a.cropped(to: CGRect(x: 0, y: h / 2, width: w, height: h / 2)), bottom = a.cropped(to: CGRect(x: 0, y: 0, width: w, height: h / 2))
            return shifted(top, 0, p * h / 2).composited(over: shifted(bottom, 0, -p * h / 2).composited(over: b))
        case .barsSwipe:
            return ci("CIBarsSwipeTransition", a, b, p, rect, ["inputAngle": Double.pi, "inputWidth": max(20, h / 18), "inputBarOffset": 20]) ?? faded(b, p).composited(over: a)
        case .modTransition:
            return ci("CIModTransition", a, b, p, rect, ["inputCenter": CIVector(x: w / 2, y: h / 2), "inputAngle": 2, "inputRadius": 40, "inputCompression": 300]) ?? faded(b, p).composited(over: a)
        case .ripple:
            return ci("CIRippleTransition", a, b, p, rect, ["inputCenter": CIVector(x: w / 2, y: h / 2), "inputExtent": CIVector(cgRect: rect), "inputShadingImage": CIImage(color: .white).cropped(to: rect),
                                                           "inputWidth": 80, "inputScale": 40]) ?? faded(b, p).composited(over: a)
        case .pageCurl:
            return ci("CIPageCurlTransition", a, b, p, rect, ["inputExtent": CIVector(cgRect: rect), "inputBacksideImage": a, "inputShadingImage": CIImage(color: .white).cropped(to: rect),
                                                             "inputAngle": 0.6, "inputRadius": max(60, h / 6)]) ?? faded(b, p).composited(over: a)
        case .swirl:
            let amount = sin(.pi * p)
            func twirl(_ img: CIImage, _ angle: Double) -> CIImage {
                img.clampedToExtent().applyingFilter("CITwirlDistortion", parameters: [kCIInputCenterKey: CIVector(x: w / 2, y: h / 2), kCIInputRadiusKey: diagonal * 0.6, kCIInputAngleKey: angle]).cropped(to: rect)
            }
            return faded(twirl(b, -amount * 3.5), p).composited(over: twirl(a, amount * 3.5))
        case .filmBurn:
            let burn = sin(.pi * p)
            let orange = CIImage(color: CIColor(red: 1, green: 0.5, blue: 0.1, alpha: burn * 0.8)).cropped(to: rect)
            let white = CIImage(color: CIColor(red: 1, green: 0.95, blue: 0.8, alpha: pow(burn, 4) * 0.7)).cropped(to: rect)
            return white.composited(over: orange.composited(over: faded(b, p).composited(over: a)))
        case .shutter:
            let first = p < 0.5, q = first ? p * 2 : 2 - p * 2
            let bar = h / 2 * q
            let black = CIImage(color: .black)
            return black.cropped(to: CGRect(x: 0, y: h - bar, width: w, height: bar)).composited(over: black.cropped(to: CGRect(x: 0, y: 0, width: w, height: bar)).composited(over: first ? a : b))
        case .cornerIris:
            let r = p * diagonal * 1.05
            return masked(b, over: a, mask: mask(size) { $0.fillEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)) })
        case .tvStatic:
            let strength = sin(.pi * p)
            let base = shifted(p < 0.5 ? a : b, sin(p * 90) * strength * w * 0.03, 0).cropped(to: rect)
            guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return base }
            let gray = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            let grain = shifted(noise, p * 977, p * 313).applyingFilter("CIColorMatrix", parameters: ["inputRVector": gray, "inputGVector": gray, "inputBVector": gray,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: min(1, strength * 1.3))]).cropped(to: rect)
            return grain.composited(over: base)
        case .squeeze:
            let t = CGAffineTransform(translationX: -w / 2, y: 0).concatenating(CGAffineTransform(scaleX: 1 - p, y: 1)).concatenating(CGAffineTransform(translationX: w / 2, y: 0))
            return a.transformed(by: t).composited(over: b)
        case .cubeSpin:
            let left = a.transformed(by: CGAffineTransform(scaleX: 1 - p, y: 1))
            let right = b.transformed(by: CGAffineTransform(scaleX: p, y: 1).concatenating(CGAffineTransform(translationX: w * (1 - p), y: 0)))
            let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.35 * (1 - abs(2 * p - 1)))).cropped(to: rect)
            return shade.composited(over: right.composited(over: left.composited(over: CIImage(color: .black).cropped(to: rect))))
        case .blindsV:
            let strips = 10.0
            return masked(b, over: a, mask: mask(size) { ctx in
                if p >= 1 { ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)); return }
                for i in 0..<Int(strips) { ctx.fill(CGRect(x: Double(i) * w / strips, y: 0, width: p * w / strips, height: h)) }
            })
        case .copyMachine:
            return ci("CICopyMachineTransition", a, b, p, rect, ["inputExtent": CIVector(cgRect: rect), "inputColor": CIColor(red: 0.6, green: 1, blue: 0.8), "inputAngle": 0, "inputWidth": max(40, w / 8), "inputOpacity": 1.3]) ?? faded(b, p).composited(over: a)
        case .flare:
            return ci("CIFlashTransition", a, b, p, rect, ["inputCenter": CIVector(x: w * 0.5, y: h * 0.5), "inputExtent": CIVector(cgRect: rect), "inputColor": CIColor(red: 1, green: 0.8, blue: 0.5),
                                                          "inputMaxStriationRadius": 2.5, "inputStriationStrength": 0.5, "inputStriationContrast": 1.375, "inputFadeThreshold": 0.85]) ?? faded(b, p).composited(over: a)
        case .clock:
            return masked(b, over: a, mask: mask(size) { ctx in
                if p >= 1 { ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)); return }
                ctx.move(to: CGPoint(x: w / 2, y: h / 2))
                ctx.addArc(center: CGPoint(x: w / 2, y: h / 2), radius: diagonal, startAngle: .pi / 2,
                           endAngle: .pi / 2 - 2 * .pi * p, clockwise: true)
                ctx.closePath(); ctx.fillPath()
            })
        }
    }

    /// Looping preview: hold on A, play the transition, hold on B. Uses your first two clips, or placeholder patterns.
    public static func previewFrames(_ type: TransitionType, a: CGImage?, b: CGImage?,
                                     size: CGSize = CGSize(width: 240, height: 135), count: Int = 36) -> [CGImage] {
        let rect = CGRect(origin: .zero, size: size)
        func fitted(_ image: CGImage?, _ tint: CIColor) -> CIImage {
            guard let image else {
                let pattern = CIFilter(name: "CICheckerboardGenerator", parameters: [
                    "inputCenter": CIVector(x: 0, y: 0), "inputColor0": tint, "inputColor1": CIColor(red: 0.1, green: 0.1, blue: 0.12),
                    "inputWidth": size.width / 8, "inputSharpness": 1])?.outputImage
                return (pattern ?? CIImage(color: tint)).cropped(to: rect)
            }
            let img = CIImage(cgImage: image)
            let s = max(size.width / img.extent.width, size.height / img.extent.height)   // fill
            let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
            return scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX,
                                                            y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY)).cropped(to: rect)
        }
        let imageA = fitted(a, CIColor(red: 0.2, green: 0.5, blue: 1)), imageB = fitted(b ?? a, CIColor(red: 1, green: 0.55, blue: 0.1))
        let context = CIContext()
        let hold = count / 6
        return (0..<count).compactMap { i in
            let t = min(max(Double(i - hold) / Double(count - 2 * hold), 0), 1)
            let p = t * t * (3 - 2 * t)
            return context.createCGImage(blend(imageA, imageB, type, p, size).cropped(to: rect), from: rect)
        }
    }

    // MARK: Helpers

    /// One of Core Image's built-in transitions, cropped to the frame; nil if the filter is missing.
    private static func ci(_ name: String, _ a: CIImage, _ b: CIImage, _ p: Double, _ rect: CGRect, _ extra: [String: Any]) -> CIImage? {
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(a, forKey: kCIInputImageKey); filter.setValue(b, forKey: kCIInputTargetImageKey); filter.setValue(p, forKey: kCIInputTimeKey)
        for (key, value) in extra { filter.setValue(value, forKey: key) }
        return filter.outputImage?.cropped(to: rect)
    }

    private static func faded(_ image: CIImage, _ alpha: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(max(alpha, 0), 1))])
    }

    private static func shifted(_ image: CIImage, _ x: Double, _ y: Double) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func scaled(_ image: CIImage, _ s: Double, _ size: CGSize) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
    }

    private static func blurred(_ image: CIImage, _ radius: Double, _ rect: CGRect) -> CIImage {
        guard radius >= 0.5 else { return image }
        return image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: rect)
    }

    private static func masked(_ top: CIImage, over bottom: CIImage, mask: CIImage) -> CIImage {
        top.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: bottom, kCIInputMaskImageKey: mask])
    }

    /// White where `draw` fills, black elsewhere.
    private static func mask(_ size: CGSize, _ draw: (CGContext) -> Void) -> CIImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(gray: 1, alpha: 1); draw(ctx)
        return CIImage(cgImage: ctx.makeImage()!)
    }
}
