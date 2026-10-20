package app.lumacut.core

/** Offline mode: the assistant never receives pictures, sound or speech of the user's footage. */
object Privacy {
    @Volatile var offline = false

    /** Everything that analyses footage or returns pictures or transcripts of it. */
    val blocked = setOf("inspect_asset", "watch_asset", "watch_timeline", "get_frame", "transcribe_asset", "auto_captions", "find_match_cuts", "smart_reframe")

    val offlinePrompt = """
        OFFLINE MODE IS ON. The user keeps their footage private (it may show children): you must not look at it, listen to it or analyse it, and the tools that would are removed.
        You work only from file names, lengths and what the user tells you. Do not ask to see frames and do not pretend to know what the clips show.
        To find the important parts, call request_selection: it opens a viewer where the user watches their files and marks 'start here' and 'end here' for each part they want; you get the ranges back as text.
        Ask for it once, early, with a short reason (for example 'mark the best moments of each clip'), then build the film from those ranges with build_edit.
        Use ask_user for the mood and length. Choices that need no picture (joins, titles, music, look, pace) work as usual.
    """.trimIndent()
}

enum class ScriptLevel(val label: String, val summary: String) {
    off("Direct", "Builds straight away from your request."),
    medium("Medium", "Looks at the clips, drafts a short script (5 to 8 beats) for you to approve, then builds."),
    advanced("Advanced", "Analyses every clip in depth, drafts a shot-by-shot script with timing, joins, sound and text, revises on your feedback, then builds."),
    director("Director", "Interviews you first, develops a creative direction, drafts the script with an alternative, builds, reviews its own cut and fixes it."),
}

data class ScriptBeat(
    val title: String = "", val detail: String = "", val assetID: Id? = null, val startMs: Long? = null, val endMs: Long? = null,
    val seconds: Double = 3.0, val join: String = "cut", val sound: String = "", val text: String = "",
)

data class ScriptDraft(val title: String, val logline: String, val beats: List<ScriptBeat>, val notes: String = "") {
    /** The script as plain text, with the exact clip ranges, so the assistant builds what was approved. */
    fun render(assetName: (Id) -> String?): String {
        val out = mutableListOf("Script: $title"); if (logline.isNotEmpty()) out += "Idea: $logline"
        beats.forEachIndexed { i, b ->
            var line = "${i + 1}. ${b.title} (${"%.1f".format(java.util.Locale.US, b.seconds)} s)"
            b.assetID?.let { id ->
                line += " clip ${assetName(id) ?: "?"} asset_id=$id"
                if (b.startMs != null && b.endMs != null) line += " source ${b.startMs}-${b.endMs} ms"
            }
            line += " join: ${b.join}"
            if (b.sound.isNotEmpty()) line += "; sound: ${b.sound}"
            if (b.text.isNotEmpty()) line += "; text: \"${b.text}\""
            out += line + if (b.detail.isEmpty()) "" else "\n   ${b.detail}"
        }
        if (notes.isNotEmpty()) out += "Notes: $notes"
        return out.joinToString("\n")
    }
}

object ScriptMode {
    @Volatile var level = ScriptLevel.off
    /** Set when the user approved a script; build_edit needs it in the script modes, and spends it. */
    @Volatile var approved = false

    fun prompt(): String = when (level) {
        ScriptLevel.off -> ""
        ScriptLevel.medium -> "SCRIPT MODE: MEDIUM. For a creative film: first look at the clips (unless offline mode is on), then call propose_script with a short script of 5 to 8 beats (what each beat shows, about how long, the join, a line of text if any). The user reviews and edits it in a window. Build only after the answer starts with APPROVED, and build exactly the approved script. If you get CHANGES REQUESTED, revise and propose again."
        ScriptLevel.advanced -> "SCRIPT MODE: ADVANCED. For a creative film: analyse EVERY clip in depth first (inspect_asset, watch_asset, transcribe_asset when people speak; in offline mode use the ranges the user marked). Write a shot-by-shot script with propose_script: one beat per cut with the exact source range, length, join, sound decision, and any text, plus music and the overall idea in notes. Wait for APPROVED (revise on CHANGES REQUESTED), build exactly the approved script with build_edit, then review it once with watch_timeline (not in offline mode) and fix problems."
        ScriptLevel.director -> "SCRIPT MODE: DIRECTOR. Work like a director on a real project. 1) Interview the user with ask_user, one question at a time (purpose, audience, the feeling, length, references, what must be in it; read the guided-edit skill). 2) Analyse every clip in depth (unless offline). 3) Read creative-thinking and creative-toolbox, call suggest_treatments, develop one concept and keep one alternative in mind. 4) Write the shot-by-shot script with propose_script, and name the alternative in notes so the user can pick it. 5) Wait for APPROVED, build exactly that, 6) review your own cut (watch_timeline, not in offline mode), fix what is weak, and 7) offer one variant."
    }
}

