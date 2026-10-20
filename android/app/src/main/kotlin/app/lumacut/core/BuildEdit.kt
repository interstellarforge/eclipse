package app.lumacut.core

import kotlinx.serialization.json.JsonObject

/** build_edit: a whole directed edit from an edit decision list, in ONE undoable step. */
object BuildEdit {
    private data class Cut(val asset: Asset, val start: Ms, val end: Ms, val args: Args)

    suspend fun apply(a: Args, editor: Editor, host: Host, musicAsset: suspend (String) -> Asset?): String {
        val rawCuts = a.list("cuts")?.takeIf { it.isNotEmpty() } ?: throw ToolError("cuts must be a non-empty list of {asset_id, start_ms, end_ms, ...}")
        val replace = a.optBool("replace") == true
        if (!replace && editor.project.tracks.any { it.clips.isNotEmpty() })
            throw ToolError("The timeline already has clips. Pass replace: true to start over (the user can undo), or change the existing clips with the other tools.")

        val cuts = rawCuts.mapIndexed { i, raw ->
            val c = Args(raw)
            val asset = editor.project.asset(c.optID("asset_id")) ?: throw ToolError("cut $i: unknown asset_id (use the ids from get_project)")
            if (!asset.hasVideo) throw ToolError("cut $i: cuts need a video asset")
            val start = if (asset.isStill) 0 else maxOf(0L, c.optMs("start_ms") ?: 0)
            val end = if (asset.isStill) minOf(asset.duration, c.optMs("duration_ms") ?: 3_000) else minOf(asset.duration, c.optMs("end_ms") ?: asset.duration)
            if (end - start < 200) throw ToolError("cut $i: end_ms must be at least 200 ms after start_ms (the clip is ${asset.duration} ms long)")
            c.optStr("transition")?.let { n -> if (n !in setOf("none", "cut") && TransitionType.entries.none { it.name == n }) throw ToolError("cut $i: unknown transition '$n'. Options: ${TransitionType.entries.joinToString(", ") { it.name }}") }
            (raw["look"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.let { if (LookPresets.preset(it.content) == null) throw ToolError("cut $i: unknown look '${it.content}'. Options: ${LookPresets.names.joinToString(", ")}") }
            c.list("effects")?.forEach { e -> val t = Args(e).optStr("type"); if (EffectType.entries.none { it.name == t }) throw ToolError("cut $i: unknown effect '${t ?: "?"}'. Call list_effects.") }
            Cut(asset, start, end, c)
        }
        val titles = a.list("titles")?.map(::Args) ?: emptyList()
        val overlays = a.list("overlays")?.map(::Args) ?: emptyList()
        overlays.forEach { o -> if (GeneratorKind.entries.none { it.name == o.optStr("kind") }) throw ToolError("unknown overlay '${o.optStr("kind") ?: "?"}'. Call list_overlays.") }
        CreativeGuard.check(rawCuts.map { toMap(it) }, overlays.map { toMap(it.d) })?.let { throw ToolError(it) }

        var music: Pair<Asset, Args>? = null
        a.obj("music")?.let { m ->
            val margs = Args(m)
            val asset = margs.optStr("name")?.let { musicAsset(it) } ?: editor.project.asset(margs.optID("asset_id"))
            music = (asset ?: throw ToolError("music needs a built-in name (see list_sounds) or an asset_id")) to margs
        }

        val summary = mutableListOf<String>()
        editor.transaction {
            if (replace) editor.project.tracks.forEach { editor.apply(Command.RemoveTrack(it.id)) }
            a.optStr("canvas")?.let { canvas ->
                val size = mapOf("16:9" to (1920 to 1080), "9:16" to (1080 to 1920), "1:1" to (1080 to 1080), "4:5" to (1080 to 1350))[canvas] ?: throw ToolError("canvas must be 16:9, 9:16, 1:1 or 4:5")
                editor.apply(Command.SetFormat(size.first, size.second, editor.project.fps))
            }
            val clipIDs = mutableListOf<Id>()
            cuts.forEachIndexed { i, cut ->
                val c = cut.args
                val clip = editor.addClip(cut.asset, start = null, sourceIn = cut.start, duration = cut.end - cut.start)
                c.optDouble("speed")?.let { if (it != 1.0) editor.apply(Command.SetSpeed(clip.id, it)) }
                var volume: Double? = null
                val soundPrim = c.d["sound"]
                val soundStr = c.optStr("sound")
                if (soundStr != null) {
                    if (soundStr == "mute") editor.apply(Command.SetMuted(clip.id, true)) else if (soundStr != "keep") throw ToolError("cut $i: sound must be keep, mute or a number")
                } else if (soundPrim != null && c.optDouble("sound") != null) volume = c.optDouble("sound")
                else if (music != null) volume = 0.3   // music leads unless the cut says otherwise
                val fadeIn = c.optMs("fade_in_ms") ?: 0; val fadeOut = c.optMs("fade_out_ms") ?: 0
                if (volume != null || fadeIn > 0 || fadeOut > 0) {
                    val length = editor.project.clip(clip.id)?.duration ?: clip.duration
                    editor.apply(Command.SetVolume(clip.id, volume ?: 1.0, minOf(fadeIn, length), minOf(fadeOut, maxOf(0L, length - minOf(fadeIn, length)))))
                }
                val lookName = (c.d["look"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
                if (lookName != null) editor.apply(Command.SetLook(clip.id, LookPresets.preset(lookName)!!))
                else c.obj("look")?.let { editor.apply(Command.SetLook(clip.id, Args(it).look(Look()))) }
                if (c.optDouble("scale") != null || c.optDouble("offset_x") != null || c.optDouble("offset_y") != null || c.optDouble("opacity") != null)
                    editor.apply(Command.SetTransform(clip.id, c.optDouble("opacity") ?: 1.0, c.optDouble("scale") ?: 1.0, c.optDouble("offset_x") ?: 0.0, c.optDouble("offset_y") ?: 0.0))
                c.list("keyframes")?.takeIf { it.isNotEmpty() }?.let { f -> editor.apply(Command.SetKeyframes(clip.id, f.map { Args(it).keyframe() })) }
                c.list("effects")?.forEach { e ->
                    val ea = Args(e)
                    val type = EffectType.valueOf(ea.str("type"))
                    editor.apply(Command.AddEffect(clip.id, Effect(type = type, amount = ea.optDouble("amount") ?: type.defaultAmount, colorHex = ea.optStr("color"))))
                }
                clipIDs += clip.id
            }
            cuts.forEachIndexed { i, cut ->
                if (i == 0) return@forEachIndexed
                val type = cut.args.optStr("transition")?.let { n -> TransitionType.entries.firstOrNull { it.name == n } } ?: return@forEachIndexed
                editor.addTransitionAfter(clipIDs[i - 1], type, cut.args.optMs("transition_ms") ?: 500)
            }
            val all = editor.project.allClips
            clipIDs.forEachIndexed { i, id ->
                all.firstOrNull { it.id == id }?.let { c -> summary += "cut $i: clip_id=$id ${c.start}-${c.end} ms (source ${cuts[i].start}-${cuts[i].end}, ${cuts[i].asset.label})" }
            }
            val total = editor.project.duration
            for (t in titles) {
                val preset = t.optStr("preset")?.let(TitlePreset::named) ?: TitlePreset.center
                val clip = editor.addTitle(t.str("text"), maxOf(0L, t.optMs("start_ms") ?: 0), t.optMs("duration_ms") ?: 2_500)
                editor.apply(Command.SetTextStyle(clip.id, t.textStyle(preset.style)))
                val fi = t.optMs("fade_in_ms") ?: 300; val fo = t.optMs("fade_out_ms") ?: 300
                editor.apply(Command.SetVolume(clip.id, 1.0, minOf(fi, clip.duration / 2), minOf(fo, clip.duration / 2)))
            }
            for (o in overlays) {
                val overlay = editor.addOverlay(GeneratorKind.valueOf(o.str("kind")), maxOf(0L, o.optMs("start_ms") ?: 0), o.optMs("duration_ms") ?: 4_000, o.optDouble("amount") ?: 0.5)
                val fi = o.optMs("fade_in_ms") ?: 400; val fo = o.optMs("fade_out_ms") ?: 400
                editor.apply(Command.SetVolume(overlay.id, 1.0, minOf(fi, overlay.duration / 2), minOf(fo, overlay.duration / 2)))
            }
            music?.let { (asset, m) ->
                val start = maxOf(0L, m.optMs("start_ms") ?: 0); val sourceIn = maxOf(0L, m.optMs("source_in_ms") ?: 0)
                val length = maxOf(1L, minOf(asset.duration - sourceIn, total - start))
                val clip = editor.addClip(asset, start = start, sourceIn = sourceIn, duration = length, kind = TrackKind.audio)
                editor.apply(Command.SetVolume(clip.id, m.optDouble("volume") ?: 0.6, minOf(500L, length / 2), minOf(2_500L, length / 2)))
                if (m.optBool("duck") == true) editor.project.trackOf(clip.id)?.let { editor.apply(Command.SetTrackDuck(it.id, true)) }   // the music dips under clip sound
            }
            summary += "total $total ms (${"%.1f".format(java.util.Locale.US, total / 1000.0)} s); ${titles.size} titles" + if (music != null) ", music" else ""
        }
        return "edit built in one undo step:\n" + summary.joinToString("\n") + "\nnext: look at it with watch_timeline and fix what is off."
    }

    private fun toMap(o: JsonObject): Map<String, Any?> = o.mapValues { (_, v) -> conv(v) }
    private fun conv(v: kotlinx.serialization.json.JsonElement): Any? = when (v) {
        is kotlinx.serialization.json.JsonNull -> null
        is kotlinx.serialization.json.JsonPrimitive -> if (v.isString) v.content else (v.booleanOrNull() ?: v.content.toDoubleOrNull())
        is kotlinx.serialization.json.JsonArray -> v.map { conv(it) }
        is JsonObject -> toMap(v)
    }
    private fun kotlinx.serialization.json.JsonPrimitive.booleanOrNull(): Boolean? = if (content == "true") true else if (content == "false") false else null
}
