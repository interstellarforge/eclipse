import CoreImage
import Foundation
import MovieCore

func renderBytes(_ image: CIImage, _ size: CGSize) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
    CIContext().render(image, toBitmap: &px, rowBytes: Int(size.width) * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    return px
}

func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double { zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) }

func runTransitionChecks() async throws {
    let size = CGSize(width: 192, height: 108), rect = CGRect(origin: .zero, size: size)
    // Two busy pictures so every transition has something to move.
    let a = EffectRenderer.demoScene(size, greenScreen: false)
    let b = CIImage(color: CIColor(red: 0.1, green: 0.3, blue: 0.9)).cropped(to: rect).composited(over: CIImage(color: .black).cropped(to: rect))
        .applyingFilter("CIColorInvert").cropped(to: rect)
    let refA = renderBytes(a, size), refB = renderBytes(b, size)
    check(TransitionType.allCases.count >= 47, "47+ transitions: \(TransitionType.allCases.count)")
    check(Set(TransitionType.allCases.map(\.title)).count == TransitionType.allCases.count, "transition titles are unique")
    for type in TransitionType.allCases {
        let start = renderBytes(TransitionRenderer.blend(a, b, type, 0, size).cropped(to: rect), size)
        let end = renderBytes(TransitionRenderer.blend(a, b, type, 1, size).cropped(to: rect), size)
        check(meanDifference(start, refA) < 1 && meanDifference(end, refB) < 1, "\(type) starts as A and ends as B")
        if type != .pixelate {
            let moved = [0.25, 0.5, 0.75].contains { p in
                let f = renderBytes(TransitionRenderer.blend(a, b, type, p, size).cropped(to: rect), size)
                return meanDifference(f, refA) > 2 && meanDifference(f, refB) > 2
            }
            check(moved, "\(type) shows a mix in between")
        }
    }
}
