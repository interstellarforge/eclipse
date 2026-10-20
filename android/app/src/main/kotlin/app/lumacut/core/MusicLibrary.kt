package app.lumacut.core

import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.*

enum class Voice { pluck, piano, bell, square, saw }
enum class Bass { saw, sine, sub808 }

data class Song(
    val name: String, val category: String, val mood: String, val bpm: Double,
    val key: Int = 48,                 // MIDI note of the tonic (48 = C3)
    val minor: Boolean = false,
    val degrees: List<Int> = listOf(1, 5, 6, 4),
    val sevenths: Boolean = false,
    val kick: List<Int> = emptyList(), val snare: List<Int> = emptyList(), val clap: List<Int> = emptyList(), val hat: List<Int> = emptyList(), val openHat: List<Int> = emptyList(),
    val bassSteps: List<Int> = emptyList(), val pluckSteps: List<Int> = emptyList(),
    val voice: Voice = Voice.pluck, val bassVoice: Bass = Bass.saw,
    val melody: Boolean = false, val swing: Double = 0.0,
    val padLevel: Double = 0.18, val pluckLevel: Double = 0.12, val drumsFromBar: Int = 4,
    val riser: Boolean = false, val drone: Boolean = false,
) {
    constructor(name: String, category: String, mood: String, bpm: Int, key: Int = 48, minor: Boolean = false, degrees: List<Int> = listOf(1, 5, 6, 4), sevenths: Boolean = false,
                kick: List<Int> = emptyList(), snare: List<Int> = emptyList(), clap: List<Int> = emptyList(), hat: List<Int> = emptyList(), openHat: List<Int> = emptyList(),
                bassSteps: List<Int> = emptyList(), pluckSteps: List<Int> = emptyList(), voice: Voice = Voice.pluck, bassVoice: Bass = Bass.saw, melody: Boolean = false, swing: Double = 0.0,
                padLevel: Double = 0.18, pluckLevel: Double = 0.12, drumsFromBar: Int = 4, riser: Boolean = false, drone: Boolean = false) :
        this(name, category, mood, bpm.toDouble(), key, minor, degrees, sevenths, kick, snare, clap, hat, openHat, bassSteps, pluckSteps, voice, bassVoice, melody, swing, padLevel, pluckLevel, drumsFromBar, riser, drone)
}

/** Royalty-free music beds the app makes itself: no licences, and the tempo is known, so cuts can sit on the beat. */
object MusicLibrary {
    data class Track(val name: String, val bpm: Double, val mood: String, val category: String)

    val songs get() = SongData.songs
    val tracks: List<Track> get() = songs.map { Track(it.name, it.bpm, it.mood, it.category) }
    val categories: List<String> get() = tracks.map { it.category }.distinct().sorted()
    const val SAMPLE_RATE = 44_100
    private const val BARS = 24

    fun song(name: String) = songs.firstOrNull { it.name.equals(name, ignoreCase = true) }

    /** The rendered song as a WAV file in `dir` (made on first use). */
    fun file(name: String, dir: File): File {
        val s = song(name) ?: throw EditError("unknown song; call list_sounds")
        dir.mkdirs(); val f = File(dir, "${s.name}.wav")
        if (!f.exists()) writeWav(render(s), f)
        return f
    }

