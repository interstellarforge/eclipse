package app.lumacut.media

import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import app.lumacut.core.*
import kotlin.math.min

/**
 * Places every video layer in the output frame for each moment: fit inside the canvas, the clip's scale/offset/rotation/opacity (with keyframes
 * and fades) and, where two clips overlap, the transition. Media3 can only move, scale, rotate and fade layers, so the 47 styles are shown
 * as one of four families (cross-dissolve, dip, push, zoom/spin); the exported movie matches the preview.
 */
@UnstableApi
class TransitionCompositor(project: Project = Project(), layers: List<Composer.Layer> = emptyList()) : VideoCompositorSettings {
    @Volatile private var project: Project = project
    @Volatile private var layers: List<Composer.Layer> = layers

    /** The preview keeps one instance for its whole life, because Media3 may keep using the first settings it was given. */
    fun update(project: Project, layers: List<Composer.Layer>) { this.project = project; this.layers = layers }

    private var inputSizes = listOf<Size>()

    override fun getOutputSize(inputSizes: List<Size>): Size {
        this.inputSizes = inputSizes
        return Size(project.width, project.height)
    }

    enum class Family { Dissolve, Dip, Push, Zoom, Spin }

    companion object {
        fun family(t: TransitionType): Family = when (t) {
            TransitionType.fadeBlack, TransitionType.fadeWhite, TransitionType.flashCut, TransitionType.shutter -> Family.Dip
            TransitionType.slide, TransitionType.slideRight, TransitionType.slideUp, TransitionType.slideDown, TransitionType.cover, TransitionType.uncover,
            TransitionType.whipLeft, TransitionType.whipRight, TransitionType.splitSlide, TransitionType.squeeze, TransitionType.cubeSpin,
            TransitionType.wipe, TransitionType.wipeLeft, TransitionType.wipeUp, TransitionType.wipeDown -> Family.Push
            TransitionType.zoom, TransitionType.zoomBlur -> Family.Zoom
            TransitionType.spin, TransitionType.rotateZoom -> Family.Spin
            else -> Family.Dissolve
        }

        /** Direction the incoming clip arrives from, as (x, y) in frame fractions (+x right, +y up). */
        fun pushDirection(t: TransitionType): Pair<Double, Double> = when (t) {
            TransitionType.slideRight, TransitionType.wipe -> -1.0 to 0.0
            TransitionType.slideUp, TransitionType.wipeUp -> 0.0 to -1.0
            TransitionType.slideDown, TransitionType.wipeDown -> 0.0 to 1.0
            TransitionType.whipRight -> -1.0 to 0.0
            else -> 1.0 to 0.0
        }
    }

    /** What the layer shows at composition time `t` (ms). */
    class Placement(val alpha: Double, val scaleX: Double, val scaleY: Double, val dx: Double, val dy: Double, val rotation: Double)

    internal fun placement(layer: Composer.Layer, inputSize: Size?, tMs: Long, isTop: Boolean): Placement? {
        val clip = layer.clips.firstOrNull { tMs >= it.start && tMs < it.end } ?: return null
        val local = tMs - clip.start
        var alpha = clip.opacity; var scale = clip.scale; var dx = clip.offsetX; var dy = clip.offsetY; var rot = 0.0
        Keyframe.interpolate(clip.keyframes, local.toDouble())?.let { alpha = it.opacity; scale = it.scale; dx = it.offsetX; dy = it.offsetY; rot = it.rotation }
        if (clip.fadeIn > 0 && local < clip.fadeIn) alpha *= local.toDouble() / clip.fadeIn
        if (clip.fadeOut > 0 && local > clip.duration - clip.fadeOut) alpha *= maxOf(0.0, (clip.duration - local).toDouble() / clip.fadeOut)

        // Fit the picture inside the canvas.
        var sx = 1.0; var sy = 1.0
        // The picture size comes from the project, because Media3 reports input sizes only when a graph is first built.
        val asset = project.asset(clip.assetID)
        val size = if (asset != null && asset.width > 0 && asset.height > 0) Size(asset.width, asset.height) else inputSize
        if (size != null && size.width > 0 && size.height > 0) {
            // Media3 draws a layer at its own pixel size times the scale, so fitting means scaling by canvas / picture.
            val fit = min(project.width.toDouble() / size.width, project.height.toDouble() / size.height)
            sx = fit; sy = fit
        }
        sx *= scale; sy *= scale

        val incoming = project.transitions.firstOrNull { it.toClip == clip.id && tMs < (project.clip(it.fromClip)?.end ?: 0) }
        val outgoing = project.transitions.firstOrNull { it.fromClip == clip.id && tMs >= (project.clip(it.toClip)?.start ?: Long.MAX_VALUE) }
        val tr = incoming ?: outgoing
        if (tr != null) {
            val from = project.clip(tr.fromClip); val to = project.clip(tr.toClip)
            if (from != null && to != null) {
                val p = ((tMs - to.start).toDouble() / maxOf(1L, from.end - to.start)).coerceIn(0.0, 1.0)
                val isIn = incoming != null
                when (family(tr.type)) {
                    Family.Dissolve -> if (isTop) alpha *= if (isIn) p else 1 - p
                    Family.Dip -> alpha *= if (isIn) maxOf(0.0, 2 * p - 1) else maxOf(0.0, 1 - 2 * p)
                    Family.Push -> {
                        val (ux, uy) = pushDirection(tr.type)
                        if (isIn) { dx += ux * (1 - p) * 2; dy += uy * (1 - p) * 2 } else { dx -= ux * p * 2; dy -= uy * p * 2 }
                    }
                    Family.Zoom -> { if (isTop) alpha *= if (isIn) p else 1 - p; val z = if (isIn) 1.6 - 0.6 * p else 1 + 0.6 * p; sx *= z; sy *= z }
                    Family.Spin -> {
                        if (isTop) alpha *= if (isIn) p else 1 - p
                        if (isIn) { val z = 0.35 + 0.65 * p; sx *= z; sy *= z; rot += (1 - p) * -90 } else { val z = 1 - 0.5 * p; sx *= z; sy *= z; rot += p * 90 }
                    }
                }
            }
        }
        return Placement(alpha.coerceIn(0.0, 1.0), sx, sy, dx, dy, rot)
    }

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val layer = layers.getOrNull(inputId)
        val tMs = presentationTimeUs / 1000
        // Later layers sit above earlier ones; a lane pair of one track alternates, so the later lane is the one on top.
        val idx = layers.indexOf(layer); val isTop = layer != null && idx >= 0 && idx + 1 < layers.size && layers[idx + 1].trackId == layer.trackId
        val p = layer?.let { placement(it, inputSizes.getOrNull(inputId), tMs, isTop) }
        if (p == null) return Settings(alpha = 0f)
        return Settings(p.alpha.toFloat(), p.scaleX.toFloat(), p.scaleY.toFloat(), p.rotation.toFloat(), (p.dx * 2).toFloat(), (p.dy * 2).toFloat())
    }
}
