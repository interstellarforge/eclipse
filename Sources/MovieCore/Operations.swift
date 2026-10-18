import Foundation

/// Higher-level edits shared by the UI and the MCP server. Each wraps one or two commands.
extension Editor {
    /// Places an asset on a track of the matching kind. Without `start` it is appended to the first such
    /// track; with `start` it goes on the first such track with room, else a new track.
    @discardableResult
    public func addClip(asset: Asset, start: Ms? = nil, sourceIn: Ms = 0, duration: Ms? = nil, track: UUID? = nil,
                         kind: TrackKind? = nil) throws -> Clip {
        let kind = kind ?? (asset.hasVideo ? .video : .audio)
        let length = duration ?? (asset.isStill ? min(4_000, asset.duration) : asset.duration - sourceIn)   // photos default to 4 s
        var trackID = track
        if trackID == nil {
            trackID = project.tracks.first { t in
                t.kind == kind && (start == nil || !t.clips.contains { $0.start < start! + length && start! < $0.end })
            }?.id
        }
        if trackID == nil {
            let id = UUID()
            try apply(.addTrack(id: id, kind: kind)); trackID = id
        }
        guard let tid = trackID, let tr = project.tracks.first(where: { $0.id == tid }) else { throw EditError.notFound }
        let clip = Clip(assetID: asset.id, sourceIn: sourceIn, duration: length,
                        start: start ?? (tr.clips.map(\.end).max() ?? 0))
        try apply(.addClip(track: tid, clip: clip))
        return clip
    }

    @discardableResult
    public func addTitle(_ text: String, start: Ms, duration: Ms = 3_000) throws -> Clip {
        var trackID = project.tracks.first { $0.kind == .text }?.id
        if trackID == nil {
            let id = UUID()
            try apply(.addTrack(id: id, kind: .text)); trackID = id
        }
        let clip = Clip(assetID: nil, text: text, duration: duration, start: start)
        try apply(.addClip(track: trackID!, clip: clip))
        return clip
    }

    /// Transition between a clip and the clip that starts exactly where it ends (default length 1 s, capped at half the shorter clip).
    public func addTransition(after clipID: UUID, type: TransitionType, duration: Ms? = nil) throws {
        guard let track = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              let clip = track.clips.first(where: { $0.id == clipID }),
              let next = track.clips.first(where: { $0.start == clip.end })
        else { throw EditError.invalid("clip is not directly followed by another clip") }
        let d = min(duration ?? 1_000, min(clip.duration, next.duration) / 2)
        try apply(.addTransition(Transition(fromClip: clip.id, toClip: next.id, type: type, duration: d)))
    }

    public func removeTransition(involving clipID: UUID) throws {
        guard let tr = project.transitions.first(where: { $0.fromClip == clipID || $0.toClip == clipID })
        else { throw EditError.notFound }
        try apply(.removeTransition(tr.id))
    }
}

extension Editor {
    /// Moves a video clip's sound onto its own audio clip (same range) and mutes the video clip.
    public func detachAudio(_ clipID: UUID) throws {
        guard let track = project.tracks.first(where: { $0.kind == .video && $0.clips.contains { $0.id == clipID } }),
              let clip = track.clips.first(where: { $0.id == clipID }),
              let asset = project.assets.first(where: { $0.id == clip.assetID }), asset.hasAudio, !clip.muted
        else { throw EditError.invalid("select a video clip that still has its own audio") }
        let audio = try addClip(asset: asset, start: clip.start, sourceIn: clip.sourceIn, duration: clip.duration, kind: .audio)
        try apply(.setVolume(audio.id, volume: clip.volume, fadeIn: clip.fadeIn, fadeOut: clip.fadeOut))
        try apply(.setMuted(clipID, true))
        try apply(.group([clipID, audio.id]))   // picture and sound stay together until ungrouped
    }

    /// Adds an empty track. The first track in the list is the top layer, so `onTop` puts it first.
    @discardableResult
    public func addTrack(_ kind: TrackKind, onTop: Bool = false) throws -> UUID {
        let id = UUID()
        try apply(.addTrack(id: id, kind: kind))
        if onTop { try apply(.moveTrack(id, to: 0)) }
        return id
    }
}

