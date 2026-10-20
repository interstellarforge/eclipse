package app.lumacut.media

import android.content.Context
import android.graphics.*
import android.view.PixelCopy
import android.view.SurfaceView
import app.lumacut.core.Asset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume

/** Pictures for the assistant: contact sheets of a clip or the timeline, and single frames, as JPEG. */
object FrameTools {
    fun label(ms: Long) = "%d:%02d.%d".format(ms / 60000, (ms / 1000) % 60, (ms % 1000) / 100)

    fun sheet(frames: List<Pair<Long, Bitmap>>, columns: Int = 4, tileW: Int = 360): ByteArray? {
        if (frames.isEmpty()) return null
        val tileH = frames.maxOf { (it.second.height * tileW / it.second.width.toFloat()).toInt() }
        val rows = (frames.size + columns - 1) / columns
        val out = Bitmap.createBitmap(tileW * minOf(columns, frames.size), tileH * rows, Bitmap.Config.ARGB_8888)
        val c = Canvas(out); c.drawColor(Color.BLACK)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = tileW / 14f; setShadowLayer(4f, 0f, 0f, Color.BLACK) }
        frames.forEachIndexed { i, (t, bmp) ->
            val x = (i % columns) * tileW; val y = (i / columns) * tileH
            val h = (bmp.height * tileW / bmp.width.toFloat()).toInt()
            c.drawBitmap(bmp, null, Rect(x, y + (tileH - h) / 2, x + tileW, y + (tileH - h) / 2 + h), null)
            c.drawText(label(t), x + 8f, y + tileH - 10f, text)
        }
        return ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }

    suspend fun contactSheet(ctx: Context, asset: Asset, count: Int, startMs: Long?, endMs: Long?): ByteArray? = withContext(Dispatchers.IO) {
        val a = (startMs ?: 0).coerceAtLeast(0); val b = (endMs ?: asset.duration).coerceAtMost(asset.duration)
        val frames = (0 until count).mapNotNull { i ->
            val t = a + ((b - a) * (i + 0.5) / count).toLong()
            MediaProbe.thumbnail(ctx, asset, t, 480)?.let { t to it }
        }
        sheet(frames, columns = if (count > 8) 4 else if (count > 4) 3 else 2)
    }

    /** The picture the preview shows right now, copied from its surface. */
    suspend fun grab(view: SurfaceView): Bitmap? = suspendCancellableCoroutine { cont ->
        if (view.width == 0 || view.height == 0) { cont.resume(null); return@suspendCancellableCoroutine }
        val bmp = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(view, bmp, { result -> cont.resume(if (result == PixelCopy.SUCCESS) bmp else null) }, android.os.Handler(android.os.Looper.getMainLooper()))
    }

    fun jpeg(b: Bitmap): ByteArray = ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 82, it) }.toByteArray()
    suspend fun settle() = delay(450)
}
