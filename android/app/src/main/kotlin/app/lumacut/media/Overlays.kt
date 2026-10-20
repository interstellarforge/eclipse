package app.lumacut.media

import android.graphics.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.TextureOverlay
import app.lumacut.core.*
import kotlin.math.*

/** Titles and drawn overlays (confetti, snow, ...) as Media3 bitmap overlays on the finished picture. */
@UnstableApi
object Overlays {
    private val blank: Bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)

    fun build(project: Project): List<TextureOverlay> {
        val out = mutableListOf<TextureOverlay>()
        // First track in the list is the top layer; draw bottom-up.
        for (track in project.tracks.reversed()) {
            if (track.hidden) continue
            for (clip in track.clips) {
                if (clip.text != null && track.kind == TrackKind.text) out += TitleOverlay(project, clip)
                else if (clip.generator != null) out += GeneratorOverlay(project, clip)
            }
        }
        return out
    }

    private fun fade(clip: Clip, local: Long): Double {
        var a = 1.0
        if (clip.fadeIn > 0 && local < clip.fadeIn) a *= local.toDouble() / clip.fadeIn
        if (clip.fadeOut > 0 && local > clip.duration - clip.fadeOut) a *= maxOf(0.0, (clip.duration - local).toDouble() / clip.fadeOut)
        return a
    }

    /** A title: a bitmap the size of the text, placed by the clip's style; the entrance animation moves, scales or fades it. */
    class TitleOverlay(private val project: Project, private val clip: Clip) : BitmapOverlay() {
        private val style = clip.style
        private val textFull = (if (style.uppercase) clip.text!!.uppercase() else clip.text!!)
        private var cache: Pair<Int, Bitmap>? = null

        private fun visibleChars(local: Long): Int =
            if (style.animation == TextAnimation.typewriter) (textFull.length * (local.toDouble() / maxOf(1L, style.animationMs)).coerceIn(0.0, 1.0)).toInt().coerceAtLeast(1) else textFull.length

        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            val t = presentationTimeUs / 1000
            if (t < clip.start || t >= clip.end) return blank
            val n = visibleChars(t - clip.start)
            cache?.let { if (it.first == n) return it.second }
            return renderText(textFull.substring(0, n), project, style).also { cache = n to it }
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val t = presentationTimeUs / 1000
            if (t < clip.start || t >= clip.end) return Settings(alpha = 0f)
            val local = t - clip.start
            var alpha = fade(clip, local)
            var dx = 0.0; var dy = 0.0; var scale = 1.0
            val u = (local.toDouble() / maxOf(1L, style.animationMs)).coerceIn(0.0, 1.0); val e = 1 - (1 - u) * (1 - u)
            when (style.animation) {
                TextAnimation.fade -> alpha *= u
                TextAnimation.slideUp -> { dy = -(1 - e) * 0.12; alpha *= u }
                TextAnimation.slideDown -> { dy = (1 - e) * 0.12; alpha *= u }
                TextAnimation.slideLeft -> { dx = (1 - e) * 0.3; alpha *= u }
                TextAnimation.pop -> { scale = 0.5 + 0.5 * (if (u < 1) e + sin(u * PI) * 0.15 else 1.0); alpha *= min(1.0, u * 3) }
                else -> {}
            }
            val ax = style.x * 2 - 1 + dx * 2; val ay = style.y * 2 - 1 + dy * 2
            val shift = when (style.align) { 0 -> 1f; 2 -> -1f; else -> 0f }   // x is where the text starts, centres or ends
            return Settings(alpha.toFloat(), scale.toFloat(), scale.toFloat(), 0f, ax.toFloat(), ay.toFloat(), shift, 0f)
        }
    }

    fun renderText(text: String, project: Project, style: TextStyle): Bitmap {
        val px = (style.size * project.height).toFloat()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = px; color = Color.parseColor("#" + style.colorHex)
            typeface = Typeface.create(style.fontName ?: "sans-serif", if (style.bold) Typeface.BOLD else Typeface.NORMAL)
            letterSpacing = style.tracking.toFloat()
        }
        val lines = text.split("\n")
        val widths = lines.map { paint.measureText(it) }
        val pad = px * 0.35f
        val w = (widths.maxOrNull() ?: 1f) + pad * 2; val lineH = px * 1.25f; val h = lineH * lines.size + pad * 2
        val bmp = Bitmap.createBitmap(w.toInt().coerceAtLeast(2), h.toInt().coerceAtLeast(2), Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        if (style.box) c.drawRoundRect(RectF(0f, 0f, w, h), px * 0.2f, px * 0.2f, Paint().apply { color = Color.argb(150, 0, 0, 0) })
        lines.forEachIndexed { i, line ->
            val x = when (style.align) { 0 -> pad; 2 -> w - pad - widths[i]; else -> (w - widths[i]) / 2 }
            val y = pad + lineH * i + px
            if (style.glow) { val g = Paint(paint).apply { maskFilter = BlurMaskFilter(px * 0.35f, BlurMaskFilter.Blur.NORMAL); alpha = 200 }; c.drawText(line, x, y, g) }
            if (style.shadow) c.drawText(line, x + px * 0.04f, y + px * 0.05f, Paint(paint).apply { color = Color.argb(160, 0, 0, 0) })
            if (style.outline) c.drawText(line, x, y, Paint(paint).apply { this.style = Paint.Style.STROKE; strokeWidth = px * 0.09f; color = Color.BLACK; strokeJoin = Paint.Join.ROUND })
            c.drawText(line, x, y, paint)
        }
        return bmp
    }

    class GeneratorOverlay(private val project: Project, private val clip: Clip) : BitmapOverlay() {
        private val w = (project.width / 2).coerceAtLeast(2); private val h = (project.height / 2).coerceAtLeast(2)
        private val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        private val canvas = Canvas(bmp)
        private var lastFrame = -1L

        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            val t = presentationTimeUs / 1000
            if (t < clip.start || t >= clip.end) return blank
            val frame = t / 40   // 25 pictures per second is plenty for particles
            if (frame != lastFrame) {
                lastFrame = frame
                bmp.eraseColor(Color.TRANSPARENT)
                Generators.draw(clip.generator!!, canvas, clip.generatorAmount, w.toFloat(), h.toFloat(), (t - clip.start) / 1000.0)
            }
            return bmp
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val t = presentationTimeUs / 1000
            if (t < clip.start || t >= clip.end) return Settings(alpha = 0f)
            return Settings(alpha = fade(clip, t - clip.start).toFloat(), scaleX = 2f, scaleY = 2f)
        }
    }
}

