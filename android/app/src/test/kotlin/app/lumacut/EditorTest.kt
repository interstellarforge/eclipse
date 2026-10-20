package app.lumacut

import app.lumacut.core.*
import org.junit.Assert.*
import org.junit.Test

class EditorTest {
    private fun setup(): Triple<Editor, Asset, Id> {
        val e = Editor()
        val a = Asset(url = "file:///a.mp4", duration = 10_000, hasVideo = true, hasAudio = true)
        val t = newId()
        e.apply(Command.AddAsset(a)); e.apply(Command.AddTrack(t, TrackKind.video))
        return Triple(e, a, t)
    }

    private fun clip(a: Asset, start: Ms, duration: Ms = 3_000, sourceIn: Ms = 0) = Clip(assetID = a.id, sourceIn = sourceIn, duration = duration, start = start)

    @Test fun splitKeepsSourceContinuity() {
        val (e, a, t) = setup(); val c = clip(a, 0, 4_000, 1_000)
        e.apply(Command.AddClip(t, c)); e.apply(Command.SplitClip(c.id, 1_500))
        val clips = e.project.tracks[0].clips
        assertEquals(2, clips.size)
        assertEquals(1_500L, clips[0].duration); assertEquals(1_500L, clips[1].start)
        assertEquals(2_500L, clips[1].sourceIn); assertEquals(2_500L, clips[1].duration)
    }

    @Test fun undoRedoAndRejectedEditsLeaveProjectUntouched() {
        val (e, a, t) = setup(); val c = clip(a, 0)
        e.apply(Command.AddClip(t, c))
        assertThrows(EditError::class.java) { e.apply(Command.AddClip(t, clip(a, 1_000))) }   // overlap without a transition
        assertEquals(1, e.project.tracks[0].clips.size)
        e.apply(Command.RemoveClip(c.id)); assertEquals(0, e.project.tracks[0].clips.size)
        e.undo(); assertEquals(1, e.project.tracks[0].clips.size)
        e.redo(); assertEquals(0, e.project.tracks[0].clips.size)
    }

    @Test fun transitionOverlapsClipsAndRemovalRestoresTiming() {
        val (e, a, t) = setup(); val c1 = clip(a, 0); val c2 = clip(a, 3_000)
        e.apply(Command.AddClip(t, c1)); e.apply(Command.AddClip(t, c2))
        val tr = Transition(fromClip = c1.id, toClip = c2.id, type = TransitionType.crossfade, duration = 500)
        e.apply(Command.AddTransition(tr))
        assertEquals(2_500L, e.project.clip(c2.id)!!.start)
        assertEquals(5_500L, e.project.duration)
        e.apply(Command.SetTransition(tr.id, TransitionType.fadeBlack, 1_000))
        assertEquals(2_000L, e.project.clip(c2.id)!!.start)
        e.apply(Command.RemoveTransition(tr.id))
        assertEquals(3_000L, e.project.clip(c2.id)!!.start)
    }

    @Test fun groupMovesTogether() {
        val (e, a, t) = setup(); val c1 = clip(a, 0, 2_000); val c2 = clip(a, 4_000, 2_000)
        e.apply(Command.AddClip(t, c1)); e.apply(Command.AddClip(t, c2)); e.apply(Command.Group(listOf(c1.id, c2.id)))
        e.apply(Command.MoveClip(c1.id, 1_000))
        assertEquals(5_000L, e.project.clip(c2.id)!!.start)
        assertThrows(EditError::class.java) { e.apply(Command.MoveClip(c1.id, -5_000)) }
    }

    @Test fun lockedTrackRefusesChanges() {
        val (e, a, t) = setup(); val c = clip(a, 0)
        e.apply(Command.AddClip(t, c)); e.apply(Command.SetTrackLocked(t, true))
        assertThrows(EditError::class.java) { e.apply(Command.RemoveClip(c.id)) }
        e.apply(Command.SetTrackLocked(t, false)); e.apply(Command.RemoveClip(c.id))
    }

    @Test fun speedChangeShortensClipAndPullsLaterClips() {
        val (e, a, t) = setup(); val c1 = clip(a, 0, 4_000); val c2 = clip(a, 4_000, 2_000)
        e.apply(Command.AddClip(t, c1)); e.apply(Command.AddClip(t, c2)); e.apply(Command.SetSpeed(c1.id, 2.0))
        assertEquals(2_000L, e.project.clip(c1.id)!!.duration); assertEquals(2_000L, e.project.clip(c2.id)!!.start)
        assertThrows(EditError::class.java) { e.apply(Command.SetSpeed(c1.id, 20.0)) }
    }

