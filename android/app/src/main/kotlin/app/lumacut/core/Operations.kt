package app.lumacut.core

/** Higher-level edits shared by the UI and the assistant. Each wraps one or a few commands. */

/** Places an asset on a track of the matching kind. Without `start` it goes at the end of the first such track; with `start` on the first such track with room, else a new track. */
fun Editor.addClip(asset: Asset, start: Ms? = null, sourceIn: Ms = 0, duration: Ms? = null, track: Id? = null, kind: TrackKind? = null): Clip {
    val k = kind ?: if (asset.hasVideo) TrackKind.video else TrackKind.audio
    val length = duration ?: if (asset.isStill) minOf(4_000L, asset.duration) else asset.duration - sourceIn   // photos default to 4 s
    var trackID = track ?: project.tracks.firstOrNull { t -> t.kind == k && (start == null || t.clips.none { it.start < start + length && start < it.end }) }?.id
    if (trackID == null) { val id = newId(); apply(Command.AddTrack(id, k)); trackID = id }
    val tr = project.track(trackID) ?: throw EditError("not found")
    val clip = Clip(assetID = asset.id, sourceIn = sourceIn, duration = length, start = start ?: (tr.clips.maxOfOrNull { it.end } ?: 0))
    apply(Command.AddClip(trackID, clip))
    return clip
}

fun Editor.addTitle(text: String, start: Ms, duration: Ms = 3_000): Clip {
    // The first text track that is free at that time; a busy time gets a new text track instead of an error.
    var trackID = project.tracks.firstOrNull { t -> t.kind == TrackKind.text && t.clips.none { it.start < start + duration && start < it.end } }?.id
    if (trackID == null) { val id = newId(); apply(Command.AddTrack(id, TrackKind.text)); trackID = id }
    val clip = Clip(assetID = null, text = text, duration = duration, start = start)
    apply(Command.AddClip(trackID, clip))
    return clip
}

/** Transition between a clip and the clip that starts exactly where it ends (default 1 s, capped at half the shorter clip). */
fun Editor.addTransitionAfter(clipID: Id, type: TransitionType, duration: Ms? = null) {
    val track = project.trackOf(clipID) ?: throw EditError("clip is not directly followed by another clip")
    val clip = track.clips.first { it.id == clipID }
    val next = track.clips.firstOrNull { it.start == clip.end } ?: throw EditError("clip is not directly followed by another clip")
    val d = minOf(duration ?: 1_000L, minOf(clip.duration, next.duration) / 2)
    apply(Command.AddTransition(Transition(fromClip = clip.id, toClip = next.id, type = type, duration = d)))
}

fun Editor.removeTransitionInvolving(clipID: Id) {
    val tr = project.transitions.firstOrNull { it.fromClip == clipID || it.toClip == clipID } ?: throw EditError("not found")
    apply(Command.RemoveTransition(tr.id))
}

/** Moves a video clip's sound onto its own audio clip (same range) and mutes the video clip. */
fun Editor.detachAudio(clipID: Id) {
    val track = project.tracks.firstOrNull { it.kind == TrackKind.video && it.clips.any { c -> c.id == clipID } }
    val clip = track?.clips?.firstOrNull { it.id == clipID }
    val asset = clip?.let { project.asset(it.assetID) }
    if (clip == null || asset == null || !asset.hasAudio || clip.muted) throw EditError("select a video clip that still has its own audio")
    val audio = addClip(asset, start = clip.start, sourceIn = clip.sourceIn, duration = clip.duration, kind = TrackKind.audio)
    apply(Command.SetVolume(audio.id, clip.volume, clip.fadeIn, clip.fadeOut))
    apply(Command.SetMuted(clipID, true))
    apply(Command.Group(listOf(clipID, audio.id)))   // picture and sound stay together until ungrouped
}

/** Adds an empty track. The first track in the list is the top layer, so `onTop` puts it first. */
fun Editor.addTrack(kind: TrackKind, onTop: Boolean = false): Id {
    val id = newId(); apply(Command.AddTrack(id, kind)); if (onTop) apply(Command.MoveTrack(id, 0)); return id
}

/** Copies a clip to the end of its track. */
fun Editor.duplicate(clipID: Id): Clip {
    val track = project.trackOf(clipID) ?: throw EditError("not found")
    val copy = track.clips.first { it.id == clipID }.copy(id = newId(), start = track.clips.maxOf { it.end })
    apply(Command.AddClip(track.id, copy)); return copy
}

/** Music bed on an audio track: trimmed to the movie when it is longer, quieter than speech, with fades. */
fun Editor.addMusicBed(asset: Asset, start: Ms = 0, duration: Ms? = null): Clip {
    val movie = project.duration
    val length = duration ?: if (movie > start) minOf(asset.duration, movie - start) else asset.duration
    val clip = addClip(asset, start = start, duration = maxOf(1L, length), kind = TrackKind.audio)
    apply(Command.SetVolume(clip.id, 0.6, minOf(500L, clip.duration / 2), minOf(2_500L, clip.duration / 2)))
    return clip
}

/** An emoji as a big title that pops in. */
fun Editor.addSticker(emoji: String, start: Ms, duration: Ms = 2_500): Clip {
    val clip = addTitle(emoji, start, duration)
    apply(Command.SetTextStyle(clip.id, TextStyle(size = 0.22, y = 0.62, x = 0.5, shadow = false, bold = false, animation = TextAnimation.pop, animationMs = 400)))
    return clip
}

/** Points an asset whose file moved at its new file; the new file must match in media kind and be long enough. */
fun Editor.relink(assetID: Id, fresh: Asset) {
    val old = project.asset(assetID) ?: throw EditError("not found")
    val needed = project.allClips.filter { it.assetID == assetID }.maxOfOrNull { it.sourceIn + it.sourceLength } ?: 0
    if (fresh.hasVideo != old.hasVideo || fresh.hasAudio != old.hasAudio || fresh.duration + 50 < needed)
        throw EditError("That file doesn't match: it needs the same picture and sound, and at least $needed ms of length.")
    apply(Command.RelinkAsset(assetID, fresh.url))
}

/** Puts a clip back to plain: no look, framing, keyframes, effects, normal speed and volume. Titles keep their text and style. */
fun Editor.resetClip(id: Id) {
    val clip = project.clip(id) ?: throw EditError("not found")
    transaction {
        if (clip.text == null) {
            apply(Command.SetLook(id, Look())); apply(Command.SetTransform(id, 1.0, 1.0, 0.0, 0.0)); apply(Command.SetKeyframes(id, emptyList()))
            clip.effects.forEach { apply(Command.RemoveEffect(id, it.id)) }
            if (clip.speed != 1.0) apply(Command.SetSpeed(id, 1.0))
            apply(Command.SetMuted(id, false))
        }
        apply(Command.SetVolume(id, 1.0, 0, 0))
    }
}

/** A drawn overlay (confetti, snow, ...) on the top-most video track with room, else on a new top layer. */
fun Editor.addOverlay(kind: GeneratorKind, start: Ms, duration: Ms = 4_000, amount: Double = 0.5): Clip {
    val clip = Clip(assetID = null, duration = duration, start = start, generator = kind, generatorAmount = amount)
    val trackID = project.tracks.firstOrNull { t -> t.kind == TrackKind.video && t.clips.none { it.start < start + duration && start < it.end } }?.id ?: addTrack(TrackKind.video, onTop = true)
    apply(Command.AddClip(trackID, clip)); return clip
}
