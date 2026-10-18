import AVFoundation
import CoreGraphics

/// Two moments in two clips that look alike (colour, shape, where the bright thing sits), so a hard cut between them feels like one move.
public struct MatchCut {
    public var assetA: UUID, timeA: Ms        // end the first clip here
    public var assetB: UUID, timeB: Ms        // start the second clip here
    public var score: Double                  // 0...1
    public var reason: String
    public init(assetA: UUID, timeA: Ms, assetB: UUID, timeB: Ms, score: Double, reason: String) {
        self.assetA = assetA; self.timeA = timeA; self.assetB = assetB; self.timeB = timeB; self.score = score; self.reason = reason
    }
}

/// What a frame looks like, in a few numbers.
struct FrameLook {
    var hue: [Double]          // 12 bins weighted by saturation, sums to 1
    var tone: [Double]         // 4 brightness bins
    var layout: [Double]       // 8x8 brightness grid, mean removed
    var blobX = 0.5, blobY = 0.5, blobArea = 0.0   // the brightest compact area
    var blobHue = -1.0, blobSaturation = 0.0       // its colour (hue 0...6), -1 when it has none
    var saturation = 0.0, brightness = 0.0

    init(_ image: CGImage) {
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        var hue = [Double](repeating: 0, count: 12), tone = [Double](repeating: 0, count: 4)
        var grid = [Double](repeating: 0, count: 64), gridCount = [Double](repeating: 0, count: 64)
        var lum = [Double](repeating: 0, count: n * n)
        var satSum = 0.0, lumSum = 0.0
        for y in 0..<n { for x in 0..<n {
            let i = (y * n + x) * 4
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), l = 0.299 * r + 0.587 * g + 0.114 * b, sat = mx > 0 ? (mx - mn) / mx : 0
            lum[y * n + x] = l; lumSum += l; satSum += sat
            if mx > mn {
                var h = mx == r ? (g - b) / (mx - mn) : mx == g ? 2 + (b - r) / (mx - mn) : 4 + (r - g) / (mx - mn)
                h = h < 0 ? h + 6 : h
                hue[Int(h / 6 * 12) % 12] += sat
            }
            tone[min(3, Int(l * 4))] += 1
            let cell = (y / 4) * 8 + x / 4
            grid[cell] += l; gridCount[cell] += 1
        } }
        let hueTotal = max(1e-9, hue.reduce(0, +)), toneTotal = Double(n * n)
        self.hue = hue.map { $0 / hueTotal }; self.tone = tone.map { $0 / toneTotal }
        let cells = zip(grid, gridCount).map { $0 / max(1, $1) }, mean = cells.reduce(0, +) / 64
        self.layout = cells.map { $0 - mean }
        saturation = satSum / Double(n * n); brightness = lumSum / Double(n * n)
        let peak = lum.max() ?? 0
        if peak > 0.2 {
            var sx = 0.0, sy = 0.0, count = 0.0, br = 0.0, bg = 0.0, bb = 0.0
            for y in 0..<n { for x in 0..<n where lum[y * n + x] > peak * 0.8 {
                sx += Double(x); sy += Double(y); count += 1
                let i = (y * n + x) * 4
                br += Double(px[i]) / 255; bg += Double(px[i + 1]) / 255; bb += Double(px[i + 2]) / 255
            } }
            blobX = sx / count / Double(n - 1); blobY = sy / count / Double(n - 1); blobArea = count / Double(n * n)
            let r = br / count, g = bg / count, b = bb / count, mx = max(r, g, b), mn = min(r, g, b)
            blobSaturation = mx > 0 ? (mx - mn) / mx : 0
            if mx > mn {
                let h = mx == r ? (g - b) / (mx - mn) : mx == g ? 2 + (b - r) / (mx - mn) : 4 + (r - g) / (mx - mn)
                blobHue = h < 0 ? h + 6 : h
            }
        }
    }

    func similarity(to o: FrameLook) -> Double {
        let colour = 1 - 0.5 * zip(hue, o.hue).reduce(0) { $0 + abs($1.0 - $1.1) } - 0.0
        let tones = 1 - 0.5 * zip(tone, o.tone).reduce(0) { $0 + abs($1.0 - $1.1) }
        let dot = zip(layout, o.layout).reduce(0) { $0 + $1.0 * $1.1 }
        let norm = (layout.reduce(0) { $0 + $1 * $1 }.squareRoot()) * (o.layout.reduce(0) { $0 + $1 * $1 }.squareRoot())
        let structure = norm > 1e-6 ? max(0, dot / norm) : 0.5
        let blob = max(0, 1 - 2 * ((blobX - o.blobX) * (blobX - o.blobX) + (blobY - o.blobY) * (blobY - o.blobY)).squareRoot() - 2 * abs(blobArea - o.blobArea))
        return max(0, min(1, 0.3 * colour + 0.15 * tones + 0.3 * structure + 0.25 * blob))
    }

    var description: String {
        let names = ["red", "orange", "yellow", "yellow-green", "green", "teal", "cyan", "blue", "blue-violet", "purple", "magenta", "pink"]
        let top = hue.enumerated().max { $0.element < $1.element }
        let colour = saturation < 0.12 ? "grey" : (top.map { names[$0.offset] } ?? "colourful")
        let blobColour = blobHue >= 0 && blobSaturation > 0.25 ? "\(names[Int(blobHue / 6 * 12) % 12]) " : ""
        let place = blobArea > 0.002 ? "a bright \(blobColour)shape \(blobX < 0.35 ? "on the left" : blobX > 0.65 ? "on the right" : "in the middle")" : "an even picture"
        return "\(brightness < 0.3 ? "dark" : brightness > 0.65 ? "bright" : "mid-toned") \(colour) with \(place)"
    }
}

