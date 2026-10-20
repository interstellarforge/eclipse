package app.lumacut.ui

import android.graphics.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import app.lumacut.core.*
import app.lumacut.media.Generators
import app.lumacut.media.Overlays

/** Small still pictures for the tabs: a demo scene with a look applied, a title on dark, an overlay over the scene. */
object Previews {
    private const val W = 320; private const val H = 180

    fun scene(): Bitmap {
        val b = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888); val c = Canvas(b)
        c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), Paint().apply { shader = LinearGradient(0f, 0f, 0f, H.toFloat(), 0xFFFA9E59.toInt(), 0xFF598CE6.toInt(), Shader.TileMode.CLAMP) })
        c.drawRect(0f, H * 0.72f, W.toFloat(), H.toFloat(), Paint().apply { color = 0xFF1F3324.toInt() })
        c.drawCircle(W * 0.72f, H * 0.3f, H * 0.11f, Paint().apply { color = 0xFFFFF2B3.toInt() })
        val red = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFD92633.toInt() }
        c.drawCircle(W * 0.45f, H * 0.42f, H * 0.1f, red); c.drawRect(W * 0.45f - H * 0.08f, H * 0.5f, W * 0.45f + H * 0.08f, H * 0.88f, red)
        return b
    }
    private val base by lazy { scene() }

    /** A colour look drawn with a colour matrix and a vignette (an approximation of what the exported picture gets). */
    fun look(look: Look, effects: List<EffectType> = emptyList()): Bitmap {
        val out = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888); val c = Canvas(out)
        val m = ColorMatrix()
        m.setSaturation(look.saturation.toFloat())
        val contrast = look.contrast.toFloat(); val t = (-0.5f * contrast + 0.5f + look.brightness.toFloat()) * 255f
        m.postConcat(ColorMatrix(floatArrayOf(contrast, 0f, 0f, 0f, t, 0f, contrast, 0f, 0f, t, 0f, 0f, contrast, 0f, t, 0f, 0f, 0f, 1f, 0f)))
        if (look.sepia > 0) { val s = ColorMatrix(floatArrayOf(.393f, .769f, .189f, 0f, 0f, .349f, .686f, .168f, 0f, 0f, .272f, .534f, .131f, 0f, 0f, 0f, 0f, 0f, 1f, 0f)); val mixed = ColorMatrix(); mixed.set(floatArrayOf(1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f)); for (i in 0 until 20) mixed.array[i] = mixed.array[i] * (1 - look.sepia.toFloat()) + s.array[i] * look.sepia.toFloat(); m.postConcat(mixed) }
        if (look.warmth != 0.0) m.postConcat(ColorMatrix(floatArrayOf(1f, 0f, 0f, 0f, look.warmth.toFloat() * 20f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, -look.warmth.toFloat() * 20f, 0f, 0f, 0f, 1f, 0f)))
        if (look.fade > 0) m.postConcat(ColorMatrix(floatArrayOf(1f - look.fade.toFloat() * .3f, 0f, 0f, 0f, 25f * look.fade.toFloat(), 0f, 1f - look.fade.toFloat() * .3f, 0f, 0f, 25f * look.fade.toFloat(), 0f, 0f, 1f - look.fade.toFloat() * .3f, 0f, 25f * look.fade.toFloat(), 0f, 0f, 0f, 1f, 0f)))
        c.drawBitmap(base, 0f, 0f, Paint().apply { colorFilter = ColorMatrixColorFilter(m) })
        if (look.splitAmount > 0 && look.splitShadows != null) {
            val sh = Color.parseColor("#" + look.splitShadows); val hi = Color.parseColor("#" + (look.splitHighlights ?: "FFFFFF"))
            c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), Paint().apply { shader = LinearGradient(0f, 0f, 0f, H.toFloat(), (hi and 0xFFFFFF) or ((look.splitAmount * 90).toInt() shl 24), (sh and 0xFFFFFF) or ((look.splitAmount * 110).toInt() shl 24), Shader.TileMode.CLAMP) })
        }
        if (look.vignette > 0) c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), Paint().apply { shader = RadialGradient(W / 2f, H / 2f, W * 0.65f, intArrayOf(0, 0, ((look.vignette * 255).toInt().coerceIn(0, 255) shl 24)), floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP) })
        if (EffectType.cinemaBars in effects) { val p = Paint().apply { color = Color.BLACK }; c.drawRect(0f, 0f, W.toFloat(), H * 0.13f, p); c.drawRect(0f, H * 0.87f, W.toFloat(), H.toFloat(), p) }
        return out
    }

    fun title(preset: TitlePreset): Bitmap {
        val b = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888); val c = Canvas(b); c.drawColor(0xFF1B1C22.toInt())
        val text = Overlays.renderText(preset.sampleText, Project(width = W, height = H), preset.style)
        val st = preset.style
        val x = (st.x * W - when (st.align) { 0 -> 0f; 2 -> text.width.toFloat(); else -> text.width / 2f }).toFloat().coerceIn(0f, (W - text.width).toFloat().coerceAtLeast(0f))
        c.drawBitmap(text, x, ((1 - st.y) * H - text.height / 2f).toFloat().coerceIn(0f, (H - text.height).toFloat().coerceAtLeast(0f)), null)
        return b
    }

    fun overlay(kind: GeneratorKind): Bitmap {
        val b = base.copy(Bitmap.Config.ARGB_8888, true); val c = Canvas(b)
        Generators.draw(kind, c, 0.6, W.toFloat(), H.toFloat(), 2.5); return b
    }

    fun template(t: EditTemplate): Bitmap {
        val b = look(t.look, t.effects.map { it.type }); val c = Canvas(b)
        t.overlay?.let { Generators.draw(it, c, t.overlayAmount + 0.2, W.toFloat(), H.toFloat(), 2.5) }
        return b
    }
}

@Composable
fun PreviewImage(key: Any, modifier: Modifier = Modifier, make: () -> Bitmap) {
    val bmp = remember(key) { make() }
    Image(bmp.asImageBitmap(), null, modifier, contentScale = ContentScale.Crop)
}
