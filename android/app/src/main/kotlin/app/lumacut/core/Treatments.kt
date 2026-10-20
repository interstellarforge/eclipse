package app.lumacut.core

/** A worked-out creative direction: structure, joins, look, one signature touch. Gives the assistant different, coherent starting points. */
data class Treatment(
    val name: String, val moods: List<String>, val idea: String, val structure: String, val transitions: List<TransitionType>,
    val look: String, val effects: List<Pair<EffectType, Double>>, val overlay: GeneratorKind?, val title: TitlePreset, val speed: String, val restraint: String,
)

object Treatments {
    val all: List<Treatment> get() = TreatmentData.all
    val constraints: List<String> get() = TreatmentData.constraints
    private var recent = listOf<String>()

    fun drawConstraints(count: Int = 2): List<String> = constraints.shuffled().take(count)

    /** Several different treatments, matching the mood words when given, avoiding the ones suggested last time. */
    @Synchronized
    fun suggest(mood: String?, count: Int = 3): List<Treatment> {
        val words = (mood ?: "").lowercase().split(Regex("[^a-z ]+")).flatMap { it.split(" ") }.filter { it.isNotEmpty() }
        val scored = all.map { t -> t to t.moods.count { m -> words.any { m.contains(it) || it.contains(m) } } }
        // Matches come first (fresh ones before repeats), then fresh others; a repeat only shows up when it is the best match.
        val fresh = scored.filter { it.first.name !in recent }; val stale = scored.filter { it.first.name in recent }
        val ordered = fresh.filter { it.second > 0 }.shuffled() + stale.filter { it.second > 0 }.shuffled() + fresh.filter { it.second == 0 }.shuffled() + stale.filter { it.second == 0 }.shuffled()
        val picks = mutableListOf<Treatment>(); val looks = mutableSetOf<String>()
        for ((t, _) in ordered) if (picks.size < count && looks.add(t.look)) picks += t
        for ((t, _) in ordered) if (picks.size < count && picks.none { it.name == t.name }) picks += t
        recent = (recent + picks.map { it.name }).takeLast(8)
        return picks
    }

    fun describe(t: Treatment): String {
        val fx = t.effects.joinToString(", ") { "${it.first.name} ${it.second}" }
        return """
            ${t.name}: ${t.idea}
              structure: ${t.structure}
              joins: ${if (t.transitions.isEmpty()) "hard cuts only" else t.transitions.joinToString(", ") { it.name } + " (mostly hard cuts)"}
              look: ${t.look}; signature effect: ${fx.ifEmpty { "none" }}; overlay: ${t.overlay?.name ?: "none"}; title style: ${t.title.label}
              speed: ${t.speed}
              restraint: ${t.restraint}
        """.trimIndent()
    }
}