/** Canvas versions of the drawn overlay layers; every particle is a pure function of its number and the time. */
object Generators {
    private fun rnd(i: Int, salt: Int): Double {
        var x = (i * 2654435761L + salt * 40503L + 97) and 0xFFFFFFFFL
        x = x xor (x shl 13) and 0xFFFFFFFFL; x = x xor (x shr 7); x = x xor (x shl 17) and 0xFFFFFFFFL
        return ((x * 0x2545F4914F6CDD1DL) ushr 11).toDouble() / (1L shl 53)
    }
    private fun wrap(v: Double, range: Double) = v - range * floor(v / range)
    private fun paint(r: Int, g: Int, b: Int, a: Int = 255) = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(a, r, g, b) }

    fun draw(kind: GeneratorKind, c: Canvas, amount: Double, W: Float, H: Float, t: Double) {
        val unit = H / 540f
        fun glow(x: Float, y: Float, r: Float, color: Int, alpha: Float) {
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.shader = RadialGradient(x, y, maxOf(1f, r), Color.argb((alpha * 255).toInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color)), Color.argb(0, Color.red(color), Color.green(color), Color.blue(color)), Shader.TileMode.CLAMP)
            c.drawCircle(x, y, r, p)
        }
        when (kind) {
            GeneratorKind.confetti -> {
                val colors = intArrayOf(0xFF4059, 0xFFCC1A, 0x33CC80, 0x408CFF, 0xCC59FF, 0xFF8C26)
                for (i in 0 until (40 + 180 * amount).toInt()) {
                    val speed = H * (0.22 + 0.3 * rnd(i, 2)); val y = -15 + wrap(rnd(i, 3) * (H + 30) + t * speed, H + 30.0).toFloat()
                    val x = (rnd(i, 1) * W + sin(t * 2 + i) * 7 * unit).toFloat(); val size = ((4 + 4 * rnd(i, 4)) * unit).toFloat()
                    c.save(); c.translate(x, y); c.rotate((t * (rnd(i, 5) * 8 - 4) + rnd(i, 6) * 6).toFloat() * 57.3f)
                    c.drawRect(-size / 2, -size / 4, size / 2, size / 4, Paint().apply { color = 0xFF000000.toInt() or colors[i % colors.size] }); c.restore()
                }
            }
            GeneratorKind.snow -> for (i in 0 until (60 + 260 * amount).toInt()) {
                val depth = 0.3 + 0.7 * rnd(i, 2); val y = -5 + wrap(rnd(i, 3) * (H + 10) + t * H * 0.08 * (0.5 + depth), H + 10.0).toFloat()
                val x = (rnd(i, 1) * W + sin(t * (0.5 + rnd(i, 4)) + i) * 12 * unit).toFloat(); val r = ((1 + 2 * depth) * unit).toFloat()
                c.drawCircle(x, y, r, paint(255, 255, 255, ((0.35 + 0.55 * depth) * 255).toInt()))
            }
            GeneratorKind.rain -> {
                val p = paint(217, 235, 255, 90).apply { strokeWidth = 1f * unit; style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
                for (i in 0 until (120 + 480 * amount).toInt()) {
                    val speed = H * (1.1 + 0.6 * rnd(i, 2)); val len = ((11 + 13 * rnd(i, 4)) * unit).toFloat()
                    val y = -20 + wrap(rnd(i, 3) * (H + 40) + t * speed, H + 40.0).toFloat(); val x = (wrap(rnd(i, 1) * (W + 100) - 50 + y * 0.15, W + 100.0) - 50).toFloat()
                    c.drawLine(x, y, x - len * 0.15f, y + len, p)
                }
            }
            GeneratorKind.sparkles, GeneratorKind.stars -> for (i in 0 until (if (kind == GeneratorKind.stars) 50 + 250 * amount else 20 + 80 * amount).toInt()) {
                val tw = 0.3 + 0.7 * max(0.0, sin(t * (0.8 + 2 * rnd(i, 4)) + rnd(i, 5) * 6.28)).pow(2)
                val x = (rnd(i, 1) * W).toFloat(); val y = (rnd(i, 2) * H).toFloat(); val r = ((0.5 + 1.5 * rnd(i, 3)) * unit).toFloat()
                c.drawCircle(x, y, r, paint(255, 250, 230, (tw * 255).toInt()))
                if (rnd(i, 6) > 0.8) { val p = paint(255, 255, 255, (tw * 150).toInt()).apply { strokeWidth = unit }; c.drawLine(x - r * 5, y, x + r * 5, y, p); c.drawLine(x, y - r * 5, x, y + r * 5, p) }
            }
            GeneratorKind.bokeh -> for (i in 0 until (6 + 20 * amount).toInt()) {
                val x = (W * (0.5 + 0.55 * sin(t * (0.05 + 0.1 * rnd(i, 2)) + rnd(i, 1) * 6.28))).toFloat(); val y = (H * (0.5 + 0.5 * sin(t * (0.04 + 0.08 * rnd(i, 4)) + rnd(i, 3) * 6.28))).toFloat()
                val r = ((15 + 40 * rnd(i, 5)) * unit).toFloat(); glow(x, y, r, Color.rgb(255, (200 + 55 * rnd(i, 6)).toInt(), (150 + 80 * rnd(i, 7)).toInt()), (0.15 + 0.25 * rnd(i, 8)).toFloat())
            }
            GeneratorKind.dust -> {
                for (i in 0 until (30 + 120 * amount).toInt()) { val x = (rnd(i, 1) * W).toFloat(); val y = (rnd(i, 2) * H).toFloat(); if ((t * 12 + i).toInt() % 3 == 0) c.drawCircle(x, y, ((0.5 + rnd(i, 3)) * unit).toFloat(), paint(240, 235, 220, 120)) }
                val p = paint(240, 235, 220, 70).apply { strokeWidth = 0.6f * unit }
                for (i in 0 until 3) if (rnd((t * 12).toInt(), 20 + i) < 0.5) { val x = (rnd((t * 12).toInt(), 30 + i) * W).toFloat(); c.drawLine(x, 0f, x + 2, H, p) }
            }
            GeneratorKind.sunbeams -> {
                val sx = W * 0.95f; val sy = -H * 0.1f
                for (i in 0 until 9) {
                    val ang = PI * (1.08 + 0.42 * i / 8.0) + sin(t * 0.4 + i) * 0.03; val wid = 0.03 + 0.05 * rnd(i, 2)
                    val path = Path().apply { moveTo(sx, sy); lineTo(sx + (cos(ang - wid) * W * 2).toFloat(), sy - (sin(ang - wid) * W * 2).toFloat()); lineTo(sx + (cos(ang + wid) * W * 2).toFloat(), sy - (sin(ang + wid) * W * 2).toFloat()); close() }
                    c.drawPath(path, paint(255, 217, 128, ((0.06 + 0.16 * rnd(i, 3)) * (0.4 + 0.8 * amount) * 255).toInt().coerceAtMost(120)))
                }
                glow(sx, sy, H * 0.8f, Color.rgb(255, 230, 150), 0.5f)
            }
            GeneratorKind.frame -> {
                val border = H * (0.025f + 0.045f * amount.toFloat()); val p = paint(250, 247, 240)
                c.drawRect(0f, 0f, W, border, p); c.drawRect(0f, H - border * 1.8f, W, H, p); c.drawRect(0f, 0f, border, H, p); c.drawRect(W - border, 0f, W, H, p)
            }
            GeneratorKind.hearts -> for (i in 0 until (6 + 24 * amount).toInt()) {
                val life = wrap(rnd(i, 3) + t * (0.08 + 0.08 * rnd(i, 2)), 1.0); val x = (rnd(i, 1) * W + sin(t * 1.5 + i) * 15 * unit).toFloat(); val y = (H + 20 - life * (H + 40)).toFloat()
                val size = ((14 + 22 * rnd(i, 4)) * unit).toFloat(); val a = (min(1.0, life * 4) * min(1.0, (1 - life) * 3) * 230).toInt()
                val pth = Path().apply { moveTo(x, y + size * 0.35f); cubicTo(x - size, y - size * 0.3f, x - size * 0.3f, y - size, x, y - size * 0.35f); cubicTo(x + size * 0.3f, y - size, x + size, y - size * 0.3f, x, y + size * 0.35f) }
                c.drawPath(pth, paint(255, 70, 100, a))
            }
            GeneratorKind.fireflies -> for (i in 0 until (10 + 40 * amount).toInt()) {
                val x = (W * (0.5 + 0.48 * sin(t * (0.15 + 0.2 * rnd(i, 2)) + rnd(i, 1) * 6.28))).toFloat(); val y = (H * (0.5 + 0.45 * sin(t * (0.12 + 0.18 * rnd(i, 4)) + rnd(i, 3) * 6.28))).toFloat()
                val pulse = (0.35 + 0.65 * max(0.0, sin(t * (1 + 2 * rnd(i, 5)) + rnd(i, 6) * 6.28)).pow(2)).toFloat(); glow(x, y, ((5 + 7 * rnd(i, 7)) * unit).toFloat(), Color.rgb(255, 242, 128), 0.9f * pulse)
            }
            GeneratorKind.embers -> for (i in 0 until (30 + 150 * amount).toInt()) {
                val life = wrap(rnd(i, 3) + t * (0.08 + 0.12 * rnd(i, 2)), 1.0); val x = (rnd(i, 1) * W + sin(t * 1.3 + i) * 20 * unit * life).toFloat(); val y = (H - life * H * 1.05).toFloat()
                glow(x, y, ((1 + 2.5 * rnd(i, 4)) * unit * (1 - life * 0.6) * 2.5).toFloat(), Color.rgb(255, (165 - 75 * life).toInt(), 38), (1 - life).toFloat() * 0.9f)
            }
            GeneratorKind.petals -> for (i in 0 until (12 + 60 * amount).toInt()) {
                val life = wrap(rnd(i, 3) + t * (0.05 + 0.05 * rnd(i, 2)), 1.0); val x = (rnd(i, 1) * W + sin(t * (0.6 + rnd(i, 4)) + i) * 30 * unit).toFloat(); val y = (-10 + life * (H + 20)).toFloat()
                val s = ((5 + 6 * rnd(i, 5)) * unit).toFloat(); c.save(); c.translate(x, y); c.rotate((t * (rnd(i, 6) * 2 - 1) * 57 + rnd(i, 7) * 300).toFloat())
                c.drawOval(RectF(-s / 2, -s / 4, s / 2, s / 4), paint(255, (185 + 38 * rnd(i, 8)).toInt(), 205, 215)); c.restore()
            }
            GeneratorKind.bubbles -> for (i in 0 until (8 + 36 * amount).toInt()) {
                val life = wrap(rnd(i, 3) + t * (0.06 + 0.08 * rnd(i, 2)), 1.0); val x = (rnd(i, 1) * W + sin(t * 1.1 + i) * 10 * unit).toFloat(); val y = (H + 15 - life * (H + 30)).toFloat(); val r = ((5 + 17 * rnd(i, 4)) * unit).toFloat()
                c.drawCircle(x, y, r, paint(204, 235, 255, 30)); c.drawCircle(x, y, r, paint(217, 242, 255, 180).apply { style = Paint.Style.STROKE; strokeWidth = unit })
                c.drawCircle(x - r * 0.4f, y - r * 0.4f, r * 0.15f, paint(255, 255, 255, 180))
            }
            GeneratorKind.leaves -> {
                val colors = arrayOf(intArrayOf(217, 89, 26), intArrayOf(242, 153, 38), intArrayOf(179, 51, 26), intArrayOf(204, 179, 51))
                for (i in 0 until (10 + 50 * amount).toInt()) {
                    val life = wrap(rnd(i, 3) + t * (0.05 + 0.06 * rnd(i, 2)), 1.0); val x = (rnd(i, 1) * W + sin(t * (0.5 + rnd(i, 4)) + i) * 40 * unit).toFloat(); val y = (-15 + life * (H + 30)).toFloat()
                    val s = ((7 + 9 * rnd(i, 5)) * unit).toFloat(); val col = colors[i % 4]
                    c.save(); c.translate(x, y); c.rotate((sin(t * (0.8 + rnd(i, 6)) + i) * 69).toFloat())
                    val p = Path().apply { moveTo(0f, s); quadTo(s * 0.9f, 0f, 0f, -s); quadTo(-s * 0.9f, 0f, 0f, s); close() }; c.drawPath(p, paint(col[0], col[1], col[2], 230)); c.restore()
                }
            }
            GeneratorKind.fireworks -> {
                val period = 2.6
                for (b in 0 until 2 + (4 * amount).toInt()) {
                    val local = wrap(t + rnd(b, 1) * period, period) / period; if (local < 0.12) continue
                    val age = (local - 0.12) / 0.88; val seed = b + (t / period).toInt()
                    val cx = (W * (0.15 + 0.7 * rnd(seed, 2))).toFloat(); val cy = (H * (0.15 + 0.4 * rnd(seed, 3))).toFloat(); val hue = rnd(seed, 4)
                    val col = Color.rgb((150 + 105 * sin(hue * 6.28)).toInt().coerceIn(0, 255), (150 + 105 * sin(hue * 6.28 + 2)).toInt().coerceIn(0, 255), (150 + 105 * sin(hue * 6.28 + 4)).toInt().coerceIn(0, 255))
                    for (i in 0 until 48) {
                        val ang = i / 48.0 * 6.283; val dist = (1 - (1 - age).pow(2.2)) * H * 0.3 * (0.7 + 0.3 * rnd(i, 5))
                        glow((cx + cos(ang) * dist).toFloat(), (cy + sin(ang) * dist + age * age * H * 0.08).toFloat(), 4f * unit, col, ((1 - age) * 0.95).toFloat())
                    }
                }
            }
            GeneratorKind.smoke -> for (i in 0 until (5 + 9 * amount).toInt()) {
                val x = (wrap(rnd(i, 1) * W * 1.4 + t * W * (0.015 + 0.02 * rnd(i, 2)), W * 1.4) - W * 0.2).toFloat(); val y = (H * (0.15 + 0.7 * rnd(i, 3)) + sin(t * 0.3 + i) * 15 * unit).toFloat()
                glow(x, y, (H * (0.25 + 0.3 * rnd(i, 4))).toFloat(), Color.rgb(217, 217, 230), 0.2f)
            }
            GeneratorKind.streaks -> for (i in 0 until 2 + (4 * amount).toInt()) {
                val pos = wrap(t * (0.12 + 0.1 * rnd(i, 2)) + rnd(i, 1), 1.6) - 0.3; val y = (H * (0.15 + 0.7 * rnd(i, 3))).toFloat(); val x = (W * pos).toFloat(); val len = (W * (0.3 + 0.3 * rnd(i, 4))).toFloat()
                val p = Paint().apply { shader = LinearGradient(x - len / 2, y, x + len / 2, y, intArrayOf(Color.argb(0, 255, 204, 128), Color.argb(130, 255, 217, 153), Color.argb(0, 255, 204, 128)), null, Shader.TileMode.CLAMP) }
                c.drawRect(x - len / 2, y - 2 * unit, x + len / 2, y + 2 * unit, p)
            }
            GeneratorKind.digitalRain -> {
                val cell = 11f * unit; val glyphs = "01ｱｲｳｴｵｶｷｸｹｺ+=<>"
                val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = cell * 0.9f; typeface = Typeface.MONOSPACE }
                for (col in 0 until (W / cell).toInt()) if (rnd(col, 1) < 0.35 + 0.6 * amount) {
                    val head = wrap(t * (4 + 8 * rnd(col, 2)) + rnd(col, 3) * 40, 40 + H / cell.toDouble())
                    for (k in 0 until 14) {
                        val y = (head - k) * cell; if (y < 0 || y > H + cell) continue
                        val g = glyphs[(rnd(col * 31 + (head - k).toInt() + 1, 4) * glyphs.length).toInt() % glyphs.length]
                        tp.color = if (k == 0) Color.WHITE else Color.argb(((0.8 - k * 0.06).coerceAtLeast(0.0) * 255).toInt(), 50, 255, 100)
                        c.drawText(g.toString(), col * cell, y.toFloat(), tp)
                    }
                }
            }
        }
    }
}
