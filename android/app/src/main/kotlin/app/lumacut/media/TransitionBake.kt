package app.lumacut.media

import androidx.media3.common.util.UnstableApi
import app.lumacut.core.*
import java.security.MessageDigest
import kotlin.math.roundToLong

/**
 * Transitions without the multi-input video graph (some phones never get it going).
 * The overlap of two clips is rendered once into a short clip; the project then plays on ONE lane:
 * outgoing clip (minus its tail), the rendered transition, incoming clip (minus its head).
 * Until a transition is rendered it plays as a cut.
 */
@UnstableApi
object TransitionBake {
    class Job(val transition: Transition, val mini: Project, val key: String, val overlapMs: Long)

    /** A clip's piece from `from` to `to` (ms from the clip's start): source offset, fades and keyframes follow. */
    internal fun Clip.slice(from: Long, to: Long): Clip = copy(
        start = start + from, sourceIn = sourceIn + (from * speed).roundToLong(), duration = to - from,
        fadeIn = if (from > 0) 0 else fadeIn, fadeOut = if (to < duration) 0 else fadeOut,
        keyframes = keyframes.filter { it.time in from..to }.map { it.copy(time = it.time - from) },
    )

    fun jobs(project: Project): List<Job> = project.transitions.mapNotNull { jobFor(project, it) }

    private fun jobFor(project: Project, tr: Transition): Job? {
        val f = project.clip(tr.fromClip) ?: return null; val t = project.clip(tr.toClip) ?: return null
        val track = project.trackOf(f.id) ?: return null
        if (track.id != project.trackOf(t.id)?.id || f.assetID == null || t.assetID == null) return null
        val ov = f.end - t.start
        if (ov < 100 || ov >= f.duration || ov >= t.duration) return null
        val f2 = f.slice(t.start - f.start, f.duration).copy(id = "bake-from", start = 0)
        val t2 = t.slice(0, ov).copy(id = "bake-to", start = 0)
        val mini = Project(
            assets = listOfNotNull(project.asset(f.assetID), project.asset(t.assetID)).distinctBy { it.id },
            tracks = listOf(track.copy(id = "bake-track", clips = listOf(f2, t2))),
            transitions = listOf(tr.copy(id = "bake-tr", fromClip = "bake-from", toClip = "bake-to", duration = ov)),
            width = project.width, height = project.height, fps = project.fps,
        )
        val key = MessageDigest.getInstance("SHA-1").digest(ProjectIO.encode(mini).toByteArray()).joinToString("") { "%02x".format(it) }.take(20)
        return Job(tr, mini, key, ov)
    }

    /** The project with every overlap removed: rendered transitions in `baked` (transition id -> clip file), cuts for the rest. */
    fun substitute(project: Project, baked: Map<Id, Asset>): Project {
        if (project.transitions.isEmpty()) return project
        val tracks = project.tracks.map { track ->
            if (track.kind != TrackKind.video) track else {
                val out = mutableListOf<Clip>()
                for (c in track.clips.sortedBy { it.start }) {
                    val inbound = project.transitions.firstOrNull { it.toClip == c.id }
                    val outbound = project.transitions.firstOrNull { it.fromClip == c.id }
                    var from = 0L; var to = c.duration
                    inbound?.let { tr -> project.clip(tr.fromClip)?.let { f -> val ov = f.end - c.start; if (ov > 0 && ov < c.duration) from = ov } }
                    val bake = outbound?.let { tr -> baked[tr.id]?.let { b -> project.clip(tr.toClip)?.let { t -> val ov = c.end - t.start; if (ov in 1 until c.duration) b to ov else null } } }
                    if (bake != null) to = c.duration - bake.second
                    if (to - from > 0) out += c.slice(from, to)
                    if (bake != null) out += Clip(assetID = bake.first.id, duration = bake.second, start = c.start + to)
                }
                track.copy(clips = out)
            }
        }
        return project.copy(assets = (project.assets + baked.values).distinctBy { it.id }, tracks = tracks, transitions = emptyList())
    }
}