/** Keeps films from all looking alike: build_edit is refused when the plan ignores the creative workflow or overdoes the tricks. */
object CreativeGuard {
    @Volatile var enabled = true
    @Volatile private var treatmentSuggested = false
    @Volatile private var lastSignature = ""

    fun noteTreatmentSuggested() { treatmentSuggested = true }
    fun reset() { treatmentSuggested = false; lastSignature = "" }

    private val camera = setOf("kenBurnsIn", "kenBurnsOut", "panLeft", "panRight", "punchIn")

    /** A message describing what to change, or null when the plan is fine (and it is remembered as the "last film"). */
    @Synchronized
    fun check(cuts: List<Map<String, Any?>>, overlays: List<Map<String, Any?>>): String? {
        if (!enabled) return null
        if (ScriptMode.level != ScriptLevel.off && !ScriptMode.approved)
            return "Script mode (${ScriptMode.level.label}) is on: draft the script with propose_script and wait for the user's APPROVED before build_edit."
        if (!treatmentSuggested)
            return "Before build_edit: read the creative-toolbox skill, call suggest_treatments, choose a direction and tell the user which one and why. Then plan again."
        val effects = mutableSetOf<String>(); val joins = mutableSetOf<String>(); var joinCount = 0; var crossfades = 0; var seconds = 0.0
        for (c in cuts) {
            (c["effects"] as? List<*>)?.forEach { e -> ((e as? Map<*, *>)?.get("type") as? String)?.let { if (it !in camera) effects += it } }
            (c["transition"] as? String)?.let { if (it !in setOf("none", "cut", "")) { joins += it; joinCount++; if (it == "crossfade") crossfades++ } }
            val s = (c["start_ms"] as? Number)?.toDouble() ?: 0.0; val e = (c["end_ms"] as? Number)?.toDouble() ?: 0.0
            seconds += maxOf(0.0, e - s) / 1000
        }
        val problems = mutableListOf<String>()
        if (effects.intersect(setOf("cinemaBars", "grain", "glow")).size >= 2) problems += "cinemaBars, grain and glow together are the default look every film gets. Choose different ingredients from your treatment (or none)."
        if (effects.size > 2) problems += "${effects.size} different effect types (${effects.sorted().joinToString(", ")}): at most 2 besides camera moves. Keep the signature touch and drop the rest."
        if (joins.size > 2) problems += "${joins.size} transition styles (${joins.sorted().joinToString(", ")}): use at most 2, mostly hard cuts."
        if (cuts.size >= 4 && joinCount.toDouble() / cuts.size > 0.5) problems += "Joins on $joinCount of ${cuts.size} cuts: most cuts should be hard cuts (at most about a third get a transition)."
        if (cuts.size >= 4 && crossfades.toDouble() / cuts.size > 0.35) problems += "Crossfades on $crossfades of ${cuts.size} cuts: the plain crossfade is the usual default, use it only where time or place changes."
        if (overlays.size > maxOf(1.0, Math.ceil(seconds / 30))) problems += "${overlays.size} overlays for ${seconds.toInt()} s: at most one per 30 s."
        val signature = effects.sorted().joinToString(",") + "|" + joins.sorted().joinToString(",")
        if (signature != "|" && signature == lastSignature) problems += "Same effects and joins as the previous film in this session ($signature). Pick a different direction with suggest_treatments."
        if (problems.isNotEmpty()) return "build_edit was NOT applied. Revise the plan:\n- " + problems.joinToString("\n- ")
        lastSignature = signature; treatmentSuggested = false; ScriptMode.approved = false
        return null
    }
}
