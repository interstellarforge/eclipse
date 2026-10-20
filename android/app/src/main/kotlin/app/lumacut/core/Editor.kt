package app.lumacut.core

import kotlin.math.roundToLong

class EditError(message: String) : Exception(message)

/** Every edit is a Command. The UI and the assistant both go through Editor.apply. */
sealed interface Command {
    data class AddAsset(val asset: Asset) : Command
    data class AddTrack(val id: Id, val kind: TrackKind) : Command
    data class AddClip(val track: Id, val clip: Clip) : Command
    data class RemoveClip(val id: Id) : Command
    data class MoveClip(val id: Id, val start: Ms) : Command
    data class TrimClip(val id: Id, val sourceIn: Ms, val duration: Ms, val start: Ms) : Command
    data class SplitClip(val id: Id, val at: Ms) : Command
    data class SetVolume(val id: Id, val volume: Double, val fadeIn: Ms, val fadeOut: Ms) : Command
    data class AddTransition(val transition: Transition) : Command
    data class RemoveTransition(val id: Id) : Command
    data class SetText(val id: Id, val text: String) : Command
    data class SetMuted(val id: Id, val muted: Boolean) : Command
    data class SetFormat(val width: Int, val height: Int, val fps: Int) : Command
    data class SetSpeed(val id: Id, val speed: Double) : Command
    data class RampSpeed(val id: Id, val points: List<RampPoint>, val segments: Int) : Command
    data class SetLook(val id: Id, val look: Look) : Command
    data class AddEffect(val id: Id, val effect: Effect) : Command
    data class RemoveEffect(val id: Id, val effect: Id) : Command
    data class SetTrackFlags(val id: Id, val muted: Boolean, val hidden: Boolean) : Command
    data class RippleRemove(val id: Id) : Command
    data class RemoveAsset(val id: Id) : Command
    data class MoveTrack(val id: Id, val to: Int) : Command
    data class RemoveTrack(val id: Id) : Command
    data class SetTransform(val id: Id, val opacity: Double, val scale: Double, val offsetX: Double, val offsetY: Double) : Command
    data class SetTextStyle(val id: Id, val style: TextStyle) : Command
    data class SetTransition(val id: Id, val type: TransitionType, val duration: Ms) : Command
    data class RelinkAsset(val id: Id, val url: String) : Command
    data class ReplaceClipAsset(val id: Id, val assetID: Id) : Command
    data class SetTrackLocked(val id: Id, val locked: Boolean) : Command
    data class SetTrackDuck(val id: Id, val duck: Boolean) : Command
    data class SetTrackDuckLevel(val id: Id, val level: Double) : Command
    data class SetGenerator(val id: Id, val kind: GeneratorKind, val amount: Double) : Command
    data class SetAssetFavorite(val id: Id, val favorite: Boolean) : Command
    data class RenameAsset(val id: Id, val name: String?) : Command
    data class SetTrackName(val id: Id, val name: String?) : Command
    data class Group(val ids: List<Id>) : Command
    data class Ungroup(val id: Id) : Command
    data class SetKeyframes(val id: Id, val frames: List<Keyframe>) : Command
}

/** Project with undo and redo. All edits are validated; on error nothing changes. */
class Editor(initial: Project = Project()) {
    var project: Project = initial
        private set
    private var undoStack = ArrayDeque<Project>()
    private var redoStack = ArrayDeque<Project>()
    var onChange: (() -> Unit)? = null

    val canUndo get() = undoStack.isNotEmpty()
    val canRedo get() = redoStack.isNotEmpty()

    private fun changed() { onChange?.invoke() }

    fun apply(command: Command) {
        val next = run(command, project)
        validate(next)
        for (old in project.tracks.filter { it.locked }) {
            val new = next.track(old.id)
            if (new == null || new.clips != old.clips) throw EditError("That track is locked. Unlock it to change its clips.")
        }
        undoStack.addLast(project); redoStack.clear(); project = next; changed()
    }

    /** Several edits as ONE undo step; if any fails, nothing changes. */
    fun transaction(body: () -> Unit) {
        val savedProject = project; val savedUndo = ArrayDeque(undoStack); val savedRedo = ArrayDeque(redoStack)
        try { body() } catch (e: Exception) {
            project = savedProject; undoStack = savedUndo; redoStack = savedRedo; changed(); throw e
        }
        if (project != savedProject) { undoStack = ArrayDeque(savedUndo).also { it.addLast(savedProject) }; redoStack = ArrayDeque() }
    }