    fun writeWav(samples: FloatArray, f: File, rate: Int = SAMPLE_RATE) {
        val data = ByteArray(samples.size * 2)
        samples.forEachIndexed { i, v -> val s = (v.coerceIn(-1f, 1f) * 32767).toInt(); data[i * 2] = (s and 0xFF).toByte(); data[i * 2 + 1] = ((s shr 8) and 0xFF).toByte() }
        val out = ByteArrayOutputStream()
        fun int(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF); out.write((v shr 16) and 0xFF); out.write((v shr 24) and 0xFF) }
        fun short(v: Int) { out.write(v and 0xFF); out.write((v shr 8) and 0xFF) }
        out.write("RIFF".toByteArray()); int(36 + data.size); out.write("WAVEfmt ".toByteArray()); int(16); short(1); short(1); int(rate); int(rate * 2); short(2); short(16)
        out.write("data".toByteArray()); int(data.size); out.write(data)
        f.writeBytes(out.toByteArray())
    }

    // ---- Harmony

    private val majorScale = intArrayOf(0, 2, 4, 5, 7, 9, 11); private val minorScale = intArrayOf(0, 2, 3, 5, 7, 8, 10)
    private fun scaleNote(s: Song, degree: Int): Int { val sc = if (s.minor) minorScale else majorScale; val i = degree - 1; return s.key + sc[((i % 7) + 7) % 7] + 12 * Math.floorDiv(i, 7) }
    private fun chord(s: Song, d: Int) = (listOf(d, d + 2, d + 4) + if (s.sevenths) listOf(d + 6) else emptyList()).map { scaleNote(s, it) }
    private fun hz(midi: Int) = 440 * 2.0.pow((midi - 69) / 12.0)
    private fun stableHash(s: String): Long = s.fold(5381L) { a, c -> a * 33 + c.code }

    // ---- Synthesis (the same recipe as the macOS app)

    fun render(s: Song): FloatArray {
        val sr = SAMPLE_RATE.toDouble()
        val beat = 60 / s.bpm; val step = beat / 4; val barLength = beat * 4
        val buffer = DoubleArray(((BARS * barLength + 3) * sr).toInt())
        val hash = stableHash(s.name)
        var seed = (987_654L + hash) and 0xFFFFFFFFL
        fun noise(): Double { seed = (seed * 1_664_525L + 1_013_904_223L) and 0xFFFFFFFFL; return (seed shr 8).toDouble() / (1 shl 24) * 2 - 1 }
        fun rnd(a: Int, b: Int): Double {
            var x = (a.toLong() * 73_856_093L + b.toLong() * 19_349_663L + hash).toULong()
            x = x xor (x shl 13); x = x xor (x shr 7); x = x xor (x shl 17)
            return ((x * 0x2545F4914F6CDD1DuL) shr 11).toDouble() / (1L shl 53)
        }
        fun add(start: Double, count: Int, body: (Double) -> Double) {
            val first = (start * sr).toInt()
            if (first < 0 || first + count >= buffer.size) return
            for (i in 0 until count) buffer[first + i] += body(i / sr)
        }
        fun tone(at: Double, length: Double, freq: Double, amp: Double, attack: Double, release: Double, saw: Double = 0.0) {
            add(at, ((length + release) * sr).toInt()) { t ->
                val env = min(1.0, t / max(attack, 0.002)) * (if (t < length) 1.0 else max(0.0, 1 - (t - length) / release)); val p = freq * t
                (sin(2 * PI * p) + saw * (sin(4 * PI * p) * 0.5 + sin(6 * PI * p) * 0.33)) * env * amp
            }
        }
        fun lead(at: Double, freq: Double, amp: Double, length: Double) {
            when (s.voice) {
                Voice.pluck -> add(at, (0.6 * sr).toInt()) { t -> (sin(2 * PI * freq * t) + 0.4 * sin(4 * PI * freq * t)) * exp(-7 * t) * amp }
                Voice.piano -> add(at, (1.4 * sr).toInt()) { t ->
                    val env = min(1.0, t / 0.004)
                    (sin(2 * PI * freq * t) * exp(-2.2 * t) + 0.5 * sin(4 * PI * freq * t) * exp(-3.5 * t) + 0.25 * sin(6 * PI * freq * t) * exp(-5 * t) + 0.1 * sin(8 * PI * freq * t) * exp(-7 * t)) * env * amp * 1.3
                }
                Voice.bell -> add(at, (2.6 * sr).toInt()) { t -> (sin(2 * PI * freq * t) * exp(-1.6 * t) + 0.5 * sin(2 * PI * freq * 2.76 * t) * exp(-2.4 * t) + 0.3 * sin(2 * PI * freq * 5.4 * t) * exp(-3.4 * t)) * amp * 1.2 }
                Voice.square -> add(at, (max(0.12, length) * sr).toInt()) { t -> val p = freq * t; val env = exp(-6 * t) * 0.6 + 0.4 * (if (t < length) 1 else 0); (sin(2 * PI * p) + sin(6 * PI * p) / 3 + sin(10 * PI * p) / 5) * env * amp * 0.8 }
                Voice.saw -> add(at, (max(0.2, length) * sr).toInt()) { t -> val p = freq * t; val env = min(1.0, t / 0.01) * exp(-4 * t); (sin(2 * PI * p) + 0.5 * sin(4 * PI * p) + 0.33 * sin(6 * PI * p) + 0.25 * sin(8 * PI * p)) * env * amp * 0.55 }
            }
        }
        fun bass(at: Double, midi: Int, length: Double, amp: Double) {
            when (s.bassVoice) {
                Bass.saw -> tone(at, length, hz(midi), amp, 0.01, 0.06, 0.4)
                Bass.sine -> tone(at, length, hz(midi), amp, 0.01, 0.08)
                Bass.sub808 -> add(at, (0.9 * sr).toInt()) { t -> sin(2 * PI * (hz(midi) * (1 + 1.2 * exp(-18 * t)) * t)) * exp(-3 * t) * amp * 1.2 }
            }
        }
        fun kick(at: Double, amp: Double) = add(at, (0.35 * sr).toInt()) { t -> sin(2 * PI * (45 * t + 105 * (1 - exp(-28 * t)) / 28)) * exp(-9 * t) * amp }
        fun snare(at: Double, amp: Double) = add(at, (0.25 * sr).toInt()) { t -> (noise() * 0.7 + sin(2 * PI * 190 * t) * 0.4) * exp(-22 * t) * amp }
        fun clap(at: Double, amp: Double) = add(at, (0.2 * sr).toInt()) { t -> noise() * (exp(-60 * t) + (if (t > 0.012) 0.8 * exp(-60 * (t - 0.012)) else 0.0) + (if (t > 0.024) 0.7 * exp(-30 * (t - 0.024)) else 0.0)) * amp }
        fun hat(at: Double, amp: Double, open: Boolean = false) {
            var previous = 0.0
            add(at, ((if (open) 0.3 else 0.08) * sr).toInt()) { t -> val n = noise(); val d = (n - previous) * exp((if (open) -14 else -70) * t) * amp; previous = n; d }
        }

        val pentatonic = if (s.minor) intArrayOf(0, 3, 5, 7, 10) else intArrayOf(0, 2, 4, 7, 9)
        fun penta(i: Int) = s.key + 24 + pentatonic[((i % 5) + 5) % 5] + 12 * Math.floorDiv(i, 5)
        var tune = 5
        for (bar in 0 until BARS) {
            val t0 = bar * barLength
            val degree = s.degrees[bar % s.degrees.size]; val notes = chord(s, degree)
            val intro = min(bar + 1, 2) / 2.0
            for (n in notes) tone(t0, barLength, hz(n + 12), s.padLevel * intro / notes.size * 2, 0.6, 0.5, 0.35)
            val root = scaleNote(s, degree) - 12
            if (s.drone) tone(t0, barLength, hz(root - 12), 0.22, 1.0, 0.8, 0.5)
            if (bar >= 1) for (st in s.pluckSteps) lead(t0 + st * step + (if (st % 2 == 1) s.swing * step else 0.0), hz(notes[st % notes.size] + (if (st > 7) 24 else 12)), s.pluckLevel, step * 1.5)
            if (s.melody && bar >= 3 && bar % 4 != 3) {
                val rhythm = listOf(listOf(0, 4, 6, 8, 12), listOf(0, 3, 6, 8, 11, 14), listOf(0, 2, 4, 8, 10, 12), listOf(0, 6, 8, 14))[(rnd(bar / 4, 11) * 4).toInt() % 4]
                for (st in rhythm) {
                    val move = listOf(-2, -1, -1, 0, 1, 1, 2)[(rnd(bar, st + 100) * 7).toInt() % 7]
                    tune = max(0, min(9, tune + move))
                    lead(t0 + st * step, hz(penta(tune)), s.pluckLevel * 1.5, step * 2)
                }
            }
            if (bar < s.drumsFromBar) continue
            val lift = if (s.riser) min(1.0, 0.6 + (bar - s.drumsFromBar) / 16.0) else 1.0
            for (st in s.bassSteps) bass(t0 + st * step, root, step * 1.6, 0.3 * lift)
            for (st in s.kick) kick(t0 + st * step, 0.8 * lift)
            for (st in s.snare) snare(t0 + st * step, 0.45 * lift)
            for (st in s.clap) clap(t0 + st * step, 0.5 * lift)
            for (st in s.hat) hat(t0 + st * step + (if (st % 2 == 1) s.swing * step else 0.0), 0.12 * lift)
            for (st in s.openHat) hat(t0 + st * step, 0.1 * lift, true)
        }
        if (s.riser) {
            val start = ((BARS - 2) * barLength * sr).toInt(); val count = (barLength * sr).toInt(); var lp = 0.0
            for (i in 0 until count) if (start + i < buffer.size) { val p = i.toDouble() / count; lp += (0.02 + 0.5 * p) * (noise() - lp); buffer[start + i] += lp * p * p * 0.5 }
        }
        val total = BARS * barLength
        val n = (total * sr).toInt()
        var peak = 0.001; for (i in 0 until n) peak = max(peak, abs(buffer[i]))
        return FloatArray(n) { i -> val fade = min(1.0, (total - i / sr) / 2.5); (buffer[i] / peak * 0.8 * fade).toFloat() }
    }
}
