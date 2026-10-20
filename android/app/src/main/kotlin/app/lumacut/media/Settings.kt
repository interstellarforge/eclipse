package app.lumacut.media

import android.util.Pair
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.UnstableApi

/** Overlay placement computed per frame (Media3's own builder only makes fixed settings). Anchors are in -1..1 frame coordinates. */
@UnstableApi
class Settings(
    private val alpha: Float = 1f, private val scaleX: Float = 1f, private val scaleY: Float = 1f, private val rotation: Float = 0f,
    private val bgX: Float = 0f, private val bgY: Float = 0f, private val ovX: Float = 0f, private val ovY: Float = 0f,
) : OverlaySettings {
    override fun getAlphaScale() = alpha
    override fun getScale(): Pair<Float, Float> = Pair(scaleX, scaleY)
    override fun getRotationDegrees() = rotation
    override fun getBackgroundFrameAnchor(): Pair<Float, Float> = Pair(bgX, bgY)
    override fun getOverlayFrameAnchor(): Pair<Float, Float> = Pair(ovX, ovY)
}
