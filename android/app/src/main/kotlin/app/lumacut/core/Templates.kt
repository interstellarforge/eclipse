package app.lumacut.core

/** A complete film style: colour grade, effects, joins, title look, overlay and a music suggestion. */
data class EditTemplate(
    val id: String, val name: String, val category: String, val summary: String, val look: Look,
    val effects: List<Effect>, val transition: TransitionType?, val transitionMs: Ms,
    val titleStyle: TitlePreset?, val overlay: GeneratorKind?, val overlayAmount: Double, val music: String?, val pace: String,
)

object Templates {
    val all: List<EditTemplate> get() = TemplateData.all
    val categories: List<String> get() = all.map { it.category }.distinct()
    fun named(name: String): EditTemplate? { val key = name.lowercase().filter { it.isLetterOrDigit() }; return all.firstOrNull { it.id == key } }
}

data class TemplateOptions(val transitions: Boolean = true, val titles: Boolean = true, val overlay: Boolean = true)

/** Applies a template to the given clips (all video clips when null) in one undo step; returns what changed in plain words. */
fun Editor.applyTemplate(template: EditTemplate, clipIDs: List<Id>? = null, options: TemplateOptions = TemplateOptions()): String {
    val notes = mutableListOf<String>()
    transaction {
        val videoClips = project.tracks.filter { it.kind == TrackKind.video }.flatMap { it.clips }.filter { it.assetID != null && (clipIDs?.contains(it.id) ?: true) }
        if (videoClips.isEmpty()) throw EditError("There are no video clips to style.")
        for (clip in videoClips) {
            apply(Command.SetLook(clip.id, clip.look.withColourOf(template.look)))   // framing stays
            clip.effects.forEach { apply(Command.RemoveEffect(clip.id, it.id)) }
            template.effects.forEach { apply(Command.AddEffect(clip.id, Effect(type = it.type, amount = it.amount, colorHex = it.colorHex))) }
        }
        notes += "styled ${videoClips.size} clips with the ${template.name} look" + if (template.effects.isEmpty()) "" else " and effects"
        val type = template.transition
        if (options.transitions && type != null) {
            var changed = 0; val ids = videoClips.map { it.id }.toSet()
            for (track in project.tracks.filter { it.kind == TrackKind.video }) {
                val sorted = track.clips.filter { it.assetID != null }.sortedBy { it.start }
                for ((a, b) in sorted.zipWithNext()) if (a.id in ids && b.id in ids) {
                    val existing = project.transitions.firstOrNull { it.fromClip == a.id && it.toClip == b.id }
                    if (existing != null) { apply(Command.SetTransition(existing.id, type, maxOf(1L, a.end - b.start))); changed++ }   // keeps the overlap, changes the style
                    else if (a.end == b.start) { addTransitionAfter(a.id, type, template.transitionMs); changed++ }
                }
            }
            if (changed > 0) notes += "$changed joins now use ${type.title.lowercase()}"
        }
        val titleStyle = template.titleStyle
        if (options.titles && titleStyle != null) {
            var count = 0
            for (track in project.tracks.filter { it.kind == TrackKind.text && it.name != "Captions" }) for (clip in track.clips.filter { it.text != null }) {
                apply(Command.SetTextStyle(clip.id, titleStyle.style.copy(x = clip.style.x, y = clip.style.y))); count++   // the title stays where you put it
            }
            if (count > 0) notes += "$count titles restyled"
        }
        val kind = template.overlay
        if (options.overlay && kind != null && project.duration > 0) {
            val overlay = addOverlay(kind, 0, project.duration, template.overlayAmount)
            apply(Command.SetVolume(overlay.id, 1.0, minOf(800L, overlay.duration / 3), minOf(800L, overlay.duration / 3)))
            notes += "${kind.title.lowercase()} overlay added"
        }
    }
    return notes.joinToString("; ")
}