extension Editor {
    /// Copies a clip to the end of its track.
    @discardableResult
    public func duplicate(_ clipID: UUID) throws -> Clip {
        guard let track = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              var copy = track.clips.first(where: { $0.id == clipID }) else { throw EditError.notFound }
        copy.id = UUID()
        copy.start = track.clips.map(\.end).max() ?? 0
        try apply(.addClip(track: track.id, clip: copy))
        return copy
    }
}

extension Editor {
    /// Music bed on an audio track: trimmed to the movie when it is longer, quieter than speech, with fades.
    @discardableResult
    public func addMusicBed(_ asset: Asset, start: Ms = 0, duration: Ms? = nil) throws -> Clip {
        let movie = project.duration
        let length = duration ?? (movie > start ? min(asset.duration, movie - start) : asset.duration)
        let clip = try addClip(asset: asset, start: start, duration: max(1, length), kind: .audio)
        try apply(.setVolume(clip.id, volume: 0.6, fadeIn: min(500, clip.duration / 2), fadeOut: min(2_500, clip.duration / 2)))
        return clip
    }
}

extension Editor {
    /// An emoji as a big title that pops in. Position it afterwards with its text style.
    @discardableResult
    public func addSticker(_ emoji: String, start: Ms, duration: Ms = 2_500) throws -> Clip {
        let clip = try addTitle(emoji, start: start, duration: duration)
        var style = TextStyle()
        style.size = 0.22; style.y = 0.62; style.x = 0.5; style.shadow = false; style.bold = false
        style.animation = .pop; style.animationMs = 400
        try apply(.setTextStyle(clip.id, style))
        return clip
    }
}

extension Editor {
    /// Points an asset whose file moved at its new file. The new file must have the same kind of media and be long enough for the clips that use it.
    public func relink(_ assetID: UUID, to fresh: Asset) throws {
        guard let old = project.assets.first(where: { $0.id == assetID }) else { throw EditError.notFound }
        let needed = project.tracks.flatMap(\.clips).filter { $0.assetID == assetID }.map { $0.sourceIn + $0.sourceLength }.max() ?? 0
        guard fresh.hasVideo == old.hasVideo, fresh.hasAudio == old.hasAudio, fresh.duration + 50 >= needed else {
            throw EditError.invalid("That file doesn't match: it needs the same picture and sound, and at least \(needed) ms of length.")
        }
        try apply(.relinkAsset(assetID, url: fresh.url))
    }
}

extension Editor {
    /// Puts a clip back to plain: no look, framing, keyframes, effects, normal speed and volume. Titles keep their text and style.
    public func resetClip(_ id: UUID) throws {
        guard let clip = project.tracks.flatMap(\.clips).first(where: { $0.id == id }) else { throw EditError.notFound }
        try transaction {
            if clip.text == nil {
                try apply(.setLook(id, Look()))
                try apply(.setTransform(id, opacity: 1, scale: 1, offsetX: 0, offsetY: 0))
                try apply(.setKeyframes(id, []))
                for e in clip.effects { try apply(.removeEffect(id, effect: e.id)) }
                if clip.speed != 1 { try apply(.setSpeed(id, 1)) }
                try apply(.setMuted(id, false))
            }
            let length = project.tracks.flatMap(\.clips).first { $0.id == id }?.duration ?? clip.duration
            _ = length
            try apply(.setVolume(id, volume: 1, fadeIn: 0, fadeOut: 0))
        }
    }
}

extension Editor {
    /// A drawn overlay (confetti, snow, ...) on the top-most video track with room, else on a new top layer.
    @discardableResult
    public func addOverlay(_ kind: GeneratorKind, start: Ms, duration: Ms = 4_000, amount: Double = 0.5) throws -> Clip {
        var clip = Clip(assetID: nil, duration: duration, start: start)
        clip.generator = kind; clip.generatorAmount = amount
        var trackID = project.tracks.first { t in t.kind == .video && !t.clips.contains { $0.start < start + duration && start < $0.end } }?.id
        if trackID == nil { trackID = try addTrack(.video, onTop: true) }
        try apply(.addClip(track: trackID!, clip: clip))
        return clip
    }
}
