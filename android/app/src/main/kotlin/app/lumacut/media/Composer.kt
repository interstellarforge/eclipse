package app.lumacut.media

import android.content.Context
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import app.lumacut.core.*

/** Builds a Media3 Composition from the project: one pair of lanes per video track (so transitions can overlap), audio tracks, titles and overlays. */
@UnstableApi
class Composer(private val context: Context) {
    class Built(val composition: Composition, val durationMs: Long, val multiLane: Boolean)

    private fun us(ms: Long) = ms * 1000

    /** Audio gain ducking: clip-local intervals where louder sound plays on other tracks. */
    private fun duckIntervals(project: Project, track: Track, clip: Clip): List<Triple<Double, Double, Double>> {
        if (!track.duck) return emptyList()
        val out = mutableListOf<Triple<Double, Double, Double>>()
        for (other in project.tracks) {
            if (other.id == track.id || other.muted || other.kind == TrackKind.text) continue
            for (c in other.clips) {
                val a = project.asset(c.assetID) ?: continue
                if (!a.hasAudio || c.muted || c.volume < 0.06 || c.generator != null) continue
                val s = maxOf(c.start, clip.start); val e = minOf(c.end, clip.end)
                if (e > s) out += Triple((s - clip.start) / 1000.0, (e - clip.start) / 1000.0, track.duckLevel)
            }
        }
        return out
    }

    private fun audioProcessors(project: Project, track: Track, clip: Clip): List<AudioProcessor> {
        val duck = duckIntervals(project, track, clip)
        val plain = clip.volume == 1.0 && clip.fadeIn == 0L && clip.fadeOut == 0L && duck.isEmpty()
        if (plain) return emptyList()
        return listOf(AudioGain(AudioGain.curve(clip.volume, clip.fadeIn / 1000.0, clip.fadeOut / 1000.0, clip.duration / 1000.0, duck)))
    }

