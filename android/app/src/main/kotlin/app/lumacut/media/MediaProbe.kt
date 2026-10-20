package app.lumacut.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import app.lumacut.core.Asset
import app.lumacut.core.Id
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteOrder
import kotlin.math.abs

/** Reads what a media file contains (length, picture, sound) and makes thumbnails, film strips and waveforms. */
object MediaProbe {
    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) { null } ?: uri.lastPathSegment?.substringAfterLast('/')

    suspend fun probe(context: Context, uri: Uri): Asset = withContext(Dispatchers.IO) {
        val mime = context.contentResolver.getType(uri) ?: ""
        val name = displayName(context, uri)
        if (mime.startsWith("image/")) {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o) }
            return@withContext Asset(url = uri.toString(), duration = 60_000, hasVideo = true, hasAudio = false, isStill = true, name = name, width = o.outWidth, height = o.outHeight)
        }
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            val dur = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: throw IllegalArgumentException("Can't read this file")
            val hasVideo = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val hasAudio = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rot = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rot == 90 || rot == 270) { val t = w; w = h; h = t }
            if (!hasVideo && !hasAudio) throw IllegalArgumentException("No picture or sound found")
            Asset(url = uri.toString(), duration = dur, hasVideo = hasVideo, hasAudio = hasAudio, name = name, width = w, height = h)
        } finally { r.release() }
    }

    suspend fun thumbnail(context: Context, asset: Asset, atMs: Long = 0, maxPx: Int = 240): Bitmap? = withContext(Dispatchers.IO) {
        try {
            if (!asset.hasVideo) return@withContext null
            if (asset.isStill) {
                val o = BitmapFactory.Options().apply { inSampleSize = maxOf(1, (maxOf(asset.width, asset.height) / (maxPx * 2))) }
                return@withContext context.contentResolver.openInputStream(Uri.parse(asset.url))?.use { BitmapFactory.decodeStream(it, null, o) }
            }
            val r = MediaMetadataRetriever()
            try {
                r.setDataSource(context, Uri.parse(asset.url))
                r.getScaledFrameAtTime(atMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxPx, maxPx * 9 / 16 + 1) ?: r.getFrameAtTime(atMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } finally { r.release() }
        } catch (_: Exception) { null }
    }

    /** A handful of frames across the file, for the timeline clips. */
    suspend fun filmstrip(context: Context, asset: Asset, count: Int = 8): List<Bitmap> = withContext(Dispatchers.IO) {
        if (!asset.hasVideo) return@withContext emptyList()
        if (asset.isStill) return@withContext listOfNotNull(thumbnail(context, asset))
        val out = mutableListOf<Bitmap>()
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, Uri.parse(asset.url))
            for (i in 0 until count) {
                val t = (asset.duration * (i + 0.5) / count).toLong()
                r.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 160, 90)?.let { out += it }
            }
        } catch (_: Exception) {} finally { r.release() }
        out
    }

    /** Peak levels (0..1) in `buckets` slices of the sound. */
    suspend fun waveform(context: Context, asset: Asset, buckets: Int = 400): FloatArray = withContext(Dispatchers.IO) {
        val peaks = FloatArray(buckets)
        if (!asset.hasAudio) return@withContext peaks
        val ex = MediaExtractor()
        try {
            ex.setDataSource(context, Uri.parse(asset.url), null)
            val track = (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return@withContext peaks
            ex.selectTrack(track)
            val format = ex.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0); codec.start()
            val info = MediaCodec.BufferInfo()
            val totalUs = maxOf(1L, asset.duration * 1000)
            var done = false; var eos = false
            while (!done) {
                if (!eos) {
                    val i = codec.dequeueInputBuffer(5_000)
                    if (i >= 0) {
                        val n = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (n < 0) { codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); eos = true }
                        else { codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance() }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 5_000)
                if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder()).asShortBuffer()
                    var peak = 0
                    while (buf.hasRemaining()) peak = maxOf(peak, abs(buf.get().toInt()))
                    val b = ((info.presentationTimeUs.toDouble() / totalUs) * buckets).toInt().coerceIn(0, buckets - 1)
                    peaks[b] = maxOf(peaks[b], peak / 32768f)
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) done = true
                }
            }
            codec.stop(); codec.release()
        } catch (_: Exception) {} finally { ex.release() }
        peaks
    }
}