    /** Swaps in a whole project (open / new). Clears the undo history. */
    fun replace(p: Project) { validate(p); project = p; undoStack.clear(); redoStack.clear(); changed() }

    /** Swaps in a whole project as ONE undoable edit (accepting a ghost edit). */
    fun replaceAsEdit(p: Project) { validate(p); undoStack.addLast(project); redoStack.clear(); project = p; changed() }

    fun undo() { val prev = undoStack.removeLastOrNull() ?: return; redoStack.addLast(project); project = prev; changed() }
    fun redo() { val next = redoStack.removeLastOrNull() ?: return; undoStack.addLast(project); project = next; changed() }

    companion object {
        private fun groupMembers(id: Id, p: Project): List<Id> {
            val g = p.clip(id)?.groupID ?: return listOf(id)
            return p.allClips.filter { it.groupID == g }.map { it.id }
        }

        private fun mapClip(p: Project, id: Id, f: (Clip) -> Clip): Project {
            if (p.clip(id) == null) throw EditError("not found")
            return p.copy(tracks = p.tracks.map { t -> if (t.clips.any { it.id == id }) t.copy(clips = t.clips.map { if (it.id == id) f(it) else it }) else t })
        }

        private fun mapClips(p: Project, ids: Set<Id>, f: (Clip) -> Clip) =
            p.copy(tracks = p.tracks.map { t -> t.copy(clips = t.clips.map { if (it.id in ids) f(it) else it }) })

        private fun mapTrack(p: Project, id: Id, f: (Track) -> Track): Project {
            if (p.track(id) == null) throw EditError("not found")
            return p.copy(tracks = p.tracks.map { if (it.id == id) f(it) else it })
        }

        private fun mapAsset(p: Project, id: Id, f: (Asset) -> Asset): Project {
            if (p.asset(id) == null) throw EditError("not found")
            return p.copy(assets = p.assets.map { if (it.id == id) f(it) else it })
        }

        private fun shift(track: Track, from: Ms, by: Ms) = track.copy(clips = track.clips.map { if (it.start >= from) it.copy(start = it.start + by) else it })

        /** Splits one clip at a timeline position; returns the project and the new right-hand clip id. */
        private fun split(p: Project, id: Id, at: Ms): Pair<Project, Id> {
            val clip = p.clip(id) ?: throw EditError("not found")
            if (at <= clip.start || at >= clip.end) throw EditError("split outside clip")
            val cut = at - clip.start
            val rightId = newId()
            var left = clip.copy(duration = cut, fadeOut = 0)
            var right = clip.copy(id = rightId, start = at, sourceIn = clip.sourceIn + (cut * clip.speed).roundToLong(), duration = clip.duration - cut, fadeIn = 0)
            if (clip.keyframes.isNotEmpty()) {   // keep the animation continuous across the cut
                val atCut = Keyframe.interpolate(clip.keyframes, cut.toDouble())!!.copy(time = cut, smooth = false)
                left = left.copy(keyframes = clip.keyframes.filter { it.time < cut } + atCut)
                right = right.copy(keyframes = (listOf(atCut) + clip.keyframes.filter { it.time > cut }).map { it.copy(time = it.time - cut) })
            }
            val tracks = p.tracks.map { t ->
                if (t.clips.none { it.id == id }) t
                else t.copy(clips = t.clips.flatMap { if (it.id == id) listOf(left, right) else listOf(it) })
            }
            val transitions = p.transitions.map { if (it.fromClip == id) it.copy(fromClip = rightId) else it }   // outgoing transition follows the tail
            return p.copy(tracks = tracks, transitions = transitions) to rightId
        }

        /** Clips on one track may only overlap as a transition: a consecutive pair, neither fully covered. */
        fun validate(p: Project) {
            for (track in p.tracks) {
                val s = track.clips.sortedBy { it.start }
                for (i in s.indices) {
                    if (i + 2 < s.size && s[i + 2].start < s[i].end) throw EditError("Clips on one track can't overlap, unless a transition joins them")
                    if (i + 1 < s.size && s[i + 1].start < s[i].end) {
                        val overlap = s[i].end - s[i + 1].start
                        if (!(overlap < s[i].duration && overlap < s[i + 1].duration && p.transitions.any { it.fromClip == s[i].id && it.toClip == s[i + 1].id }))
                            throw EditError("Clips on one track can't overlap, unless a transition joins them")
                    }
                }
            }
            for (tr in p.transitions) {
                val clips = p.tracks.firstOrNull { t -> t.clips.any { it.id == tr.fromClip } }?.clips
                val from = clips?.firstOrNull { it.id == tr.fromClip }; val to = clips?.firstOrNull { it.id == tr.toClip }
                if (from == null || to == null || !(from.start < to.start && to.start < from.end)) throw EditError("a transition needs two overlapping clips; remove it first")
            }
        }

        internal fun run(cmd: Command, p: Project): Project = when (cmd) {
            is Command.AddAsset -> p.copy(assets = p.assets + cmd.asset)
            is Command.AddTrack -> p.copy(tracks = p.tracks + Track(id = cmd.id, kind = cmd.kind))
            is Command.AddClip -> {
                val clip = cmd.clip
                if (p.track(cmd.track) == null) throw EditError("not found")
                clip.assetID?.let { aid ->
                    val a = p.asset(aid) ?: throw EditError("not found")
                    if (clip.sourceIn < 0 || clip.sourceIn + clip.sourceLength > a.duration) throw EditError("clip exceeds asset duration")
                }
                if (clip.duration <= 0 || clip.start < 0) throw EditError("bad clip range")
                mapTrack(p, cmd.track) { it.copy(clips = it.clips + clip) }
            }
            is Command.RemoveClip -> {
                if (p.clip(cmd.id) == null) throw EditError("not found")
                val gone = groupMembers(cmd.id, p).toSet()
                p.copy(transitions = p.transitions.filter { it.fromClip !in gone && it.toClip !in gone },
                    tracks = p.tracks.map { t -> t.copy(clips = t.clips.filter { it.id !in gone }) })
            }
            is Command.MoveClip -> {
                if (cmd.start < 0) throw EditError("negative start")
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                val delta = cmd.start - clip.start
                val members = groupMembers(cmd.id, p).toSet()
                if (p.allClips.any { it.id in members && it.start + delta < 0 }) throw EditError("a grouped clip would start before 0")
                mapClips(p, members) { it.copy(start = it.start + delta) }
            }
            is Command.TrimClip -> {
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                clip.assetID?.let { aid -> p.asset(aid)?.let { a ->
                    if (cmd.sourceIn < 0 || cmd.sourceIn + (cmd.duration * clip.speed).roundToLong() > a.duration) throw EditError("trim exceeds asset duration")
                } }
                if (cmd.duration <= 0 || cmd.start < 0) throw EditError("bad clip range")
                mapClip(p, cmd.id) { it.copy(sourceIn = cmd.sourceIn, duration = cmd.duration, start = cmd.start) }
            }
            is Command.SplitClip -> {
                val members = groupMembers(cmd.id, p)
                val spanning = members.filter { m -> p.clip(m)?.let { it.start < cmd.at && cmd.at < it.end } ?: false }
                if (cmd.id !in spanning) throw EditError("split outside clip")
                var q = p; val rights = mutableListOf<Id>()
                for (m in spanning) { val (np, r) = split(q, m, cmd.at); q = np; rights += r }
                if (members.size > 1 && rights.size > 1) { val g = newId(); q = mapClips(q, rights.toSet()) { it.copy(groupID = g) } }
                q
            }
            is Command.SetVolume -> {
                if (cmd.volume < 0 || cmd.fadeIn < 0 || cmd.fadeOut < 0) throw EditError("negative value")
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                if (cmd.fadeIn + cmd.fadeOut > clip.duration) throw EditError("fades longer than clip")
                mapClip(p, cmd.id) { it.copy(volume = cmd.volume, fadeIn = cmd.fadeIn, fadeOut = cmd.fadeOut) }
            }
            is Command.AddTransition -> {
                val tr = cmd.transition
                val t = p.trackOf(tr.fromClip) ?: throw EditError("not found"); val t2 = p.trackOf(tr.toClip) ?: throw EditError("not found")
                val from = p.clip(tr.fromClip)!!; val to = p.clip(tr.toClip)!!
                if (t.id != t2.id || from.end != to.start) throw EditError("clips must be adjacent on one track")
                if (tr.duration <= 0 || tr.duration >= from.duration || tr.duration >= to.duration) throw EditError("bad transition duration")
                if (p.transitions.any { it.fromClip == from.id && it.toClip == to.id }) throw EditError("transition already exists")
                // The clips overlap by the transition length: the incoming clip and everything after it move earlier.
                mapTrack(p, t.id) { shift(it, to.start, -tr.duration) }.let { it.copy(transitions = it.transitions + tr) }
            }
            is Command.RemoveTransition -> {
                val tr = p.transitions.firstOrNull { it.id == cmd.id } ?: throw EditError("not found")
                val t = p.trackOf(tr.fromClip) ?: throw EditError("not found")
                val from = p.clip(tr.fromClip)!!; val to = p.clip(tr.toClip) ?: throw EditError("not found")
                val overlap = from.end - to.start
                val q = p.copy(transitions = p.transitions.filter { it.id != cmd.id })
                if (overlap > 0) mapTrack(q, t.id) { shift(it, to.start, overlap) } else q
            }
            is Command.MoveTrack -> {
                val i = p.tracks.indexOfFirst { it.id == cmd.id }; if (i < 0) throw EditError("not found")
                val list = p.tracks.toMutableList(); val track = list.removeAt(i)
                list.add(cmd.to.coerceIn(0, list.size), track); p.copy(tracks = list)
            }
            is Command.RemoveTrack -> {
                val track = p.track(cmd.id) ?: throw EditError("not found")
                val gone = track.clips.map { it.id }.toSet()
                p.copy(transitions = p.transitions.filter { it.fromClip !in gone && it.toClip !in gone }, tracks = p.tracks.filter { it.id != cmd.id })
            }
            is Command.SetFormat -> {
                if (cmd.width !in 240..4096 || cmd.height !in 240..4096 || cmd.width % 2 != 0 || cmd.height % 2 != 0 || cmd.fps !in 12..120)
                    throw EditError("size must be even numbers from 240 to 4096 and fps from 12 to 120")
                p.copy(width = cmd.width, height = cmd.height, fps = cmd.fps)
            }
            is Command.SetSpeed -> {
                if (cmd.speed < 0.1 || cmd.speed > 8) throw EditError("speed must be between 0.1x and 8x")
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                val t = p.trackOf(cmd.id)!!
                val newDuration = maxOf(1L, (clip.sourceLength / cmd.speed).roundToLong())
                val delta = newDuration - clip.duration
                mapTrack(p, t.id) { tr ->
                    tr.copy(clips = tr.clips.map {
                        when {
                            it.id == clip.id -> it.copy(speed = cmd.speed, duration = newDuration, fadeIn = minOf(clip.fadeIn, newDuration),
                                fadeOut = minOf(clip.fadeOut, newDuration - minOf(clip.fadeIn, newDuration)))
                            it.start > clip.start -> it.copy(start = it.start + delta)   // later clips follow
                            else -> it
                        }
                    })
                }
            }
            is Command.AddEffect -> {
                if (cmd.effect.amount !in 0.0..1.0) throw EditError("effect amount must be 0...1")
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                if (clip.text != null || clip.generator != null) throw EditError("effects work on video clips, not titles or overlays")
                mapClip(p, cmd.id) { c ->
                    val i = c.effects.indexOfFirst { it.type == cmd.effect.type || it.id == cmd.effect.id }
                    if (i >= 0) c.copy(effects = c.effects.toMutableList().also { it[i] = cmd.effect.copy(id = c.effects[i].id) }) else c.copy(effects = c.effects + cmd.effect)
                }
            }
            is Command.RemoveEffect -> {
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                if (clip.effects.none { it.id == cmd.effect }) throw EditError("not found")
                mapClip(p, cmd.id) { c -> c.copy(effects = c.effects.filter { it.id != cmd.effect }) }
            }
            is Command.RampSpeed -> rampSpeed(cmd, p)
            is Command.SetLook -> {
                val l = cmd.look
                val ok = l.brightness in -1.0..1.0 && l.contrast in 0.0..4.0 && l.saturation in 0.0..3.0 && l.sepia in 0.0..1.0 && l.blur in 0.0..1.0 &&
                    l.vignette in 0.0..1.0 && listOf(l.cropLeft, l.cropRight, l.cropTop, l.cropBottom).all { it in 0.0..0.9 } &&
                    l.cropLeft + l.cropRight < 0.95 && l.cropTop + l.cropBottom < 0.95 && l.warmth in -1.0..1.0 && l.fade in 0.0..1.0 &&
                    l.sharpen in 0.0..1.0 && l.splitAmount in 0.0..1.0
                if (!ok) throw EditError("look value out of range")
                mapClip(p, cmd.id) { it.copy(look = l) }
            }
            is Command.SetTrackFlags -> mapTrack(p, cmd.id) { it.copy(muted = cmd.muted, hidden = cmd.hidden) }
            is Command.RippleRemove -> {
                if (p.clip(cmd.id) == null) throw EditError("not found")
                val gone = groupMembers(cmd.id, p).toSet()
                p.copy(transitions = p.transitions.filter { it.fromClip !in gone && it.toClip !in gone }, tracks = p.tracks.map { t ->
                    val removed = t.clips.filter { it.id in gone }
                    if (removed.isEmpty()) t
                    else {
                        var clips = t.clips.filter { it.id !in gone }
                        for (r in removed.sortedByDescending { it.start }) clips = clips.map { if (it.start >= r.end) it.copy(start = it.start - r.duration) else it }   // close each gap, latest first
                        t.copy(clips = clips)
                    }
                })
            }
            is Command.RemoveAsset -> {
                if (p.asset(cmd.id) == null) throw EditError("not found")
                val gone = p.allClips.filter { it.assetID == cmd.id }.map { it.id }.toSet()
                p.copy(assets = p.assets.filter { it.id != cmd.id }, transitions = p.transitions.filter { it.fromClip !in gone && it.toClip !in gone },
                    tracks = p.tracks.map { t -> t.copy(clips = t.clips.filter { it.id !in gone }) })
            }
            is Command.ReplaceClipAsset -> {
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                val a = p.asset(cmd.assetID) ?: throw EditError("not found")
                if (clip.sourceIn + clip.sourceLength > a.duration + 50) throw EditError("the new file is shorter than the clip")
                mapClip(p, cmd.id) { it.copy(assetID = cmd.assetID) }
            }
            is Command.RelinkAsset -> mapAsset(p, cmd.id) { it.copy(url = cmd.url) }
            is Command.SetTrackLocked -> mapTrack(p, cmd.id) { it.copy(locked = cmd.locked) }
            is Command.SetTrackDuck -> {
                val t = p.track(cmd.id) ?: throw EditError("not found")
                if (t.kind != TrackKind.audio) throw EditError("only audio tracks can duck")
                mapTrack(p, cmd.id) { it.copy(duck = cmd.duck) }
            }
            is Command.SetGenerator -> {
                val c = p.clip(cmd.id) ?: throw EditError("not found")
                if (c.generator == null) throw EditError("not an overlay clip")
                if (cmd.amount !in 0.0..1.0) throw EditError("amount must be 0...1")
                mapClip(p, cmd.id) { it.copy(generator = cmd.kind, generatorAmount = cmd.amount) }
            }
            is Command.SetTrackDuckLevel -> {
                if (p.track(cmd.id) == null) throw EditError("not found")
                if (cmd.level !in 0.05..0.95) throw EditError("duck level must be between 5 % and 95 %")
                mapTrack(p, cmd.id) { it.copy(duckLevel = cmd.level) }
            }
            is Command.SetAssetFavorite -> mapAsset(p, cmd.id) { it.copy(favorite = cmd.favorite) }
            is Command.RenameAsset -> mapAsset(p, cmd.id) { a ->
                val trimmed = cmd.name?.trim()
                a.copy(name = if (trimmed.isNullOrEmpty()) (if (a.isStill) a.name else null) else trimmed)
            }
            is Command.SetTrackName -> mapTrack(p, cmd.id) { it.copy(name = cmd.name) }
            is Command.Group -> {
                if (cmd.ids.toSet().size < 2) throw EditError("select at least two clips to group")
                cmd.ids.forEach { if (p.clip(it) == null) throw EditError("not found") }
                val g = newId(); mapClips(p, cmd.ids.toSet()) { it.copy(groupID = g) }
            }
            is Command.Ungroup -> {
                val g = p.clip(cmd.id)?.groupID ?: throw EditError("clip is not grouped")
                mapClips(p, p.allClips.filter { it.groupID == g }.map { it.id }.toSet()) { it.copy(groupID = null) }
            }
            is Command.SetKeyframes -> {
                val clip = p.clip(cmd.id) ?: throw EditError("not found")
                val ok = cmd.frames.all { it.time in 0..clip.duration && it.opacity in 0.0..1.0 && it.scale > 0 && it.scale <= 10 } && cmd.frames.map { it.time }.toSet().size == cmd.frames.size
                if (!ok) throw EditError("keyframes need distinct times inside the clip, opacity 0...1 and scale above 0")
                mapClip(p, cmd.id) { it.copy(keyframes = cmd.frames.sortedBy { f -> f.time }) }
            }
            is Command.SetMuted -> mapClip(p, cmd.id) { it.copy(muted = cmd.muted) }
            is Command.SetTransform -> {
                if (cmd.opacity !in 0.0..1.0 || cmd.scale <= 0 || cmd.scale > 10) throw EditError("bad opacity or scale")
                mapClip(p, cmd.id) { it.copy(opacity = cmd.opacity, scale = cmd.scale, offsetX = cmd.offsetX, offsetY = cmd.offsetY) }
            }
            is Command.SetTextStyle -> {
                if (cmd.style.size <= 0 || cmd.style.size > 1) throw EditError("bad text size")
                val c = p.clip(cmd.id) ?: throw EditError("not found")
                if (c.text == null) throw EditError("not a text clip")
                mapClip(p, cmd.id) { it.copy(style = cmd.style) }
            }
            is Command.SetTransition -> {
                val tr = p.transitions.firstOrNull { it.id == cmd.id } ?: throw EditError("not found")
                if (cmd.duration <= 0) throw EditError("zero duration")
                val t = p.trackOf(tr.fromClip) ?: throw EditError("not found")
                val from = p.clip(tr.fromClip)!!; val to = p.clip(tr.toClip) ?: throw EditError("not found")
                val overlap = from.end - to.start
                val q = mapTrack(p, t.id) { shift(it, to.start, overlap - cmd.duration) }   // longer transition = later clips move earlier
                q.copy(transitions = q.transitions.map { if (it.id == cmd.id) it.copy(type = cmd.type, duration = cmd.duration) else it })
            }
            is Command.SetText -> {
                val c = p.clip(cmd.id) ?: throw EditError("not found")
                if (c.text == null) throw EditError("not a text clip")
                mapClip(p, cmd.id) { it.copy(text = cmd.text) }
            }
        }

        private val timeBased = setOf(EffectType.kenBurnsIn, EffectType.kenBurnsOut, EffectType.panLeft, EffectType.panRight, EffectType.blurIn, EffectType.blurOut, EffectType.flash)

        private fun rampSpeed(cmd: Command.RampSpeed, p: Project): Project {
            val clip = p.clip(cmd.id) ?: throw EditError("not found")
            val t = p.trackOf(cmd.id)!!
            if (clip.assetID == null || clip.text != null || clip.generator != null) throw EditError("speed ramps work on video and audio clips")
            val pts = cmd.points
            if (cmd.segments !in 4..40 || pts.size < 2 || !pts.all { it.position in 0.0..1.0 && it.speed in 0.1..8.0 } || !pts.zipWithNext().all { (a, b) -> a.position < b.position })
                throw EditError("a speed curve needs 2 or more points with rising positions 0...1 and speeds between 0.1x and 8x")
            if (p.transitions.any { it.fromClip == cmd.id || it.toClip == cmd.id })
                throw EditError("Remove the transitions on this clip first: a speed ramp cuts it into small pieces, and a transition can't overlap several pieces. Add them again afterwards.")
            val sourceLength = clip.sourceLength.toDouble()
            val pieces = mutableListOf<Clip>(); var cursor = clip.start
            for (k in 0 until cmd.segments) {
                val u0 = k.toDouble() / cmd.segments; val u1 = (k + 1).toDouble() / cmd.segments
                val from = clip.sourceIn + (u0 * sourceLength).roundToLong(); val to = clip.sourceIn + (u1 * sourceLength).roundToLong()
                val speed = SpeedRamp.speed((u0 + u1) / 2, pts)
                val dur = maxOf(1L, ((to - from) / speed).roundToLong())
                pieces += clip.copy(id = if (k == 0) clip.id else newId(), sourceIn = from, speed = speed, start = cursor, duration = dur,
                    fadeIn = if (k == 0) clip.fadeIn else 0, fadeOut = if (k == cmd.segments - 1) clip.fadeOut else 0,
                    keyframes = emptyList(), effects = clip.effects.filter { it.type !in timeBased })
                cursor += dur
            }
            val delta = cursor - clip.end
            return mapTrack(p, t.id) { tr ->
                tr.copy(clips = tr.clips.filter { it.id != clip.id }.map { if (it.start > clip.start) it.copy(start = it.start + delta) else it } + pieces)
            }
        }
    }
}
