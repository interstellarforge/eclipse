import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func cm(_ ms: Ms) -> CMTime { CMTime(value: ms, timescale: 1000) }

extension Asset {
    /// Reads duration and track kinds from a media file. A photo becomes a still-picture video (your original is untouched).
    public static func load(url: URL) async throws -> Asset {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), type.conforms(to: .image) {
            var asset = try await loadMedia(url: try StillVideo.make(from: url))
            asset.isStill = true; asset.name = url.lastPathComponent
            return asset
        }
        return try await loadMedia(url: url)
    }

    static func loadMedia(url: URL) async throws -> Asset {
        let av = AVURLAsset(url: url)
        let duration = try await av.load(.duration)
        let video = try await av.loadTracks(withMediaType: .video)
        let audio = try await av.loadTracks(withMediaType: .audio)
        guard !video.isEmpty || !audio.isEmpty else { throw EditError.invalid("no audio or video track") }
        return Asset(url: url, duration: Ms(duration.seconds * 1000), hasVideo: !video.isEmpty, hasAudio: !audio.isEmpty)
    }

    public func thumbnail(maxSize: CGSize = CGSize(width: 320, height: 180)) async -> CGImage? {
        guard hasVideo else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = maxSize
        return try? await gen.image(at: cm(min(500, duration / 2))).image
    }
}

/// Everything the player and the exporter need to render the project.
public struct BuiltComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition?
    public let audioMix: AVMutableAudioMix?
}

