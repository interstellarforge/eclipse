import CoreImage

/// Colour work of a clip: one place for preview, export and the Templates / Color thumbnails.
public enum LookRenderer {
    public static func apply(_ look: Look, to image: CIImage, size: CGSize) -> CIImage {
        var out = image
        let extent = image.extent
        if look.brightness != 0 || look.contrast != 1 || look.saturation != 1 {
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: look.brightness, kCIInputContrastKey: look.contrast, kCIInputSaturationKey: look.saturation])
        }
        if look.warmth != 0 {   // moves the white point: warm adds red and takes blue away
            out = out.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - 2800 * look.warmth, y: 0)])
        }
        if look.splitAmount > 0, look.splitShadows != nil || look.splitHighlights != nil {
            out = out.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": 24, "inputCubeData": splitToneCube(look)])
        }
        if look.fade > 0 {   // blacks become grey: out = in * (1 - 0.3 f) + 0.12 f
            let k = 1 - 0.3 * look.fade, bias = 0.12 * look.fade
            out = out.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                                                                    "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
        }
        if look.sepia > 0 { out = out.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: look.sepia]) }
        if look.sharpen > 0 { out = out.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: look.sharpen * 1.4]) }
        if look.blur > 0 {
            out = out.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: look.blur * size.width * 0.02]).cropped(to: extent)
        }
        if look.vignette > 0 {
            out = out.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: look.vignette * 2, kCIInputRadiusKey: 2])
        }
        return out
    }

    nonisolated(unsafe) private static var cubeCache: [String: Data] = [:]
    private static let lock = NSLock()

    /// Colour table that tints dark areas with one colour and bright areas with another.
    private static func splitToneCube(_ look: Look) -> Data {
        let key = "\(look.splitShadows ?? "-")|\(look.splitHighlights ?? "-")|\(Int(look.splitAmount * 100))"
        lock.lock(); defer { lock.unlock() }
        if let cached = cubeCache[key] { return cached }
        func rgb(_ hex: String?) -> (Double, Double, Double)? {
            guard let hex, let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
            return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        }
        func chroma(_ c: (Double, Double, Double)) -> (Double, Double, Double) {   // the colour with its brightness removed
            let l = 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2
            return (c.0 - l, c.1 - l, c.2 - l)
        }
        let shadow = rgb(look.splitShadows).map(chroma) ?? (0, 0, 0), highlight = rgb(look.splitHighlights).map(chroma) ?? (0, 0, 0)
        let n = 24
        var data = [Float](); data.reserveCapacity(n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let rf = Double(r) / Double(n - 1), gf = Double(g) / Double(n - 1), bf = Double(b) / Double(n - 1)
            let l = 0.299 * rf + 0.587 * gf + 0.114 * bf
            let ws = pow(1 - l, 2) * look.splitAmount, wh = pow(l, 2) * look.splitAmount
            data += [Float(min(1, max(0, rf + shadow.0 * ws + highlight.0 * wh))), Float(min(1, max(0, gf + shadow.1 * ws + highlight.1 * wh))),
                     Float(min(1, max(0, bf + shadow.2 * ws + highlight.2 * wh))), 1]
        } } }
        let result = data.withUnsafeBufferPointer { Data(buffer: $0) }
        cubeCache[key] = result
        return result
    }
}
