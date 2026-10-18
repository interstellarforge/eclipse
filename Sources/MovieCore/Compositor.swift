import AppKit
import AVFoundation
import CoreImage

struct GeneratorLayer {
    var kind: GeneratorKind
    var amount: Double
    var opacity: Double
    var start: Ms, end: Ms
    var fadeIn: Ms, fadeOut: Ms
}

struct TextLayer {
    var string: String
    var style: TextStyle
    var start: Ms, end: Ms          // the title clip's span on the timeline
    var fadeIn: Ms, fadeOut: Ms
}

struct ClipRef {
    var trackID: CMPersistentTrackID
    var orientation: CGImagePropertyOrientation
    var opacity = 1.0
    var scale = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var look = Look()
    var effects: [Effect] = []
    var keyframes: [Keyframe] = []
    var start: Ms = 0       // timeline span of the clip, for picture fades
    var end: Ms = 0
    var fadeIn: Ms = 0
    var fadeOut: Ms = 0
}

enum Layer {
    case clip(ClipRef)
    /// `start`/`end` (ms) bound the overlap; progress is derived per frame.
    case transition(from: ClipRef, to: ClipRef, type: TransitionType, start: Ms, end: Ms)
    case text(TextLayer)
    case generator(GeneratorLayer)
}

final class Instruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let layers: [Layer]
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?

    init(timeRange: CMTimeRange, layers: [Layer]) {
        self.timeRange = timeRange
        self.layers = layers
        var ids: [CMPersistentTrackID] = []
        for l in layers {
            switch l {
            case .clip(let r): ids.append(r.trackID)
            case .transition(let f, let t, _, _, _): ids += [f.trackID, t.trackID]
            case .text, .generator: break
            }
        }
        requiredSourceTrackIDs = ids.map { NSNumber(value: $0) }
    }
}

