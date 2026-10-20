package app.lumacut.core

import kotlinx.serialization.json.*
import java.util.Base64

/** All tools the assistant can call, with the same names and arguments as the macOS app's MCP server. */
class ToolRegistry(
    private val editorProvider: () -> Editor,
    private val host: Host,
    private val skills: Skills,
    definitionsJson: String,
    /** Built-in music bed by name, as an imported asset (null when the app has none). */
    private val musicAsset: suspend (String) -> Asset? = { null },
) {
    private val editor get() = editorProvider()
    private val allDefinitions: List<JsonObject> = Json.parseToJsonElement(definitionsJson).jsonArray.map { it.jsonObject }
    private val handlers = mutableMapOf<String, suspend (Args) -> List<Content>>()

    private fun text(s: String) = listOf<Content>(Content.Text(s))
    private fun image(bytes: ByteArray?, fallback: String): List<Content> =
        if (bytes == null) text(fallback) else listOf(Content.Image("image/jpeg", Base64.getEncoder().encodeToString(bytes)))
    private fun h(name: String, f: suspend (Args) -> List<Content>) { handlers[name] = f }
    private fun clip(id: Id): Clip = editor.project.clip(id) ?: throw ToolError("clip not found")
    private fun describe(c: Clip) = "clip_id=${c.id} start_ms=${c.start} duration_ms=${c.duration}"
    private fun transitionType(n: String) = TransitionType.entries.firstOrNull { it.name == n }
        ?: throw ToolError("unknown transition type; use one of: ${TransitionType.entries.joinToString(", ") { it.name }}")

    /** Tools that exist in this app, minus the ones offline mode hides; shaped for the Claude API. */
    fun definitions(): List<JsonObject> = allDefinitions.filter { d ->
        val name = d["name"]!!.jsonPrimitive.content
        name in handlers && (if (Privacy.offline) name !in Privacy.blocked else name != "request_selection")
    }.map { d ->
        buildJsonObject {
            put("name", d["name"]!!); put("description", d["description"]!!)
            put("input_schema", d["inputSchema"] ?: buildJsonObject { put("type", "object") })
        }
    }

    val implemented: Set<String> get() = handlers.keys

    suspend fun call(name: String, args: JsonObject): Pair<List<Content>, Boolean> {
        if (Privacy.offline && name in Privacy.blocked)
            return text("Offline mode is on: $name is disabled so the footage stays private. Use request_selection to let the user mark the important parts.") to true
        val handler = handlers[name] ?: return text("unknown tool '$name'") to true
        return try { handler(Args(args)) to false } catch (e: ToolError) { text(e.message ?: "error") to true } catch (e: EditError) { text(e.message ?: "error") to true }
    }

    init {
        h("ask_user") { a ->
            val options = (a.d["options"] as? JsonArray)?.mapNotNull { el ->
                when (el) {
                    is JsonPrimitive -> if (el.isString) AskOption(el.content) else null
                    is JsonObject -> el["label"]?.jsonPrimitive?.contentOrNull?.let { AskOption(it, el["info"]?.jsonPrimitive?.contentOrNull ?: el["description"]?.jsonPrimitive?.contentOrNull ?: "") }
                    else -> null
                }
            } ?: emptyList()
            text("The user answered: " + host.ask(a.str("question"), options, a.optBool("allow_text") ?: true))
        }
        h("request_selection") { a -> text(host.pickRanges(a.optStr("reason") ?: "Mark the parts that matter", a.strings("asset_ids") ?: emptyList())) }
        h("browse_folder") { a ->
            val roots = host.workspaceRoots()
            val path = a.optStr("path") ?: return@h text(if (roots.isEmpty()) "No folders are open. Ask the user to open one with the Files tab (Open folder…)." else "Opened folders:\n" + roots.joinToString("\n") { "- $it" })
            if (roots.none { path == it || path.startsWith(it.trimEnd('/') + "/") }) throw ToolError("That folder is not open in the Files tab. Opened folders: ${roots.joinToString(", ")}")
            text(host.browseFolder(path, (a.optInt("depth") ?: 1).coerceIn(1, 3)))
        }
        h("propose_script") { a ->
            val beats = (a.list("beats") ?: emptyList()).map { raw ->
                val b = Args(raw)
                ScriptBeat(b.optStr("title") ?: "", b.optStr("detail") ?: "", b.optID("asset_id"), b.optMs("start_ms"), b.optMs("end_ms"), b.optDouble("seconds") ?: 3.0, b.optStr("join") ?: "cut", b.optStr("sound") ?: "", b.optStr("text") ?: "")
            }
            if (beats.isEmpty()) throw ToolError("beats must not be empty")
            val reply = host.reviewScript(ScriptDraft(a.str("title"), a.optStr("logline") ?: "", beats, a.optStr("notes") ?: ""))
            if (reply.startsWith("APPROVED")) ScriptMode.approved = true
            text(reply)
        }
        h("list_skills") { text(skills.all().joinToString("\n") { "${it.name}: ${it.summary}" }) }
        h("get_skill") { a -> text(skills.get(a.str("name"))?.body ?: throw ToolError("unknown skill; call list_skills")) }
        h("set_format") { a ->
            var w = editor.project.width; var hgt = editor.project.height
            when (a.optStr("preset")) { "16:9" -> { w = 1920; hgt = 1080 }; "9:16" -> { w = 1080; hgt = 1920 }; "1:1" -> { w = 1080; hgt = 1080 }; "4:5" -> { w = 1080; hgt = 1350 } }
            editor.apply(Command.SetFormat(a.optInt("width") ?: w, a.optInt("height") ?: hgt, a.optInt("fps") ?: editor.project.fps))
            text("canvas ${editor.project.width}x${editor.project.height} at ${editor.project.fps} fps")
        }
        h("get_project") {
            val obj = ProjectIO.json.encodeToJsonElement(Project.serializer(), editor.project).jsonObject
            text(JsonObject(obj + mapOf("duration_ms" to JsonPrimitive(editor.project.duration), "playhead_ms" to JsonPrimitive(host.playheadMs()))).toString())
        }
        h("import_media") { a ->
            val asset = host.importMedia(a.str("path"))
            text("asset_id=${asset.id} duration_ms=${asset.duration} video=${asset.hasVideo} audio=${asset.hasAudio}")
        }
        h("add_clip") { a ->
            val asset = editor.project.asset(a.id("asset_id")) ?: throw ToolError("asset not found")
            text(describe(editor.addClip(asset, a.optMs("start_ms"), a.optMs("source_in_ms") ?: 0, a.optMs("duration_ms"), a.optID("track_id"))))
        }
        h("add_title") { a ->
            val c = editor.addTitle(a.str("text"), a.optMs("start_ms") ?: host.playheadMs(), a.optMs("duration_ms") ?: 3_000)
            a.optStr("preset")?.let { n -> editor.apply(Command.SetTextStyle(c.id, (TitlePreset.named(n) ?: throw ToolError("unknown title style")).style)) }
            text(describe(c))
        }
        h("set_title_text") { a -> editor.apply(Command.SetText(a.id("clip_id"), a.str("text"))); text("ok") }
        h("move_clip") { a -> editor.apply(Command.MoveClip(a.id("clip_id"), a.ms("start_ms"))); text("ok") }
        h("trim_clip") { a ->
            val c = clip(a.id("clip_id"))
            editor.apply(Command.TrimClip(c.id, a.optMs("source_in_ms") ?: c.sourceIn, a.optMs("duration_ms") ?: c.duration, a.optMs("start_ms") ?: c.start)); text("ok")
        }
        h("split_clip") { a -> editor.apply(Command.SplitClip(a.id("clip_id"), a.ms("at_ms"))); text("ok") }
        h("remove_clip") { a -> val id = a.id("clip_id"); editor.apply(if (a.optBool("ripple") == true) Command.RippleRemove(id) else Command.RemoveClip(id)); text("ok") }
        h("duplicate_clip") { a -> text(describe(editor.duplicate(a.id("clip_id")))) }
        h("remove_asset") { a -> editor.apply(Command.RemoveAsset(a.id("asset_id"))); text("ok") }
        h("set_speed") { a -> editor.apply(Command.SetSpeed(a.id("clip_id"), a.optDouble("speed") ?: throw ToolError("missing number argument 'speed'"))); text("ok") }
        h("set_look") { a -> editor.apply(Command.SetLook(a.id("clip_id"), a.look(clip(a.id("clip_id")).look))); text("ok") }
        h("set_track") { a ->
            val id = a.id("track_id"); val t = editor.project.track(id) ?: throw ToolError("track not found")
            editor.transaction {
                editor.apply(Command.SetTrackFlags(id, a.optBool("muted") ?: t.muted, a.optBool("hidden") ?: t.hidden))
                a.optBool("duck")?.let { editor.apply(Command.SetTrackDuck(id, it)) }
                a.optDouble("duck_level")?.let { editor.apply(Command.SetTrackDuckLevel(id, it)) }
                a.optStr("name")?.let { editor.apply(Command.SetTrackName(id, it)) }
                a.optBool("locked")?.let { editor.apply(Command.SetTrackLocked(id, it)) }
            }
            text("ok")
        }
        h("add_transition") { a -> editor.addTransitionAfter(a.id("clip_id"), transitionType(a.str("type")), a.optMs("duration_ms")); text("ok") }
        h("remove_transition") { a -> editor.removeTransitionInvolving(a.id("clip_id")); text("ok") }
        h("update_transition") { a ->
            val id = a.id("clip_id"); val tr = editor.project.transitions.firstOrNull { it.fromClip == id || it.toClip == id } ?: throw ToolError("clip has no transition")
            editor.apply(Command.SetTransition(tr.id, a.optStr("type")?.let(::transitionType) ?: tr.type, a.optMs("duration_ms") ?: tr.duration)); text("ok")
        }
        h("set_audio") { a ->
            val c = clip(a.id("clip_id"))
            editor.apply(Command.SetVolume(c.id, a.optDouble("volume") ?: c.volume, a.optMs("fade_in_ms") ?: c.fadeIn, a.optMs("fade_out_ms") ?: c.fadeOut)); text("ok")
        }
        h("set_transform") { a ->
            val c = clip(a.id("clip_id"))
            editor.apply(Command.SetTransform(c.id, a.optDouble("opacity") ?: c.opacity, a.optDouble("scale") ?: c.scale, a.optDouble("offset_x") ?: c.offsetX, a.optDouble("offset_y") ?: c.offsetY)); text("ok")
        }
        h("set_text_style") { a -> editor.apply(Command.SetTextStyle(a.id("clip_id"), a.textStyle(clip(a.id("clip_id")).style))); text("ok") }
        h("detach_audio") { a -> editor.detachAudio(a.id("clip_id")); text("ok") }
        h("add_track") { a ->
            val kind = TrackKind.entries.firstOrNull { it.name == a.str("kind") } ?: throw ToolError("kind must be video, audio or text")
            text("track_id=${editor.addTrack(kind, a.optBool("on_top") ?: false)}")
        }
        h("remove_track") { a -> editor.apply(Command.RemoveTrack(a.id("track_id"))); text("ok") }
        h("list_effects") { text(EffectType.entries.joinToString("\n") { "${it.name} (${it.title}): ${it.summary}" }) }
        h("add_effect") { a ->
            val type = EffectType.entries.firstOrNull { it.name == a.str("type") } ?: throw ToolError("unknown effect; call list_effects")
            editor.apply(Command.AddEffect(a.id("clip_id"), Effect(type = type, amount = a.optDouble("amount") ?: type.defaultAmount, colorHex = a.optStr("color")))); text("ok")
        }
        h("remove_effect") { a ->
            val c = clip(a.id("clip_id")); val e = c.effects.firstOrNull { it.type.name == a.str("type") } ?: throw ToolError("clip has no such effect")
            editor.apply(Command.RemoveEffect(c.id, e.id)); text("ok")
        }
        h("list_sounds") {
            text("music beds, ${MusicLibrary.tracks.size} songs by category (made by the app, free to use; sound effects are not built in on Android):\n" +
                MusicLibrary.categories.joinToString("\n") { c -> "$c: " + MusicLibrary.tracks.filter { it.category == c }.joinToString("; ") { "${it.name} (${it.bpm.toInt()} BPM, ${it.mood})" } })
        }
        h("add_music") { a ->
            val name = a.str("name")
            val asset = musicAsset(name) ?: throw ToolError("unknown song; call list_sounds")
            val clip = editor.addMusicBed(asset, a.optMs("start_ms") ?: 0, a.optMs("duration_ms"))
            text(describe(clip) + " bpm=${MusicLibrary.song(name)?.bpm?.toInt()}")
        }
        h("build_edit") { a -> text(BuildEdit.apply(a, editor, host, musicAsset)) }
        h("group_clips") { a -> val ids = a.strings("clip_ids") ?: emptyList(); if (ids.size < 2) throw ToolError("clip_ids needs at least two clip ids"); editor.apply(Command.Group(ids)); text("ok") }
        h("ungroup_clip") { a -> editor.apply(Command.Ungroup(a.id("clip_id"))); text("ok") }
        h("set_keyframes") { a -> editor.apply(Command.SetKeyframes(a.id("clip_id"), (a.list("keyframes") ?: throw ToolError("keyframes must be a list")).map { Args(it).keyframe() })); text("ok") }
        h("add_sticker") { a -> text(describe(editor.addSticker(a.str("emoji"), a.optMs("start_ms") ?: host.playheadMs(), a.optMs("duration_ms") ?: 2_500))) }
        h("reset_clip") { a -> editor.resetClip(a.id("clip_id")); text("ok") }
        h("asset_info") { a ->
            val asset = editor.project.asset(a.id("asset_id")) ?: throw ToolError("asset not found")
            text(host.assetInfo(asset) + "\nused in ${editor.project.allClips.count { it.assetID == asset.id }} clips")
        }
        h("list_overlays") { text(GeneratorKind.entries.joinToString("\n") { "${it.name} (${it.title}): ${it.summary}" }) }
        h("add_overlay") { a ->
            val kind = GeneratorKind.entries.firstOrNull { it.name == a.str("kind") } ?: throw ToolError("unknown overlay; call list_overlays")
            text(describe(editor.addOverlay(kind, a.optMs("start_ms") ?: host.playheadMs(), a.optMs("duration_ms") ?: 4_000, a.optDouble("amount") ?: 0.5)))
        }
        h("suggest_treatments") { a ->
            CreativeGuard.noteTreatmentSuggested()
            val picks = Treatments.suggest(a.optStr("mood"), (a.optInt("count") ?: 3).coerceIn(2, 5))
            text(picks.joinToString("\n\n") { Treatments.describe(it) } + "\n\nConstraint cards (obey at least one, it keeps the film from being the usual):\n- " +
                Treatments.drawConstraints().joinToString("\n- ") + "\n\nBefore choosing, read the creative-thinking skill: name the obvious default film for this request, then move away from it.")
        }
        h("list_templates") {
            text(Templates.categories.joinToString("\n") { c -> "$c:\n" + Templates.all.filter { it.category == c }.joinToString("\n") { "  - ${it.name}: ${it.summary} Pace: ${it.pace}." + (it.music?.let { m -> " Music: $m." } ?: "") } })
        }
        h("apply_template") { a ->
            val template = Templates.named(a.str("name")) ?: throw ToolError("unknown template; call list_templates")
            val options = TemplateOptions(a.optBool("transitions") ?: true, a.optBool("titles") ?: true, a.optBool("overlay") ?: true)
            var summary = editor.applyTemplate(template, a.strings("clip_ids"), options)
            if (a.optBool("music") == true) template.music?.let { bed -> musicAsset(bed)?.let { editor.addMusicBed(it, 0); summary += "; music $bed added" } }
            text(summary)
        }
        h("ramp_speed") { a ->
            val points = a.optStr("preset")?.let { SpeedRamp.preset(it) ?: throw ToolError("unknown preset; use one of: ${SpeedRamp.presets.joinToString(", ") { p -> p.first }}") }
                ?: a.list("points")?.map { Args(it).let { p -> RampPoint(p.optDouble("position") ?: 0.0, p.optDouble("speed") ?: 1.0) } } ?: throw ToolError("give a preset or points")
            editor.apply(Command.RampSpeed(a.id("clip_id"), points, a.optInt("segments") ?: 20)); text("ok")
        }
        h("undo") { if (!editor.canUndo) throw ToolError("nothing to undo"); editor.undo(); text("ok") }
        h("redo") { if (!editor.canRedo) throw ToolError("nothing to redo"); editor.redo(); text("ok") }
        h("inspect_asset") { a ->
            val asset = editor.project.asset(a.id("asset_id")) ?: throw ToolError("asset not found")
            image(host.contactSheet(asset, (a.optInt("frames") ?: 12).coerceIn(4, 24), null, null), "could not read frames")
        }
        h("watch_asset") { a ->
            val asset = editor.project.asset(a.id("asset_id")) ?: throw ToolError("asset not found")
            image(host.contactSheet(asset, (a.optInt("frames") ?: 12).coerceIn(4, 24), a.optMs("start_ms"), a.optMs("end_ms")), "could not read frames")
        }
        h("watch_timeline") { a -> image(host.timelineSheet(editor.project, (a.optInt("frames") ?: 12).coerceIn(4, 24), a.optMs("start_ms"), a.optMs("end_ms")), "the timeline is empty") }
        h("get_frame") { a -> image(host.timelineFrame(editor.project, a.optMs("time_ms") ?: host.playheadMs()), "no picture at that time") }
        h("export") { a -> text(host.export(editor.project, a.optStr("path"))) }
    }
}
