import Foundation

public struct AutoMovieOptions {
    public var targetMs: Ms = 30_000
    public var transitionMs: Ms = 400
    public var title: String?
    public var music: Asset?
    public init(targetMs: Ms = 30_000, transitionMs: Ms = 400, title: String? = nil, music: Asset? = nil) {
        self.targetMs = targetMs; self.transitionMs = transitionMs; self.title = title; self.music = music
    }
}

/// GoPro-style highlight reel: scores every clip, keeps the most active moments, joins them with
/// crossfades and (optionally) cuts on the beat of a music track. Planning is pure; `apply` edits the timeline.
public struct AutoMoviePlan {
    struct Segment { var asset: Asset; var sourceIn: Ms; var duration: Ms }
    var segments: [Segment]
    var transitionMs: Ms
    var title: String?
    var music: (asset: Asset, grid: BeatGrid)?
    public var bpm: Double? { music?.grid.bpm }
    public var segmentCount: Int { segments.count }

    public func apply(to editor: Editor) throws {
        guard editor.project.tracks.flatMap(\.clips).isEmpty else {
            throw EditError.invalid("auto movie needs an empty timeline; remove the clips first")
        }
        guard !segments.isEmpty else { throw EditError.invalid("no usable video clips") }
        // Adjacent clips first; each transition then pulls the following clips earlier by its length.
        var clips: [Clip] = []
        var start: Ms = 0
        for s in segments {
            clips.append(try editor.addClip(asset: s.asset, start: start, sourceIn: s.sourceIn, duration: s.duration))
            start += s.duration
        }
        for c in clips.dropLast() { try editor.addTransition(after: c.id, type: .crossfade, duration: transitionMs) }
        let total = editor.project.duration
        if let title { try editor.addTitle(title, start: 0, duration: min(3_000, total)) }
        guard let music else { return }
        for c in clips { try editor.apply(.setVolume(c.id, volume: 0.3, fadeIn: 0, fadeOut: 0)) }   // music leads
        let length = min(total, music.asset.duration - music.grid.firstBeatMs)
        let track = UUID()
        try editor.apply(.addTrack(id: track, kind: .audio))
        let m = try editor.addClip(asset: music.asset, start: 0, sourceIn: music.grid.firstBeatMs, duration: length, track: track)
        try editor.apply(.setVolume(m.id, volume: 0.9, fadeIn: 0, fadeOut: min(1_500, length)))
    }
}

public enum AutoMovie {
    /// Analysis only: safe to call off the main actor.
    public static func plan(videos: [Asset], options: AutoMovieOptions) async throws -> AutoMoviePlan {
        let videos = videos.filter(\.hasVideo)
        guard !videos.isEmpty else { throw EditError.invalid("no video clips to use") }
        let d = options.transitionMs
        var grid: BeatGrid?
        if let music = options.music { grid = try await BeatTracker.analyze(url: music.url) }
        // Segment length: ~3 s, rounded to whole beats when there is music.
        let base: Ms = grid.map { Ms((Double(max(2, Int((3_000 / $0.periodMs).rounded()))) * $0.periodMs).rounded()) } ?? 3_000
        let count = max(1, Int((Double(options.targetMs) / Double(base)).rounded()))
        let window = base + d

        struct Candidate { var asset: Int; var start: Ms; var length: Ms; var score: Double }
        var candidates: [Candidate] = []
        for (i, a) in videos.enumerated() {
            let length = min(window, a.duration)
            guard length >= 500 else { continue }
            let analysis = await ClipAnalyzer.analyze(a)
            var starts = Array(stride(from: Ms(0), through: a.duration - length, by: Int(max(500, analysis.binMs))))
            if starts.last != a.duration - length { starts.append(a.duration - length) }
            candidates += starts.map { Candidate(asset: i, start: $0, length: length, score: analysis.score(from: $0, length: length)) }
        }
        func clashes(_ c: Candidate, _ chosen: [Candidate]) -> Bool {
            chosen.contains { $0.asset == c.asset && c.start < $0.start + $0.length && $0.start < c.start + c.length }
        }
        var chosen: [Candidate] = []
        // Pass 1: best moment of every clip (strongest clips first); pass 2: fill with the best remaining moments.
        let bestPerAsset = Dictionary(grouping: candidates, by: \.asset).compactMap { $0.value.max { $0.score < $1.score } }
        for c in bestPerAsset.sorted(by: { $0.score > $1.score }) where chosen.count < count { chosen.append(c) }
        for c in candidates.sorted(by: { $0.score > $1.score }) where chosen.count < count && !clashes(c, chosen) { chosen.append(c) }
        chosen.sort { ($0.asset, $0.start) < ($1.asset, $1.start) }

        let segments = chosen.enumerated().map { i, c in
            AutoMoviePlan.Segment(asset: videos[c.asset], sourceIn: c.start,
                                  duration: i == chosen.count - 1 ? min(c.length, base) : c.length)
        }
        return AutoMoviePlan(segments: segments, transitionMs: d, title: options.title,
                             music: options.music.flatMap { m in grid.map { (m, $0) } })
    }
}
