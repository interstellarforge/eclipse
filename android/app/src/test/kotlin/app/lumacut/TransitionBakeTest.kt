package app.lumacut

import androidx.media3.common.util.UnstableApi
import app.lumacut.core.*
import app.lumacut.media.TransitionBake
import org.junit.Assert.*
import org.junit.Test

@UnstableApi
class TransitionBakeTest {
    private val a = Asset(id = "a", url = "file:///a.mp4", duration = 10_000, hasVideo = true, hasAudio = false)
    private val b = Asset(id = "b", url = "file:///b.mp4", duration = 10_000, hasVideo = true, hasAudio = false)
    private val c1 = Clip(id = "c1", assetID = "a", duration = 3_000, start = 0)
    private val c2 = Clip(id = "c2", assetID = "b", sourceIn = 1_000, duration = 3_000, start = 2_200)   // overlaps c1 by 800
    private val project = Project(assets = listOf(a, b), tracks = listOf(Track(id = "t", kind = TrackKind.video, clips = listOf(c1, c2))),
        transitions = listOf(Transition(fromClip = "c1", toClip = "c2", type = TransitionType.crossfade, duration = 800)))

    @Test fun cutKeepsLengthAndRemovesOverlap() {
        val p = TransitionBake.substitute(project, emptyMap())
        val clips = p.tracks[0].clips
        assertTrue(p.transitions.isEmpty())
        assertEquals(listOf(0L, 3_000L), clips.map { it.start })
        assertEquals(1_800L, clips[1].sourceIn)
        assertEquals(project.duration, p.duration)
    }

    @Test fun renderedTransitionFillsTheOverlapOnOneLane() {
        val job = TransitionBake.jobs(project).single()
        assertEquals(800L, job.overlapMs)
        val baked = Asset(id = "baked", url = "file:///x.mp4", duration = 800, hasVideo = true, hasAudio = true)
        val clips = TransitionBake.substitute(project, mapOf(job.transition.id to baked)).tracks[0].clips
        assertEquals(listOf("a", "baked", "b"), clips.map { it.assetID })
        assertEquals(listOf(0L, 2_200L, 3_000L), clips.map { it.start })
        assertEquals(listOf(2_200L, 800L, 2_200L), clips.map { it.duration })
        assertTrue(clips.zipWithNext().all { (x, y) -> x.end == y.start })
    }
}