    private fun item(project: Project, track: Track, clip: Clip, asset: Asset, withAudio: Boolean, placement: Boolean = false): EditedMediaItem {
        val uri = Uri.parse(asset.url)
        val mediaItem = MediaItem.Builder().setUri(uri).apply {
            if (asset.isStill) setImageDurationMs(clip.duration)
            else setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionMs(clip.sourceIn).setEndPositionMs(minOf(clip.sourceIn + clip.sourceLength, asset.duration)).build())   // Media3 refuses a clip that ends after its file (a rendered transition can be a frame short)
        }.build()
        val speedy = clip.speed != 1.0 && !asset.isStill
        // Speed goes through EditedMediaItem.setSpeed: CompositionPlayer rejects hand-made speed effects.
        val video = 
            (if (asset.hasVideo) ClipEffects.look(clip.look) + ClipEffects.scene(clip.effects, us(clip.duration)) + (if (placement) ClipEffects.placement(clip) else emptyList()) else emptyList())
        val audio = (if (withAudio && asset.hasAudio && !track.muted) audioProcessors(project, track, clip) else emptyList())
        val b = EditedMediaItem.Builder(mediaItem).setEffects(Effects(audio, video))
        if (speedy) b.setSpeed(ConstantSpeed(clip.speed.toFloat()))
        if (asset.isStill) b.setDurationUs(us(clip.duration)).setFrameRate(project.fps) else b.setDurationUs(us(asset.duration))   // the preview needs the file's length up front
        if (!withAudio || !asset.hasAudio || track.muted || clip.muted) b.setRemoveAudio(true)
        return b.build()
    }

    /** Clips go back to back on the first lane; only a clip that overlaps the previous one (a transition) moves to the second lane. Fewer gaps and decoders than alternating. */
    private fun lanesOf(track: Track): List<List<Clip>> {
        val lanes = listOf(mutableListOf<Clip>(), mutableListOf<Clip>()); val end = longArrayOf(0, 0)
        for (c in track.clips.filter { it.assetID != null }.sortedBy { it.start }) {
            val l = if (c.start >= end[0]) 0 else 1
            lanes[l] += c; end[l] = c.end
        }
        return lanes
    }

    fun build(project: Project, reuse: TransitionCompositor? = null, outputFps: Int? = null): Built {
        val sequences = mutableListOf<EditedMediaItemSequence>()
        val layers = mutableListOf<Layer>()
        // With one video lane Media3 has no compositor: the clip's own placement is then applied as an effect.
        val videoLanes = project.tracks.filter { it.kind == TrackKind.video && !it.hidden }.sumOf { t -> lanesOf(t).count { it.isNotEmpty() } }
        val singleLane = videoLanes <= 1
        // Media3 draws the first input on top: the first track in the list is the top layer, so it comes first.
        for (track in project.tracks) {
            if (track.kind == TrackKind.video && !track.hidden) {
                for (mine in lanesOf(track)) {
                    if (mine.isEmpty()) continue
                    val seq = EditedMediaItemSequence.Builder().experimentalSetForceVideoTrack(true)
                        .experimentalSetForceAudioTrack(mine.any { project.asset(it.assetID)?.hasAudio == true && !it.muted && !track.muted })   // a lane may start with a gap
                    var cursor = 0L
                    for (c in mine) {
                        val asset = project.asset(c.assetID) ?: continue
                        if (c.start > cursor) seq.addGap(us(c.start - cursor))
                        seq.addItem(item(project, track, c, asset, withAudio = true, placement = singleLane))
                        cursor = c.end
                    }
                    if (!singleLane && cursor < project.duration) seq.addGap(us(project.duration - cursor))   // every lane runs to the end: Media3 stalls when one layer ends while another continues
                    sequences += seq.build(); layers += Layer(track.id, mine)
                }
            } else if (track.kind == TrackKind.audio) {
                val clips = track.clips.filter { it.assetID != null }.sortedBy { it.start }
                if (clips.isEmpty()) continue
                // Audio clips may not overlap in a sequence; overlaps (transitions) cannot happen on audio tracks with the same rules, so one lane is enough.
                val seq = EditedMediaItemSequence.Builder().setIsLooping(false).experimentalSetForceAudioTrack(true)
                var cursor = 0L
                for (c in clips) {
                    val asset = project.asset(c.assetID) ?: continue
                    if (c.start > cursor) seq.addGap(us(c.start - cursor))
                    seq.addItem(item(project, track, c, asset, withAudio = true))
                    cursor = c.end
                }
                sequences += seq.build(); layers += Layer(track.id, emptyList())
            }
        }
        if (sequences.isEmpty()) throw IllegalStateException("nothing to play")
        val overlays = Overlays.build(project)
        val b = Composition.Builder(sequences)
        val finalEffects = mutableListOf<Effect>()
        if (outputFps != null && outputFps < 30) finalEffects += androidx.media3.effect.FrameDropEffect.createDefaultFrameDropEffect(outputFps.toFloat())
        if (singleLane) finalEffects += androidx.media3.effect.Presentation.createForWidthAndHeight(project.width, project.height, androidx.media3.effect.Presentation.LAYOUT_SCALE_TO_FIT)
        else b.setVideoCompositorSettings(reuse?.also { it.update(project, layers) } ?: TransitionCompositor(project, layers))
        if (overlays.isNotEmpty()) finalEffects += androidx.media3.effect.OverlayEffect(overlays)
        if (finalEffects.isNotEmpty()) b.setEffects(Effects(emptyList(), finalEffects))
        return Built(b.build(), project.duration, !singleLane)
    }

    class Layer(val trackId: Id, val clips: List<Clip>)
}

/** Constant playback speed for one item. */
@UnstableApi
class ConstantSpeed(private val speed: Float) : androidx.media3.common.audio.SpeedProvider {
    override fun getSpeed(timeUs: Long) = speed
    override fun getNextSpeedChangeTimeUs(timeUs: Long) = androidx.media3.common.C.TIME_UNSET
}