public enum MatchCuts {
    /// Compares moments of the given clips and returns the best matching pairs (different clips), best first.
    public static func find(_ assets: [Asset], limit: Int = 5, minScore: Double = 0.6) async -> [MatchCut] {
        struct Sample { var asset: UUID; var time: Ms; var look: FrameLook }
        var samples: [Sample] = []
        for asset in assets where asset.hasVideo && asset.duration > 1_000 {
            let step = max(500, asset.duration / 50)
            let times = stride(from: Ms(250), to: asset.duration - 200, by: Int(step)).map { cm($0) }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 96, height: 96)
            gen.requestedTimeToleranceBefore = CMTime(value: 200, timescale: 1000); gen.requestedTimeToleranceAfter = CMTime(value: 200, timescale: 1000)
            for await result in gen.images(for: times) {
                if let image = try? result.image { samples.append(Sample(asset: asset.id, time: Ms((result.requestedTime.seconds * 1000).rounded()), look: FrameLook(image))) }
            }
        }
        var best: [String: [MatchCut]] = [:]   // per pair of clips only the best moment pair is kept
        for a in samples { for b in samples where a.asset != b.asset {
            let score = a.look.similarity(to: b.look)
            guard score >= minScore else { continue }
            let key = [a.asset.uuidString, b.asset.uuidString].sorted().joined()
            let cut = MatchCut(assetA: a.asset, timeA: a.time, assetB: b.asset, timeB: b.time, score: score, reason: "\(a.look.description) → \(b.look.description)")
            if let current = best[key]?.first, current.score >= score { continue }
            best[key] = [cut]
        } }
        return Array(best.values.compactMap(\.first).sorted { $0.score > $1.score }.prefix(limit))
    }
}

extension Editor {
    /// Puts the two moments next to each other at the end of the video track: clip A runs up to the match, clip B continues from it.
    @discardableResult
    public func addMatchCut(_ match: MatchCut, lead: Ms = 1_800, tail: Ms = 2_500) throws -> (Clip, Clip) {
        guard let a = project.assets.first(where: { $0.id == match.assetA }), let b = project.assets.first(where: { $0.id == match.assetB }) else { throw EditError.notFound }
        var first: Clip?, second: Clip?
        try transaction {
            let from = max(0, match.timeA - lead)
            first = try addClip(asset: a, sourceIn: from, duration: max(300, match.timeA - from))
            second = try addClip(asset: b, sourceIn: match.timeB, duration: min(tail, max(300, b.duration - match.timeB)))
        }
        return (first!, second!)
    }
}