    @Test fun speedRampBuildsPiecesThatCoverTheSource() {
        val (e, a, t) = setup(); val c = clip(a, 0, 4_000)
        e.apply(Command.AddClip(t, c)); e.apply(Command.RampSpeed(c.id, SpeedRamp.preset("Hero pause")!!, 20))
        val pieces = e.project.tracks[0].clips.sortedBy { it.start }
        assertEquals(20, pieces.size)
        assertEquals(4_000L, pieces.sumOf { it.sourceLength }, )
        assertTrue(pieces.zipWithNext().all { (x, y) -> y.start == x.end })
        assertTrue(pieces.minOf { it.speed } < 0.5 && pieces.first().speed > 0.9)
    }

    @Test fun rippleRemoveClosesTheGap() {
        val (e, a, t) = setup(); val c1 = clip(a, 0, 2_000); val c2 = clip(a, 2_000, 2_000)
        e.apply(Command.AddClip(t, c1)); e.apply(Command.AddClip(t, c2)); e.apply(Command.RippleRemove(c1.id))
        assertEquals(0L, e.project.clip(c2.id)!!.start)
    }

    @Test fun transactionIsOneUndoStepAndRollsBack() {
        val (e, a, t) = setup()
        e.transaction { e.apply(Command.AddClip(t, clip(a, 0))); e.apply(Command.AddClip(t, clip(a, 3_000))) }
        e.undo(); assertEquals(0, e.project.tracks[0].clips.size)
        assertThrows(EditError::class.java) { e.transaction { e.apply(Command.AddClip(t, clip(a, 0))); e.apply(Command.RemoveClip("nope")) } }
        assertEquals(0, e.project.tracks[0].clips.size)
    }

    @Test fun projectSurvivesJsonAndOlderFilesLoad() {
        val (e, a, t) = setup(); val c = clip(a, 0).copy(look = LookPresets.preset("Golden hour")!!, effects = listOf(Effect(type = EffectType.vignette)))
        e.apply(Command.AddClip(t, c))
        val back = ProjectIO.decode(ProjectIO.encode(e.project))
        assertEquals(e.project, back)
        val old = """{"assets":[{"id":"A","url":"file:///x.mp4","duration":5000,"hasVideo":true,"hasAudio":false}],"tracks":[{"id":"T","kind":"video","clips":[{"id":"C","assetID":"A","sourceIn":0,"duration":1000,"start":0,"volume":1,"fadeIn":0,"fadeOut":0}]}],"transitions":[],"width":1280,"height":720,"fps":24,"someFutureField":1}"""
        val p = ProjectIO.decode(old)
        assertEquals(1280, p.width); assertEquals(1.0, p.tracks[0].clips[0].speed, 0.0); assertFalse(p.assets[0].isStill)
    }

    @Test fun catalogMatchesTheMacApp() {
        assertEquals(47, TransitionType.entries.size); assertEquals(34, EffectType.entries.size)
        assertEquals(19, GeneratorKind.entries.size); assertEquals(27, TitlePreset.entries.size); assertEquals(18, LookPresets.names.size)
        assertTrue(LookPresets.names.all { LookPresets.preset(it) != null })
        assertEquals(TitlePreset.lowerThird, TitlePreset.named("Lower third")); assertEquals(TitlePreset.wide, TitlePreset.named("cinematic wide"))
        assertEquals("Fade in", TextAnimation.fade.title)
    }

    @Test fun keyframesGlideAndSplitStaysContinuous() {
        val frames = listOf(Keyframe(0, scale = 1.0, smooth = false), Keyframe(1_000, scale = 2.0, smooth = false))
        assertEquals(1.5, Keyframe.interpolate(frames, 500.0)!!.scale, 1e-9)
        val (e, a, t) = setup(); val c = clip(a, 0, 2_000).copy(keyframes = frames)
        e.apply(Command.AddClip(t, c)); e.apply(Command.SplitClip(c.id, 500))
        val right = e.project.tracks[0].clips[1]
        assertEquals(0L, right.keyframes.first().time)
        assertEquals(1.5, right.keyframes.first().scale, 1e-9)               // the value at the cut, not a jump
        assertEquals(1.5, e.project.tracks[0].clips[0].keyframes.last().scale, 1e-9)
    }
}
