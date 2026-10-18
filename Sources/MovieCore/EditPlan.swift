import Foundation

/// Builds a whole edit (cuts, joins, sound, looks, effects, titles, music, sound effects) from one edit decision list.
/// Everything happens in one transaction: one undo step, and nothing changes if any part is invalid.
@MainActor
enum EditPlan {
    static func apply(_ a: Args, editor: Editor, host: MCPHost) async throws -> String {
        guard let rawCuts = a.d["cuts"] as? [[String: Any]], !rawCuts.isEmpty else {
            throw ToolError("cuts must be a non-empty list of {asset_id, start_ms, end_ms, ...}")
        }
        let replace = a.d["replace"] as? Bool == true
        if !replace, editor.project.tracks.contains(where: { !$0.clips.isEmpty }) {
            throw ToolError("The timeline already has clips. Pass replace: true to start over (the user can undo), or change the existing clips with the other tools.")
        }

        // Resolve and check everything before touching the project.
        struct Cut { var asset: Asset; var start: Ms; var end: Ms; var args: Args }
        var cuts: [Cut] = []
        for (i, raw) in rawCuts.enumerated() {
            let c = Args(d: raw)
            guard let id = try? c.id("asset_id"), let asset = editor.project.assets.first(where: { $0.id == id }) else {
                throw ToolError("cut \(i): unknown asset_id (use the ids from get_project)")
            }
            guard asset.hasVideo else { throw ToolError("cut \(i): cuts need a video asset") }
            // A photo has no "source range": give duration_ms (default 3 s).
            let start = asset.isStill ? 0 : max(0, c.optMs("start_ms") ?? 0)
            let end = asset.isStill ? min(asset.duration, c.optMs("duration_ms") ?? 3_000) : min(asset.duration, c.optMs("end_ms") ?? asset.duration)
            guard end - start >= 200 else { throw ToolError("cut \(i): end_ms must be at least 200 ms after start_ms (the clip is \(asset.duration) ms long)") }
            if let name = c.optStr("transition"), !["none", "cut"].contains(name), TransitionType(rawValue: name) == nil {
                throw ToolError("cut \(i): unknown transition '\(name)'. Options: \(TransitionType.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            if case let look as String = c.d["look"], Look.preset(look) == nil {
                throw ToolError("cut \(i): unknown look '\(look)'. Options: \(Look.presetNames.joined(separator: ", "))")
            }
            for e in (c.d["effects"] as? [[String: Any]]) ?? [] where EffectType(rawValue: e["type"] as? String ?? "") == nil {
                throw ToolError("cut \(i): unknown effect '\(e["type"] as? String ?? "?")'. Call list_effects.")
            }
            cuts.append(Cut(asset: asset, start: start, end: end, args: c))
        }
        let titles = (a.d["titles"] as? [[String: Any]] ?? []).map(Args.init)
        let overlays = (a.d["overlays"] as? [[String: Any]] ?? []).map(Args.init)
        for o in overlays where GeneratorKind(rawValue: o.optStr("kind") ?? "") == nil { throw ToolError("unknown overlay '\(o.optStr("kind") ?? "?")'. Call list_overlays.") }
        if let problem = CreativeGuard.check(cuts: rawCuts, overlays: overlays.map(\.d)) { throw ToolError(problem) }
        var music: (asset: Asset, args: Args)?
        if let m = a.d["music"] as? [String: Any] {
            let margs = Args(d: m)
            if let name = margs.optStr("name") { music = (try await host.importMedia(try MusicLibrary.url(for: name)), margs) }
            else if let id = margs.optID("asset_id"), let asset = editor.project.assets.first(where: { $0.id == id }) { music = (asset, margs) }
            else { throw ToolError("music needs a built-in name (see list_sounds) or an asset_id") }
        }
        var sfx: [(asset: Asset, args: Args)] = []
        for raw in a.d["sfx"] as? [[String: Any]] ?? [] {
            let s = Args(d: raw)
            sfx.append((try await host.importMedia(try SoundEffects.url(for: try s.str("name"))), s))
        }

        var summary: [String] = []
        try editor.transaction {
            if replace { for t in editor.project.tracks { try editor.apply(.removeTrack(t.id)) } }
            if let canvas = a.optStr("canvas") {
                let sizes = ["16:9": (1920, 1080), "9:16": (1080, 1920), "1:1": (1080, 1080), "4:5": (1080, 1350)]
                guard let size = sizes[canvas] else { throw ToolError("canvas must be 16:9, 9:16, 1:1 or 4:5") }
                try editor.apply(.setFormat(width: size.0, height: size.1, fps: editor.project.fps))
            }
            var clipIDs: [UUID] = []
            for (i, cut) in cuts.enumerated() {
                let c = cut.args
                let clip = try editor.addClip(asset: cut.asset, start: nil, sourceIn: cut.start, duration: cut.end - cut.start)
                if let speed = c.optDouble("speed"), speed != 1 { try editor.apply(.setSpeed(clip.id, speed)) }
                var volume: Double? = nil
                if let sound = c.d["sound"] as? String {
                    if sound == "mute" { try editor.apply(.setMuted(clip.id, true)) }
                    else if sound != "keep" { throw ToolError("cut \(i): sound must be keep, mute or a number") }
                } else if let v = c.optDouble("sound") { volume = v }
                else if music != nil { volume = 0.3 }   // music leads unless the cut says otherwise
                let fadeIn = c.optMs("fade_in_ms") ?? 0, fadeOut = c.optMs("fade_out_ms") ?? 0
                if volume != nil || fadeIn > 0 || fadeOut > 0 {
                    let length = editor.project.tracks.flatMap(\.clips).first { $0.id == clip.id }?.duration ?? clip.duration
                    try editor.apply(.setVolume(clip.id, volume: volume ?? 1, fadeIn: min(fadeIn, length), fadeOut: min(fadeOut, max(0, length - min(fadeIn, length)))))
                }
                if let name = c.d["look"] as? String, let look = Look.preset(name) { try editor.apply(.setLook(clip.id, look)) }
                else if let dict = c.d["look"] as? [String: Any] { try editor.apply(.setLook(clip.id, Args(d: dict).look(Look()))) }
                if c.optDouble("scale") != nil || c.optDouble("offset_x") != nil || c.optDouble("offset_y") != nil || c.optDouble("opacity") != nil {
                    try editor.apply(.setTransform(clip.id, opacity: c.optDouble("opacity") ?? 1, scale: c.optDouble("scale") ?? 1,
                                                   offsetX: c.optDouble("offset_x") ?? 0, offsetY: c.optDouble("offset_y") ?? 0))
                }
                if let frames = c.d["keyframes"] as? [[String: Any]], !frames.isEmpty {
                    try editor.apply(.setKeyframes(clip.id, frames.map { Args(d: $0).keyframe() }))
                }
                for e in (c.d["effects"] as? [[String: Any]]) ?? [] {
                    let ea = Args(d: e)
                    try editor.apply(.addEffect(clip.id, Effect(EffectType(rawValue: try ea.str("type"))!, amount: ea.optDouble("amount"), colorHex: ea.optStr("color"))))
                }
                clipIDs.append(clip.id)
            }
            for (i, cut) in cuts.enumerated() where i > 0 {
                guard let name = cut.args.optStr("transition"), let type = TransitionType(rawValue: name) else { continue }
                try editor.addTransition(after: clipIDs[i - 1], type: type, duration: cut.args.optMs("transition_ms") ?? 500)
            }
            let all = editor.project.tracks.flatMap(\.clips)
            func cutStart(_ i: Int) -> Ms { all.first { $0.id == clipIDs[i] }?.start ?? 0 }
            for (i, id) in clipIDs.enumerated() {
                if let c = all.first(where: { $0.id == id }) {
                    summary.append("cut \(i): clip_id=\(id.uuidString) \(c.start)-\(c.end) ms (source \(cuts[i].start)-\(cuts[i].end), \(cuts[i].asset.url.lastPathComponent))")
                }
            }
            let total = editor.project.duration
            for t in titles {
                let preset = t.optStr("preset").flatMap(TitlePreset.named) ?? .center
                let clip = try editor.addTitle(try t.str("text"), start: max(0, t.optMs("start_ms") ?? 0), duration: t.optMs("duration_ms") ?? 2_500)
                try editor.apply(.setTextStyle(clip.id, t.textStyle(preset.style)))
                let fadeIn = t.optMs("fade_in_ms") ?? 300, fadeOut = t.optMs("fade_out_ms") ?? 300
                try editor.apply(.setVolume(clip.id, volume: 1, fadeIn: min(fadeIn, clip.duration / 2), fadeOut: min(fadeOut, clip.duration / 2)))
            }
            for o in overlays {
                let overlay = try editor.addOverlay(GeneratorKind(rawValue: try o.str("kind"))!, start: max(0, o.optMs("start_ms") ?? 0), duration: o.optMs("duration_ms") ?? 4_000, amount: o.optDouble("amount") ?? 0.5)
                let fadeIn = o.optMs("fade_in_ms") ?? 400, fadeOut = o.optMs("fade_out_ms") ?? 400
                try editor.apply(.setVolume(overlay.id, volume: 1, fadeIn: min(fadeIn, overlay.duration / 2), fadeOut: min(fadeOut, overlay.duration / 2)))
            }
            for s in sfx {
                let at = s.args.optMs("at_ms") ?? (s.args.optMs("at_cut").map { Int($0) }.flatMap { cuts.indices.contains($0) ? cutStart($0) : nil } ?? 0) + (s.args.optMs("offset_ms") ?? 0)
                let clip = try editor.addClip(asset: s.asset, start: max(0, at))
                try editor.apply(.setVolume(clip.id, volume: s.args.optDouble("volume") ?? 0.6, fadeIn: 0, fadeOut: 0))
            }
            if let (asset, m) = music {
                let start = max(0, m.optMs("start_ms") ?? 0), sourceIn = max(0, m.optMs("source_in_ms") ?? 0)
                let length = max(1, min(asset.duration - sourceIn, total - start))
                let clip = try editor.addClip(asset: asset, start: start, sourceIn: sourceIn, duration: length, kind: .audio)
                try editor.apply(.setVolume(clip.id, volume: m.optDouble("volume") ?? 0.6, fadeIn: min(500, length / 2), fadeOut: min(2_500, length / 2)))
                if m.d["duck"] as? Bool == true, let track = editor.project.tracks.first(where: { $0.clips.contains { $0.id == clip.id } }) {
                    try editor.apply(.setTrackDuck(track.id, true))   // the music dips under clip sound
                }
            }
            summary.append("total \(total) ms (\(String(format: "%.1f", Double(total) / 1000)) s); \(titles.count) titles, \(sfx.count) sound effects" + (music != nil ? ", music" : ""))
        }
        return "edit built in one undo step:\n" + summary.joined(separator: "\n") + "\nnext: look at it with watch_timeline and fix what is off."
    }
}
