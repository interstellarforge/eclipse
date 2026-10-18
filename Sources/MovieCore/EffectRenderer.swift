import CoreImage
import CoreGraphics
import Vision

/// Draws the scene effects. The compositor (preview/export) and the Effects tab previews both call this.
public enum EffectRenderer {
    /// `image` is the clip's frame fitted into the canvas. `progress` runs 0...1 over the clip, `seconds` since its start.
    public static func apply(_ e: Effect, to image: CIImage, size: CGSize, progress: Double, seconds: Double, duration: Double) -> CIImage {
        let a = min(max(e.amount, 0), 1)
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)
        let frame = Int(seconds * 30)
        switch e.type {
        case .kenBurnsIn: return zoom(image, 1 + 0.25 * a * progress, size)
        case .kenBurnsOut: return zoom(image, 1 + 0.25 * a * (1 - progress), size)
        case .panLeft: return move(zoom(image, 1 + 0.15 * a, size), (0.5 - progress) * 0.15 * a * w, 0)
        case .panRight: return move(zoom(image, 1 + 0.15 * a, size), (progress - 0.5) * 0.15 * a * w, 0)
        case .shake:
            let dx = (rand(frame, 1) - 0.5) * 0.04 * a * w, dy = (rand(frame, 2) - 0.5) * 0.04 * a * h
            let angle = (rand(frame, 3) - 0.5) * 0.03 * a
            let t = CGAffineTransform(translationX: -w / 2, y: -h / 2).concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(scaleX: 1 + 0.06 * a, y: 1 + 0.06 * a))
                .concatenating(CGAffineTransform(translationX: w / 2 + dx, y: h / 2 + dy))
            return image.transformed(by: t)
        case .pulse: return zoom(image, 1 + 0.07 * a * (0.5 + 0.5 * sin(2 * .pi * 2 * seconds)), size)
        case .glow:
            return image.clampedToExtent().applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 8 + 28 * a, kCIInputIntensityKey: 0.4 + 1.2 * a]).cropped(to: image.extent)
        case .flash:
            let alpha = a * max(0, 1 - seconds / 0.5)
            return alpha > 0.001 ? overlay(CIColor.white, alpha, rect).composited(over: image) : image
        case .lightLeak:
            let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: w * (0.1 + 0.8 * progress), y: h * 0.85), "inputRadius0": 0, "inputRadius1": w * 0.65,
                "inputColor0": CIColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.95 * a), "inputColor1": CIColor(red: 1, green: 0.3, blue: 0.2, alpha: 0)
            ])?.outputImage?.cropped(to: rect)
            return gradient?.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: image.extent) ?? image
        case .cinemaBars:
            let bar = h * 0.13 * a
            let black = CIImage(color: .black)
            return black.cropped(to: CGRect(x: 0, y: 0, width: w, height: bar)).composited(over:
                black.cropped(to: CGRect(x: 0, y: h - bar, width: w, height: bar)).composited(over: image))
        case .grain:
            return grainImage(rect, frame).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45 * a)]).composited(over: image).cropped(to: image.extent)
        case .vhs:
            let split = chromatic(image, 0.006 * w * (0.5 + a), rect)
            let lines = CIFilter(name: "CIStripesGenerator", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputWidth": max(1.5, h / 270),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.28 * a), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0), "inputSharpness": 1])?
                .outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect)
            let toned = split.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2, kCIInputContrastKey: 1.05])
            let noisy = grainImage(rect, frame).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.25 * a)]).composited(over: toned)
            return (lines?.composited(over: noisy) ?? noisy).cropped(to: image.extent)
        case .chromatic: return chromatic(image, 0.012 * w * a, rect)
        case .glitch:
            let burst = rand(frame / 3, 4) < 0.35 * (0.4 + a)   // bursts last a few frames
            guard burst else { return chromatic(image, 0.002 * w * a, rect) }
            var out = chromatic(image, 0.02 * w * a, rect)
            for i in 0..<3 {
                let y = rand(frame / 3, 10 + i) * h * 0.85, band = h * (0.03 + 0.07 * rand(frame / 3, 20 + i))
                let shift = (rand(frame / 3, 30 + i) - 0.5) * 0.18 * a * w
                out = image.cropped(to: CGRect(x: 0, y: y, width: w, height: band)).transformed(by: CGAffineTransform(translationX: shift, y: 0)).composited(over: out)
            }
            return out.cropped(to: image.extent)
        case .blurIn: return blur(image, w * 0.04 * a * (1 - progress))
        case .blurOut: return blur(image, w * 0.04 * a * progress)
        case .posterize:
            return image.applyingFilter("CIColorPosterize", parameters: ["inputLevels": max(2, 9 - 7 * a)])
        case .duotone:
            let tinted = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.2])
                .applyingFilter("CIFalseColor", parameters: ["inputColor0": CIColor(red: 0.05, green: 0.02, blue: 0.3), "inputColor1": CIColor(red: 1, green: 0.78, blue: 0.4)])
            return mix(tinted, over: image, amount: min(1, a * 1.4))
        case .comic:
            return mix(image.applyingFilter("CIComicEffect"), over: image, amount: min(1, a * 1.4)).cropped(to: image.extent)
        case .mirror:
            let half = image.cropped(to: CGRect(x: 0, y: 0, width: w / 2, height: h))
            let flipped = half.transformed(by: CGAffineTransform(scaleX: -1, y: 1)).transformed(by: CGAffineTransform(translationX: w, y: 0))
            return flipped.composited(over: image)
        case .removeBackground:
            return PersonCutout.apply(image) ?? image   // if Vision fails the frame is left as it is
        case .vignette:
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.6 + 1.6 * a, kCIInputRadiusKey: 1.6])
        case .tiltShift:
            let soft = blur(image, w * 0.012 * (0.4 + a))
            func band(_ from: Double, _ to: Double) -> CIImage {
                CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: h * from), "inputPoint1": CIVector(x: 0, y: h * to),
                                                                "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: rect)
            }
            let mask = band(1, 0.68).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: band(0, 0.32)])
            return soft.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]).cropped(to: image.extent)
        case .punchIn:
            return zoom(image, 1 + 0.22 * a * max(0, 1 - seconds / 0.45), size)
        case .dreamBlur:
            let soft = mix(blur(image, w * (0.006 + 0.014 * a)), over: image, amount: 0.55)
            return soft.clampedToExtent().applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 16 + 24 * a, kCIInputIntensityKey: 0.5 + 0.6 * a]).cropped(to: image.extent)
        case .halftone:
            let dots = image.clampedToExtent().applyingFilter("CICMYKHalftone", parameters: [kCIInputWidthKey: max(4, w / 90), "inputSharpness": 0.8]).cropped(to: image.extent)
            return mix(dots, over: image, amount: min(1, a * 1.4))
        case .pixelate:
            return image.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(2, w * (0.004 + 0.04 * a))]).cropped(to: image.extent)
        case .neonEdges:
            let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3 + 9 * a]).applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.1, kCIInputContrastKey: 1.6])
            let dark = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.55])
            return edges.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: dark]).cropped(to: image.extent)
        case .invert:
            return mix(image.applyingFilter("CIColorInvert"), over: image, amount: a)
        case .kaleidoscope:
            let k = image.clampedToExtent().applyingFilter("CIKaleidoscope", parameters: ["inputCount": 6, kCIInputCenterKey: CIVector(x: w / 2, y: h / 2), kCIInputAngleKey: progress * .pi]).cropped(to: image.extent)
            return mix(k, over: image, amount: min(1, a * 1.25))
        case .fisheye:
            return image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [kCIInputCenterKey: CIVector(x: w / 2, y: h / 2), kCIInputRadiusKey: w * 0.55, kCIInputScaleKey: 0.7 * a]).cropped(to: image.extent)
        case .strobe:
            let on = seconds * 5 - floor(seconds * 5) < 0.18
            return on ? overlay(CIColor.white, 0.85 * a, rect).composited(over: image) : image
        case .dutchTilt:
            let t = CGAffineTransform(translationX: -w / 2, y: -h / 2).concatenating(CGAffineTransform(rotationAngle: 0.2 * a))
                .concatenating(CGAffineTransform(scaleX: 1 + 0.4 * a, y: 1 + 0.4 * a)).concatenating(CGAffineTransform(translationX: w / 2, y: h / 2))
            return image.transformed(by: t).cropped(to: image.extent)
        case .chromaKey:
            return image.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": 48, "inputCubeData": keyCube(hex: e.colorHex ?? "00FF00", amount: a)])
        }
    }

    // MARK: Previews

    /// Looping preview of one effect on `source` (or a built-in demo scene). 3 second "clip" with a hold at the end.
    public static func previewFrames(_ type: EffectType, source: CGImage?, size: CGSize = CGSize(width: 240, height: 135), count: Int = 36) -> [CGImage] {
        let rect = CGRect(origin: .zero, size: size)
        let context = CIContext()
        let base: CIImage
        if type == .chromaKey { base = demoScene(size, greenScreen: true) }
        else if let source {
            let img = CIImage(cgImage: source)
            let s = max(size.width / img.extent.width, size.height / img.extent.height)
            let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
            base = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX,
                                                           y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY)).cropped(to: rect)
        } else { base = demoScene(size, greenScreen: false) }
        let backdrop = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputColor0": CIColor(red: 0.25, green: 0.25, blue: 0.3),
                                                                             "inputColor1": CIColor(red: 0.15, green: 0.15, blue: 0.18), "inputWidth": size.width / 12, "inputSharpness": 1])!
            .outputImage!.cropped(to: rect)
        let hold = count / 8
        return (0..<count).compactMap { i in
            let p = min(1, Double(i) / Double(count - hold))
            var frame = apply(Effect(type), to: base, size: size, progress: p, seconds: p * 3, duration: 3)
            if type == .chromaKey || type == .removeBackground { frame = frame.composited(over: backdrop) }
            return context.createCGImage(frame.cropped(to: rect), from: rect)
        }
    }

    /// A simple scene with sky, ground, sun and a figure, so effects have something to act on.
    public static func demoScene(_ size: CGSize, greenScreen: Bool) -> CIImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let W = size.width, H = size.height
        if greenScreen {
            ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        } else {
            let colors = [CGColor(red: 0.98, green: 0.62, blue: 0.35, alpha: 1), CGColor(red: 0.35, green: 0.55, blue: 0.9, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
            ctx.setFillColor(red: 0.12, green: 0.2, blue: 0.14, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H * 0.28))
            ctx.setFillColor(red: 1, green: 0.95, blue: 0.7, alpha: 1); ctx.fillEllipse(in: CGRect(x: W * 0.68, y: H * 0.62, width: H * 0.22, height: H * 0.22))
        }
        ctx.setFillColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: W * 0.4, y: H * 0.5, width: H * 0.2, height: H * 0.2))
        ctx.fill(CGRect(x: W * 0.4 + H * 0.02, y: H * 0.12, width: H * 0.16, height: H * 0.4))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    // MARK: Helpers

    private static func rand(_ seed: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 73_856_093 &+ salt &* 19_349_663 &+ 12_345)
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        x = x &* 0x2545F4914F6CDD1D
        return Double(x >> 11) / Double(1 << 53)
    }

    private static func zoom(_ image: CIImage, _ s: Double, _ size: CGSize) -> CIImage {
        guard s != 1 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(scaleX: s, y: s)).concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
    }

    private static func move(_ image: CIImage, _ dx: Double, _ dy: Double) -> CIImage { image.transformed(by: CGAffineTransform(translationX: dx, y: dy)) }

    private static func blur(_ image: CIImage, _ radius: Double) -> CIImage {
        guard radius >= 0.5 else { return image }
        return image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: image.extent)
    }

    private static func overlay(_ color: CIColor, _ alpha: Double, _ rect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)).cropped(to: rect)
    }

    private static func mix(_ top: CIImage, over bottom: CIImage, amount: Double) -> CIImage {
        top.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount)]).composited(over: bottom)
    }

    private static func grainImage(_ rect: CGRect, _ frame: Int) -> CIImage {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: CGAffineTransform(translationX: rand(frame, 7) * 500, y: rand(frame, 8) * 500))
        return noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]).cropped(to: rect)
    }

    private static func chromatic(_ image: CIImage, _ shift: Double, _ rect: CGRect) -> CIImage {
        func channel(_ r: Double, _ g: Double, _ b: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                                                              "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        }
        let red = move(channel(1, 0, 0), shift, 0), green = channel(0, 1, 0), blue = move(channel(0, 0, 1), -shift, 0)
        let rg = red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
        return rg.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue]).cropped(to: image.extent)
    }

    nonisolated(unsafe) private static var cubeCache: [String: Data] = [:]
    private static let cubeLock = NSLock()

    /// 3D colour table making colours near `hex` transparent (distance measured in chroma, so brightness changes of the screen still key).
    private static func keyCube(hex: String, amount: Double) -> Data {
        let name = "\(hex)-\(Int(amount * 100))"
        cubeLock.lock(); defer { cubeLock.unlock() }
        if let cached = cubeCache[name] { return cached }
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x00FF00
        func chroma(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double) {
            (-0.169 * r - 0.331 * g + 0.5 * b, 0.5 * r - 0.419 * g - 0.081 * b)
        }
        let key = chroma(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        let n = 48
        let tolerance = 0.06 + 0.22 * amount, soft = 0.10
        var data = [Float](); data.reserveCapacity(n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let rf = Double(r) / Double(n - 1), gf = Double(g) / Double(n - 1), bf = Double(b) / Double(n - 1)
            let c = chroma(rf, gf, bf)
            let distance = ((c.0 - key.0) * (c.0 - key.0) + (c.1 - key.1) * (c.1 - key.1)).squareRoot()
            let alpha = min(1, max(0, (distance - tolerance) / soft))
            // spill suppression: pull green out of what remains near the key
            let despill = min(gf, max(rf, bf) + 0.02)
            let gOut = alpha < 1 ? despill : gf
            data += [Float(rf * alpha), Float(gOut * alpha), Float(bf * alpha), Float(alpha)]
        } } }
        let result = data.withUnsafeBufferPointer { Data(buffer: $0) }
        cubeCache[name] = result
        return result
    }
}

/// Person cut-out with Apple's on-device segmentation. Everything that is not a person becomes transparent.
enum PersonCutout {
    static func apply(_ image: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do { try VNImageRequestHandler(ciImage: image, options: [:]).perform([request]) } catch { return nil }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: buffer)
        let e = image.extent
        mask = mask.transformed(by: CGAffineTransform(scaleX: e.width / mask.extent.width, y: e.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: e)
        return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
    }
}