/// Core Image compositor: stacks clip layers, blends transitions, draws titles.
final class Compositor: NSObject, AVVideoCompositing {
    private let context = CIContext()
    private let textLock = NSLock()
    private var textCache: [String: CIImage] = [:]

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? Instruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MovieCore", code: 1))
            return
        }
        let size = request.renderContext.size
        let rect = CGRect(origin: .zero, size: size)
        let nowMs = Double(request.compositionTime.seconds * 1000)
        var image = CIImage(color: .black).cropped(to: rect)

        for layer in instruction.layers {
            switch layer {
            case .clip(let ref):
                if let img = frame(ref, request, size, nowMs) { image = img.composited(over: image) }
            case .transition(let from, let to, let type, let start, let end):
                let p = end > start ? min(max((nowMs - Double(start)) / Double(end - start), 0), 1) : 1
                let a = frame(from, request, size, nowMs), b = frame(to, request, size, nowMs)
                if let a, let b { image = TransitionRenderer.blend(a, b, type, p, size).composited(over: image) }
                else if let one = a ?? b { image = one.composited(over: image) }
            case .text(let layer):
                if let t = titleImage(layer, nowMs, size) { image = t.composited(over: image) }
            case .generator(let g):
                var alpha = g.opacity
                if g.fadeIn > 0 { alpha *= min(1, max(0, (nowMs - Double(g.start)) / Double(g.fadeIn))) }
                if g.fadeOut > 0 { alpha *= min(1, max(0, (Double(g.end) - nowMs) / Double(g.fadeOut))) }
                guard alpha > 0.001, var overlay = GeneratorRenderer.image(g.kind, amount: g.amount, size: size, seconds: (nowMs - Double(g.start)) / 1000) else { break }
                if alpha < 1 { overlay = overlay.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)]) }
                image = overlay.composited(over: image)
            }
        }
        context.render(image.cropped(to: rect), to: output)
        request.finish(withComposedVideoFrame: output)
    }

    private func frame(_ ref: ClipRef, _ request: AVAsynchronousVideoCompositionRequest, _ size: CGSize, _ nowMs: Double) -> CIImage? {
        guard let buffer = request.sourceFrame(byTrackID: ref.trackID) else { return nil }
        var img = CIImage(cvPixelBuffer: buffer).oriented(ref.orientation)
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let s = min(size.width / img.extent.width, size.height / img.extent.height)   // aspect fit
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        var out = img.transformed(by: CGAffineTransform(translationX: (size.width - img.extent.width) / 2,
                                                        y: (size.height - img.extent.height) / 2))
        let fitted = out.extent
        let look = ref.look
        out = LookRenderer.apply(look, to: out, size: size)
        if look.cropLeft > 0 || look.cropRight > 0 || look.cropTop > 0 || look.cropBottom > 0 {
            out = out.cropped(to: CGRect(x: fitted.minX + fitted.width * look.cropLeft, y: fitted.minY + fitted.height * look.cropBottom,
                                         width: fitted.width * (1 - look.cropLeft - look.cropRight), height: fitted.height * (1 - look.cropTop - look.cropBottom)))
        }
        if !ref.effects.isEmpty {
            let length = max(1, Double(ref.end - ref.start))
            let elapsed = min(max(nowMs - Double(ref.start), 0), length)
            for effect in ref.effects {
                out = EffectRenderer.apply(effect, to: out, size: size, progress: elapsed / length, seconds: elapsed / 1000, duration: length / 1000)
            }
        }
        var opacity = ref.opacity, scale = ref.scale, offsetX = ref.offsetX, offsetY = ref.offsetY, rotation = look.rotation
        if let k = Keyframe.interpolate(ref.keyframes, at: nowMs - Double(ref.start)) {   // animation replaces the plain values
            opacity = k.opacity; scale = k.scale; offsetX = k.offsetX; offsetY = k.offsetY; rotation += k.rotation
        }
        if scale != 1 || offsetX != 0 || offsetY != 0 || look.flipX || look.flipY || rotation != 0 {
            // Around the frame centre: flip, rotate, scale, then move by a fraction of the frame size.
            out = out.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                .concatenating(CGAffineTransform(scaleX: look.flipX ? -1 : 1, y: look.flipY ? -1 : 1))
                .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: size.width / 2 + offsetX * size.width,
                                                 y: size.height / 2 + offsetY * size.height)))
        }
        var alpha = opacity
        if ref.fadeIn > 0 { alpha *= min(1, max(0, (nowMs - Double(ref.start)) / Double(ref.fadeIn))) }
        if ref.fadeOut > 0 { alpha *= min(1, max(0, (Double(ref.end) - nowMs) / Double(ref.fadeOut))) }
        if alpha < 1 {
            out = out.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
        }
        return out
    }

    /// The title for this moment: fades, entrance animation, typewriter reveal.
    private func titleImage(_ t: TextLayer, _ nowMs: Double, _ size: CGSize) -> CIImage? {
        let local = nowMs - Double(t.start)
        var alpha = 1.0
        if t.fadeIn > 0 { alpha *= min(1, max(0, local / Double(t.fadeIn))) }
        if t.fadeOut > 0 { alpha *= min(1, max(0, (Double(t.end) - nowMs) / Double(t.fadeOut))) }
        let u = min(1, max(0, local / Double(max(1, t.style.animationMs))))
        let eased = u * u * (3 - 2 * u)
        var visible: Int?
        if t.style.animation == .typewriter {
            visible = Int(Double(t.string.count) * u)
            if visible == 0 { return nil }
        }
        guard var image = textImage(t.style.uppercase ? t.string.uppercased() : t.string, t.style, size, visible: visible), alpha > 0.001 else { return nil }
        let w = size.width, h = size.height
        switch t.style.animation {
        case .none, .typewriter: break
        case .fade: alpha *= u
        case .slideUp: image = image.transformed(by: CGAffineTransform(translationX: 0, y: -(1 - eased) * 0.08 * h)); alpha *= u
        case .slideDown: image = image.transformed(by: CGAffineTransform(translationX: 0, y: (1 - eased) * 0.08 * h)); alpha *= u
        case .slideLeft: image = image.transformed(by: CGAffineTransform(translationX: (1 - eased) * 0.12 * w, y: 0)); alpha *= u
        case .pop:
            let c1 = 1.70158, c3 = c1 + 1
            let back = 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)   // overshoots, then settles
            let s = 0.5 + 0.5 * back
            let cx = w * t.style.x, cy = h * t.style.y
            image = image.transformed(by: CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
            alpha *= min(1, u * 2)
        }
        return alpha < 1 ? image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)]) : image
    }

    private func textImage(_ string: String, _ style: TextStyle, _ size: CGSize, visible: Int? = nil) -> CIImage? {
        TextRenderer.image(string, style, size, visible: visible)
    }

    static func color(_ hex: String) -> NSColor {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                       blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

/// Draws title text (also used for the title previews in the Titles tab).
public enum TextRenderer {
    nonisolated(unsafe) private static var cache: [String: CIImage] = [:]
    private static let lock = NSLock()

    public static func image(_ string: String, _ style: TextStyle, _ size: CGSize, visible: Int? = nil) -> CIImage? {
        let key = "\(string)|\(style)|\(Int(size.width))x\(Int(size.height))|\(visible ?? -1)"
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let w = Int(size.width), h = Int(size.height)
        guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        let para = NSMutableParagraphStyle()
        para.alignment = [.left, .center, .right][max(0, min(style.align, 2))]
        let points = size.height * style.size
        let font = style.fontName.flatMap { NSFont(name: $0, size: points) }
            ?? (style.bold ? NSFont.boldSystemFont(ofSize: points) : NSFont.systemFont(ofSize: points))
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Compositor.color(style.colorHex),
                                                         .paragraphStyle: para]
        if style.shadow {
            let shadow = NSShadow(); shadow.shadowBlurRadius = points / 8; shadow.shadowColor = NSColor.black
            attributes[.shadow] = shadow
        }
        if style.outline { attributes[.strokeColor] = NSColor.black; attributes[.strokeWidth] = -4 }
        if style.tracking != 0 { attributes[.kern] = style.tracking * points }
        if style.glow {   // a soft halo in the text colour instead of the dark shadow
            let halo = NSShadow(); halo.shadowBlurRadius = points * 0.35; halo.shadowColor = Compositor.color(style.colorHex).withAlphaComponent(0.9)
            attributes[.shadow] = halo
        }
        // Typewriter: the whole text is laid out, letters not yet typed are invisible, so nothing jumps around.
        let attributed = NSMutableAttributedString(string: string, attributes: attributes)
        if let visible, visible < string.count {
            let hidden = NSRange(location: visible, length: string.count - visible)
            attributed.setAttributes([.font: font, .paragraphStyle: para, .foregroundColor: NSColor.clear], range: hidden)
        }
        // The text box is anchored at x: centred on it, or starting / ending there for left / right alignment.
        let maxWidth = size.width * 0.9
        let (originX, boxWidth): (Double, Double) = switch style.align {
        case 0: (size.width * style.x, min(maxWidth, size.width * (1 - style.x)))
        case 2: (size.width * style.x - min(maxWidth, size.width * style.x), min(maxWidth, size.width * style.x))
        default: (size.width * style.x - min(maxWidth, 2 * size.width * min(style.x, 1 - style.x)) / 2,
                  min(maxWidth, 2 * size.width * min(style.x, 1 - style.x)))
        }
        let measured = attributed.boundingRect(with: CGSize(width: boxWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin)
        let rect = CGRect(x: originX, y: size.height * style.y - measured.height / 2, width: boxWidth, height: measured.height)
        if style.box {
            let textX = style.align == 0 ? rect.minX : style.align == 2 ? rect.maxX - measured.width : rect.midX - measured.width / 2
            let pad = points * 0.35
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: CGRect(x: textX - pad, y: rect.minY - pad / 2, width: measured.width + 2 * pad,
                                             height: rect.height + pad), xRadius: pad / 2, yRadius: pad / 2).fill()
        }
        attributed.draw(with: rect, options: .usesLineFragmentOrigin)
        if style.glow { attributed.draw(with: rect, options: .usesLineFragmentOrigin) }   // a second pass makes the halo glow
        NSGraphicsContext.restoreGraphicsState()
        guard let image = cg.makeImage() else { return nil }
        let result = CIImage(cgImage: image)
        if cache.count > 600 { cache.removeAll() }
        cache[key] = result
        return result
    }

}

/// Still previews of the title styles: the text over a dark gradient.
public enum TitlePreviews {
    public static func image(_ preset: TitlePreset, size: CGSize = CGSize(width: 240, height: 135)) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        let background = CIFilter(name: "CILinearGradientFilter", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size.width, y: size.height),
                                                                              "inputColor0": CIColor(red: 0.08, green: 0.09, blue: 0.14), "inputColor1": CIColor(red: 0.22, green: 0.2, blue: 0.3)])?.outputImage?.cropped(to: rect)
            ?? CIImage(color: .black).cropped(to: rect)
        var style = preset.style
        if style.size < 0.06 { style.size = 0.06 }   // keep tiny styles readable in a small card
        let text = TextRenderer.image(style.uppercase ? preset.text.uppercased() : preset.text, style, size, visible: nil)
        return CIContext().createCGImage((text?.composited(over: background) ?? background).cropped(to: rect), from: rect)
    }
}
