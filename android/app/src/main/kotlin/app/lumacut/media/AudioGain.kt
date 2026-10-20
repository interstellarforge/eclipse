package app.lumacut.media

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/** Volume, fade in/out and ducking on 16 bit PCM: `gain(seconds since the clip's start)`. */
@UnstableApi
class AudioGain(private val gain: (Double) -> Double) : BaseAudioProcessor() {
    private var frames = 0L

    override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) throw UnhandledAudioFormatException(inputAudioFormat)
        return inputAudioFormat
    }

    override fun onFlush() { frames = 0 }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        val out = replaceOutputBuffer(size)
        val channels = inputAudioFormat.channelCount
        val rate = inputAudioFormat.sampleRate.toDouble()
        var g = gain(frames / rate)
        var n = 0
        while (inputBuffer.remaining() >= 2 * channels) {
            if (n++ % 256 == 0) g = gain(frames / rate)   // the curve is smooth: update every few hundred frames
            for (c in 0 until channels) out.putShort((inputBuffer.short * g).toInt().coerceIn(-32768, 32767).toShort())
            frames++
        }
        out.flip()
    }

    companion object {
        /** Gain for a clip: constant volume, linear fades and ducking intervals (clip-local seconds: start, end, level). */
        fun curve(volume: Double, fadeInS: Double, fadeOutS: Double, durationS: Double, duck: List<Triple<Double, Double, Double>> = emptyList()): (Double) -> Double = { t ->
            var g = volume
            if (fadeInS > 0 && t < fadeInS) g *= t / fadeInS
            if (fadeOutS > 0 && t > durationS - fadeOutS) g *= maxOf(0.0, (durationS - t) / fadeOutS)
            for ((s, e, level) in duck) {   // a short ramp into and out of each ducked stretch
                val ramp = 0.15
                val k = when { t < s - ramp || t > e + ramp -> 0.0; t < s -> (t - (s - ramp)) / ramp; t > e -> 1 - (t - e) / ramp; else -> 1.0 }
                g *= 1 - k * (1 - level)
            }
            g
        }
    }
}
