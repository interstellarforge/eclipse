package app.lumacut.core

import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.roundToLong

/** All times are integer milliseconds. Ids are UUID strings, the same shape as the macOS app's project files. */
typealias Ms = Long
typealias Id = String

fun newId(): Id = UUID.randomUUID().toString().uppercase()

@Serializable
enum class TrackKind { video, audio, text }

@Serializable
data class Asset(
    val id: Id = newId(),
    val url: String,                // content:// or file:// uri
    val duration: Ms,
    val hasVideo: Boolean,
    val hasAudio: Boolean,
    val isStill: Boolean = false,   // a photo: it plays as a clip of fixed length
    val name: String? = null,
    val favorite: Boolean = false,
    val width: Int = 0,
    val height: Int = 0,
) {
    val label: String get() = name ?: url.substringAfterLast('/').substringBefore('?')
}

@Serializable
data class TextStyle(
    val size: Double = 0.08,         // fraction of the video height
    val colorHex: String = "FFFFFF",
    val x: Double = 0.5,             // centre, fraction of width from the left
    val y: Double = 0.15,            // centre, fraction of height from the bottom
    val bold: Boolean = true,
    val shadow: Boolean = true,
    val fontName: String? = null,
    val align: Int = 1,              // 0 left, 1 centre, 2 right
    val outline: Boolean = false,
    val box: Boolean = false,        // dark box behind the text
    val tracking: Double = 0.0,      // letter spacing as a fraction of the size
    val uppercase: Boolean = false,
    val glow: Boolean = false,
    val animation: TextAnimation = TextAnimation.none,
    val animationMs: Ms = 500,
)

@Serializable
data class Look(
    val brightness: Double = 0.0,    // -1...1
    val contrast: Double = 1.0,      // 0...4
    val saturation: Double = 1.0,    // 0...3
    val sepia: Double = 0.0,
    val blur: Double = 0.0,
    val vignette: Double = 0.0,
    val flipX: Boolean = false,
    val flipY: Boolean = false,
    val rotation: Double = 0.0,
    val cropLeft: Double = 0.0,
    val cropRight: Double = 0.0,
    val cropTop: Double = 0.0,
    val cropBottom: Double = 0.0,
    val warmth: Double = 0.0,        // -1 cool ... +1 warm
    val fade: Double = 0.0,
    val sharpen: Double = 0.0,
    val splitShadows: String? = null,
    val splitHighlights: String? = null,
    val splitAmount: Double = 0.0,
) {
    /** Colour part of a preset: the geometry of `this` is kept. */
    fun withColourOf(preset: Look) = preset.copy(flipX = flipX, flipY = flipY, rotation = rotation, cropLeft = cropLeft, cropRight = cropRight, cropTop = cropTop, cropBottom = cropBottom)
}

@Serializable
data class Effect(
    val id: Id = newId(),
    val type: EffectType,
    val amount: Double = type.defaultAmount,
    val colorHex: String? = null,
)

@Serializable
data class RampPoint(val position: Double, val speed: Double)

object SpeedRamp {
    private fun p(vararg v: Pair<Double, Double>) = v.map { RampPoint(it.first, it.second) }

    val presets: List<Pair<String, List<RampPoint>>> = listOf(
        "Slow-mo dip" to p(0.0 to 1.0, 0.35 to 1.0, 0.5 to 0.3, 0.65 to 1.0, 1.0 to 1.0),
        "Hero pause" to p(0.0 to 1.0, 0.4 to 0.2, 0.6 to 0.2, 1.0 to 1.0),
        "Ramp up" to p(0.0 to 0.5, 1.0 to 2.5),
        "Ramp down" to p(0.0 to 2.5, 1.0 to 0.5),
        "Speed burst" to p(0.0 to 1.0, 0.4 to 1.0, 0.5 to 3.0, 0.6 to 1.0, 1.0 to 1.0),
        "Slow ending" to p(0.0 to 1.0, 0.7 to 1.0, 1.0 to 0.4),
        "Slow start" to p(0.0 to 0.4, 0.3 to 1.0, 1.0 to 1.0),
        "Pulse" to p(0.0 to 1.0, 0.25 to 0.4, 0.5 to 1.0, 0.75 to 0.4, 1.0 to 1.0),
    )

    fun preset(name: String): List<RampPoint>? {
        fun key(s: String) = s.lowercase().filter { it.isLetter() }
        return presets.firstOrNull { key(it.first) == key(name) }?.second
    }

