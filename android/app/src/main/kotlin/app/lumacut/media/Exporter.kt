package app.lumacut.media

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.*
import app.lumacut.core.Project
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

/** Renders the project to an H.264/AAC MP4 with Media3 Transformer, the same Composition the preview plays. */
@UnstableApi
class Exporter(private val context: Context) {
    suspend fun export(project: Project, out: File, onProgress: (Float) -> Unit = {}, bitrate: Int? = null, outputFps: Int? = null): File = withContext(Dispatchers.Main) {
        val built = Composer(context).build(project, outputFps = outputFps)
        out.parentFile?.mkdirs(); if (out.exists()) out.delete()
        suspendCancellableCoroutine { cont ->
            val transformer = Transformer.Builder(context)
                .apply { if (bitrate != null) setEncoderFactory(DefaultEncoderFactory.Builder(context).setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build()).build()) }
                .setVideoMimeType(androidx.media3.common.MimeTypes.VIDEO_H264)
                .setAudioMimeType(androidx.media3.common.MimeTypes.AUDIO_AAC)
                .setMaxDelayBetweenMuxerSamplesMs(androidx.media3.common.C.TIME_UNSET)   // big projects can take a while between samples
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { cont.resume(out) }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) { cont.resumeWithException(exportException) }
                }).build()
            transformer.start(built.composition, out.absolutePath)
            val holder = ProgressHolder()
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            val poll = object : Runnable {
                override fun run() {
                    if (!cont.isActive) return
                    if (transformer.getProgress(holder) != Transformer.PROGRESS_STATE_NOT_STARTED) onProgress(holder.progress / 100f)
                    handler.postDelayed(this, 250)
                }
            }
            handler.post(poll)
            cont.invokeOnCancellation { transformer.cancel() }
        }
    }
}
