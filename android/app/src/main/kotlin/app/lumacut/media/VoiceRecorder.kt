package app.lumacut.media

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/** Records a voice-over from the microphone as AAC in an .m4a file. */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    val recording get() = recorder != null

    fun start(): File {
        val f = File(context.cacheDir, "voice-over-${System.currentTimeMillis() / 1000}.m4a")
        val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        r.setAudioSource(MediaRecorder.AudioSource.MIC); r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4); r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioSamplingRate(44_100); r.setAudioEncodingBitRate(128_000); r.setOutputFile(f.absolutePath)
        r.prepare(); r.start(); recorder = r; file = f
        return f
    }

    /** The finished file, or null when nothing useful was recorded. */
    fun stop(): File? {
        val r = recorder ?: return null
        recorder = null
        return try { r.stop(); file } catch (_: RuntimeException) { file?.delete(); null } finally { r.release() }
    }
}
