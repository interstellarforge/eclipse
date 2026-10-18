import AVFoundation
import CoreImage
import Foundation
import ImageIO
import MovieCore

/// Small shared test media, created once per run.
struct Fixtures {
    let red: Asset, blue: Asset, busy: Asset
    let urls: [URL]

    static func make() async throws -> Fixtures {
        func video(_ name: String, _ seconds: Int, _ color: (UInt8, UInt8, UInt8), flicker: Int? = nil) async throws -> (URL, Asset) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fx-\(name)-\(UUID()).mp4")
            try await makeTestVideo(at: url, seconds: seconds, bgra: color, flickerFrom: flicker)
            return (url, try await Asset.load(url: url))
        }
        let r = try await video("red", 4, (0, 0, 255)), b = try await video("blue", 4, (255, 0, 0)), y = try await video("busy", 8, (0, 128, 255), flicker: 150)
        return Fixtures(red: r.1, blue: b.1, busy: y.1, urls: [r.0, b.0, y.0])
    }

    func cleanUp() { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
}

/// RGBA pixels of a PNG.
func decodePNG(_ png: Data) -> (w: Int, h: Int, px: [UInt8]) {
    let img = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
    var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let c = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return (img.width, img.height, px)
}

/// Colour at a fractional position (0,0 = top-left).
func pixel(_ p: (w: Int, h: Int, px: [UInt8]), _ fx: Double, _ fy: Double) -> (r: Int, g: Int, b: Int) {
    let i = (Int(fy * Double(p.h - 1)) * p.w + Int(fx * Double(p.w - 1))) * 4
    return (Int(p.px[i]), Int(p.px[i + 1]), Int(p.px[i + 2]))
}