/// Builds the AVFoundation composition used for preview and export, so both render identically.
/// Consecutive clips on a track alternate between two lanes so a transition can overlap them.
public enum CompositionBuilder {
    /// `renderSize` overrides the canvas (exports at another resolution); everything is drawn relative to the frame.
    public static func build(_ p: Project, renderSize: CGSize? = nil) async throws -> BuiltComposition {
        let comp = AVMutableComposition()
        var lanes: [String: AVMutableCompositionTrack] = [:]
        var audioParams: [String: AVMutableAudioMixInputParameters] = [:]
        var refs: [UUID: ClipRef] = [:]
        let duckIntervals = Self.duckIntervals(p)

        func lane(_ key: String, _ type: AVMediaType) -> AVMutableCompositionTrack? {
            if let t = lanes[key] { return t }
            let t = comp.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
            lanes[key] = t
            return t
        }

        for (ti, track) in p.tracks.enumerated() where track.kind != .text {
            let sorted = track.clips.sorted { $0.start < $1.start }
            for (ci, clip) in sorted.enumerated() {
                guard let aid = clip.assetID, let asset = p.assets.first(where: { $0.id == aid }),
                      FileManager.default.fileExists(atPath: asset.url.path) else { continue }   // missing media is skipped, not fatal
                let av = AVURLAsset(url: asset.url)
                let range = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.sourceLength))
                let sped = CMTimeRange(start: cm(clip.start), duration: cm(clip.sourceLength))   // where the source lands before retiming
                if track.kind == .video, !track.hidden, asset.hasVideo,
                   let src = try await av.loadTracks(withMediaType: .video).first,
                   let vt = lane("v\(ti)-\(ci % 2)", .video) {
                    try vt.insertTimeRange(range, of: src, at: cm(clip.start))
                    if clip.speed != 1 { vt.scaleTimeRange(sped, toDuration: cm(clip.duration)) }
                    let transform = try await src.load(.preferredTransform)
                    refs[clip.id] = ClipRef(trackID: vt.trackID, orientation: orientation(of: transform), opacity: clip.opacity,
                                            scale: clip.scale, offsetX: clip.offsetX, offsetY: clip.offsetY, look: clip.look, effects: clip.effects, keyframes: clip.keyframes,
                                            start: clip.start, end: clip.end, fadeIn: clip.fadeIn, fadeOut: clip.fadeOut)
                }
                if asset.hasAudio, !clip.muted, !track.muted, let src = try await av.loadTracks(withMediaType: .audio).first,
                   let at = lane("a\(ti)-\(ci % 2)", .audio) {
                    try at.insertTimeRange(range, of: src, at: cm(clip.start))
                    if clip.speed != 1 { at.scaleTimeRange(sped, toDuration: cm(clip.duration)) }
                    let params = audioParams["a\(ti)-\(ci % 2)"]
                        ?? AVMutableAudioMixInputParameters(track: at)
                    audioParams["a\(ti)-\(ci % 2)"] = params
                    let points = gainPoints(clip, previous: ci > 0 ? sorted[ci - 1] : nil, next: ci + 1 < sorted.count ? sorted[ci + 1] : nil,
                                            ducks: track.duck ? duckIntervals : [], duckLevel: track.duckLevel)
                    params.setVolume(points[0].gain, at: cm(points[0].time))
                    for (x, y) in zip(points, points.dropFirst()) where y.time > x.time {
                        params.setVolumeRamp(fromStartVolume: x.gain, toEndVolume: y.gain, timeRange: CMTimeRange(start: cm(x.time), end: cm(y.time)))
                    }
                }
            }
        }

        var audioMix: AVMutableAudioMix?
        if !audioParams.isEmpty {
            audioMix = AVMutableAudioMix()
            audioMix?.inputParameters = Array(audioParams.values)
        }

        var videoComposition: AVMutableVideoComposition?
        if !refs.isEmpty {
            let vc = AVMutableVideoComposition()
            vc.renderSize = renderSize ?? CGSize(width: p.width, height: p.height)
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(p.fps))
            vc.customVideoCompositorClass = Compositor.self
            vc.instructions = instructions(p, refs: refs, total: comp.duration)
            videoComposition = vc
        }
        return BuiltComposition(composition: comp, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// Splits the timeline at every clip edge; each segment gets the layers visible in it, bottom to top.
    private static func instructions(_ p: Project, refs: [UUID: ClipRef], total: CMTime) -> [Instruction] {
        let totalMs = Ms((total.seconds * 1000).rounded())
        var points: Set<Ms> = [0, totalMs]
        for t in p.tracks where t.kind != .audio { for c in t.clips { points.insert(c.start); points.insert(c.end) } }
        let sorted = points.filter { $0 >= 0 && $0 <= totalMs }.sorted()
        var result: [Instruction] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let mid = (a + b) / 2
            var layers: [Layer] = []
            for track in p.tracks.reversed() where track.kind == .video {   // first track is on top
                let active = track.clips.filter { $0.start <= mid && mid < $0.end }.sorted { $0.start < $1.start }
                if active.count >= 2, let f = refs[active[0].id], let t = refs[active[1].id] {
                    let type = p.transitions.first { $0.fromClip == active[0].id && $0.toClip == active[1].id }?.type
                    layers.append(.transition(from: f, to: t, type: type ?? .crossfade,
                                              start: active[1].start, end: active[0].end))
                } else if let c = active.first, let ref = refs[c.id] {
                    layers.append(.clip(ref))
                }
                for g in active where g.generator != nil && !track.hidden {
                    layers.append(.generator(GeneratorLayer(kind: g.generator!, amount: g.generatorAmount, opacity: g.opacity, start: g.start, end: g.end, fadeIn: g.fadeIn, fadeOut: g.fadeOut)))
                }
            }
            for track in p.tracks where track.kind == .text && !track.hidden {
                for c in track.clips where c.start <= mid && mid < c.end { layers.append(.text(TextLayer(string: c.text ?? "", style: c.style, start: c.start, end: c.end, fadeIn: c.fadeIn, fadeOut: c.fadeOut))) }
            }
            let end = b == totalMs ? total : cm(b)
            result.append(Instruction(timeRange: CMTimeRange(start: cm(a), end: end), layers: layers))
        }
        return result
    }

    /// Time spans where other sound plays (clip sound, voice-overs), so ducking tracks can dip under it.
    static func duckIntervals(_ p: Project) -> [(Ms, Ms)] {
        var spans: [(Ms, Ms)] = []
        for track in p.tracks where !track.duck && !track.muted && track.kind != .text {
            for clip in track.clips where clip.duration >= 1_500 && clip.volume > 0.05 && !clip.muted {
                if let a = p.assets.first(where: { $0.id == clip.assetID }), a.hasAudio { spans.append((clip.start, clip.end)) }
            }
        }
        var merged: [(Ms, Ms)] = []
        for s in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, s.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, s.1) } else { merged.append(s) }
        }
        return merged
    }

    /// Volume breakpoints of one audio clip: volume x fades x transition overlaps x ducking, as straight pieces between points.
    static func gainPoints(_ clip: Clip, previous: Clip?, next: Clip?, ducks: [(Ms, Ms)], duckLevel: Double = 0.3) -> [(time: Ms, gain: Float)] {
        let fadeIn = min(clip.fadeIn, clip.duration), fadeOut = min(clip.fadeOut, clip.duration - fadeIn)
        let headEnd: Ms? = previous.flatMap { $0.end > clip.start ? min($0.end, clip.end) : nil }
        let tailStart: Ms? = next.flatMap { $0.start < clip.end ? max($0.start, clip.start) : nil }
        let level = duckLevel, ramp: Ms = 250
        var times: Set<Ms> = [clip.start, clip.end]
        if let headEnd { times.insert(headEnd) } else if fadeIn > 0 { times.insert(clip.start + fadeIn) }
        if let tailStart { times.insert(tailStart) } else if fadeOut > 0 { times.insert(clip.end - fadeOut) }
        for (ds, de) in ducks where de > clip.start && ds < clip.end {
            for t in [ds - ramp, ds, de, de + ramp] where t > clip.start && t < clip.end { times.insert(t) }
        }
        func gain(_ t: Ms) -> Float {
            var g = clip.volume
            if let headEnd { g *= t >= headEnd ? 1 : Double(t - clip.start) / Double(max(1, headEnd - clip.start)) }
            else if fadeIn > 0 { g *= min(1, Double(t - clip.start) / Double(fadeIn)) }
            if let tailStart { g *= t <= tailStart ? 1 : Double(clip.end - t) / Double(max(1, clip.end - tailStart)) }
            else if fadeOut > 0 { g *= min(1, Double(clip.end - t) / Double(fadeOut)) }
            var duck = 1.0
            for (ds, de) in ducks {
                var d = 1.0
                if t >= ds && t <= de { d = level }
                else if t < ds && t > ds - ramp { d = 1 - (1 - level) * Double(t - (ds - ramp)) / Double(ramp) }
                else if t > de && t < de + ramp { d = level + (1 - level) * Double(t - de) / Double(ramp) }
                duck = min(duck, d)
            }
            return Float(g * duck)
        }
        return times.sorted().map { (time: $0, gain: gain($0)) }
    }

    private static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

public enum FrameRenderer {
    /// Renders one composited frame (transitions and titles included) as PNG, scaled to fit `maxSize`.
    public static func png(_ p: Project, atMs ms: Ms, maxSize: Int = 640) async throws -> Data {
        let built = try await CompositionBuilder.build(p)
        guard built.videoComposition != nil else { throw EditError.invalid("project has no video") }
        let gen = AVAssetImageGenerator(asset: built.composition)
        gen.videoComposition = built.videoComposition
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let image = try await gen.image(at: cm(max(0, min(ms, p.duration - 1)))).image
        return try pngData(image)
    }
}

func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw EditError.invalid("png encoding failed")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw EditError.invalid("png encoding failed") }
    return data as Data
}