    /** Speed at `u` (0...1): glides between the points in the ratio of the speeds, so 0.5 to 2 feels even. */
    fun speed(u: Double, points: List<RampPoint>): Double {
        val first = points.firstOrNull() ?: return 1.0
        val last = points.last()
        if (u <= first.position) return first.speed
        if (u >= last.position) return last.speed
        for (i in 0 until points.size - 1) if (u <= points[i + 1].position) {
            val a = points[i]; val b = points[i + 1]
            val f = (u - a.position) / maxOf(1e-9, b.position - a.position)
            val eased = f * f * (3 - 2 * f)
            return exp(ln(a.speed) + (ln(b.speed) - ln(a.speed)) * eased)
        }
        return last.speed
    }
}

@Serializable
data class Keyframe(
    val time: Ms,                    // from the start of the clip
    val opacity: Double = 1.0,
    val scale: Double = 1.0,
    val offsetX: Double = 0.0,
    val offsetY: Double = 0.0,
    val rotation: Double = 0.0,
    val smooth: Boolean = true,
) {
    companion object {
        /** The animated picture state at `time`: values glide between keyframes and hold before the first and after the last. */
        fun interpolate(frames: List<Keyframe>, time: Double): Keyframe? {
            val first = frames.firstOrNull() ?: return null
            val last = frames.last()
            if (time <= first.time) return first
            if (time >= last.time) return last
            for (i in 0 until frames.size - 1) if (time < frames[i + 1].time) {
                val a = frames[i]; val b = frames[i + 1]
                var u = (time - a.time) / maxOf(1L, b.time - a.time).toDouble()
                if (b.smooth) u = u * u * (3 - 2 * u)
                fun mix(x: Double, y: Double) = x + (y - x) * u
                return Keyframe(time.toLong(), mix(a.opacity, b.opacity), mix(a.scale, b.scale), mix(a.offsetX, b.offsetX), mix(a.offsetY, b.offsetY), mix(a.rotation, b.rotation))
            }
            return last
        }
    }
}

@Serializable
data class Clip(
    val id: Id = newId(),
    val assetID: Id? = null,         // null for text and overlay clips
    val text: String? = null,
    val sourceIn: Ms = 0,            // offset into the asset
    val duration: Ms,
    val start: Ms,                   // position on the timeline
    val volume: Double = 1.0,
    val fadeIn: Ms = 0,
    val fadeOut: Ms = 0,
    val muted: Boolean = false,
    val opacity: Double = 1.0,
    val scale: Double = 1.0,
    val offsetX: Double = 0.0,
    val offsetY: Double = 0.0,
    val style: TextStyle = TextStyle(),
    val speed: Double = 1.0,         // 2 = plays twice as fast; `duration` is the time on the timeline
    val look: Look = Look(),
    val effects: List<Effect> = emptyList(),
    val groupID: Id? = null,
    val keyframes: List<Keyframe> = emptyList(),
    val generator: GeneratorKind? = null,
    val generatorAmount: Double = 0.5,
) {
    val end: Ms get() = start + duration
    /** Length of the source material the clip uses. */
    val sourceLength: Ms get() = (duration * speed).roundToLong()
}

@Serializable
data class Track(
    val id: Id = newId(),
    val kind: TrackKind,
    val clips: List<Clip> = emptyList(),
    val muted: Boolean = false,
    val hidden: Boolean = false,
    val locked: Boolean = false,
    val duck: Boolean = false,
    val duckLevel: Double = 0.3,
    val name: String? = null,
)

@Serializable
data class Transition(
    val id: Id = newId(),
    val fromClip: Id,
    val toClip: Id,
    val type: TransitionType,
    val duration: Ms,
)

@Serializable
data class Project(
    val assets: List<Asset> = emptyList(),
    val tracks: List<Track> = emptyList(),
    val transitions: List<Transition> = emptyList(),
    val width: Int = 1920,
    val height: Int = 1080,
    val fps: Int = 30,
) {
    val duration: Ms get() = tracks.flatMap { it.clips }.maxOfOrNull { it.end } ?: 0

    fun asset(id: Id?): Asset? = assets.firstOrNull { it.id == id }
    fun clip(id: Id): Clip? = tracks.firstNotNullOfOrNull { t -> t.clips.firstOrNull { it.id == id } }
    fun track(id: Id): Track? = tracks.firstOrNull { it.id == id }
    fun trackOf(clipID: Id): Track? = tracks.firstOrNull { t -> t.clips.any { it.id == clipID } }
    val allClips: List<Clip> get() = tracks.flatMap { it.clips }
}
