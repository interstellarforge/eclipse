package app.lumacut

import app.lumacut.core.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

class FakeHost : Host {
    var asked = mutableListOf<List<AskOption>>()
    var answer = "Calm"
    var scriptReply = "APPROVED. Build exactly this script"
    override fun playheadMs() = 0L
    override fun workspaceRoots() = listOf("/media/trip")
    override suspend fun importMedia(uriOrPath: String) = Asset(url = uriOrPath, duration = 8_000, hasVideo = true, hasAudio = true)
    override suspend fun ask(question: String, options: List<AskOption>, allowText: Boolean): String { asked += options; return answer }
    override suspend fun pickRanges(reason: String, assetIds: List<Id>) = "picked"
    override suspend fun reviewScript(draft: ScriptDraft) = scriptReply
    override suspend fun browseFolder(path: String, depth: Int) = "listing of $path"
    override suspend fun contactSheet(asset: Asset, frames: Int, startMs: Ms?, endMs: Ms?) = byteArrayOf(1, 2, 3)
    override suspend fun timelineFrame(project: Project, atMs: Ms) = byteArrayOf(1)
    override suspend fun timelineSheet(project: Project, frames: Int, startMs: Ms?, endMs: Ms?) = byteArrayOf(1)
    override suspend fun export(project: Project, name: String?) = "exported"
    override suspend fun assetInfo(asset: Asset) = "name: ${asset.label}"
}

class ToolsTest {
    private val defs = File("src/main/assets/tools.json").readText()
    private val skillsDir = File("src/main/assets/skills")
    private val skills = Skills(AssetSkillSource { File("src/main/assets/$it").takeIf { f -> f.exists() }?.readText() })
    private val editor = Editor()
    private val host = FakeHost()
    private lateinit var tools: ToolRegistry
    private lateinit var asset: Asset

    @Before fun setUp() {
        Privacy.offline = false; ScriptMode.level = ScriptLevel.off; ScriptMode.approved = false; CreativeGuard.enabled = true; CreativeGuard.reset()
        tools = ToolRegistry({ editor }, host, skills, defs)
        asset = Asset(url = "file:///a.mp4", duration = 20_000, hasVideo = true, hasAudio = true)
        editor.apply(Command.AddAsset(asset))
    }
    @After fun tearDown() { Privacy.offline = false; ScriptMode.level = ScriptLevel.off; CreativeGuard.enabled = true }

    private fun call(name: String, vararg args: Pair<String, JsonElement>) = runBlocking { tools.call(name, JsonObject(args.toMap())) }
    private fun text(r: Pair<List<Content>, Boolean>) = (r.first.first() as Content.Text).text
    private fun s(v: String) = JsonPrimitive(v)
    private fun n(v: Number) = JsonPrimitive(v)
    private fun cuts(vararg effects: String, joins: Boolean = false): JsonArray = JsonArray((0 until 3).map { i ->
        buildJsonObject {
            put("asset_id", asset.id); put("start_ms", i * 3_000); put("end_ms", i * 3_000 + 2_500)
            if (joins && i > 0) put("transition", "crossfade")
            if (effects.isNotEmpty()) put("effects", JsonArray(effects.map { e -> buildJsonObject { put("type", e) } }))
        }
    })

    @Test fun skillsAndDefinitionsLoad() {
        assertEquals(18, skills.all().size)
        assertTrue(skills.get("creative-thinking")!!.body.contains("Name the default first"))
        val names = tools.definitions().map { it["name"]!!.jsonPrimitive.content }
        assertTrue(names.containsAll(listOf("build_edit", "get_project", "suggest_treatments", "ask_user", "propose_script")))
        assertFalse(names.contains("request_selection")); assertFalse(names.contains("auto_movie"))
        assertTrue(tools.definitions().first()["input_schema"] != null)
    }

    @Test fun editingTools() {
        val (c, err) = call("add_clip", "asset_id" to s(asset.id), "duration_ms" to n(4_000)); assertFalse(err)
        val id = editor.project.allClips.first().id
        assertTrue((c.first() as Content.Text).text.contains(id))
        assertFalse(call("set_speed", "clip_id" to s(id), "speed" to n(2)).second)
        assertEquals(2_000L, editor.project.clip(id)!!.duration)
        assertTrue(call("set_speed", "clip_id" to s(id), "speed" to n(99)).second)
        assertFalse(call("add_effect", "clip_id" to s(id), "type" to s("vignette")).second)
        assertEquals(EffectType.vignette, editor.project.clip(id)!!.effects.single().type)
        assertFalse(call("undo").second)
        assertTrue(text(call("get_project")).contains("duration_ms"))
    }

    @Test fun buildEditNeedsATreatmentAndRefusesTheDefaultLook() {
        val first = call("build_edit", "cuts" to cuts())
        assertTrue(first.second); assertTrue(text(first).contains("suggest_treatments"))
        assertFalse(call("suggest_treatments", "mood" to s("calm travel")).second)
        val trio = call("build_edit", "cuts" to cuts("cinemaBars", "grain", "glow"))
        assertTrue(trio.second); assertTrue(text(trio).contains("default look"))
        val ok = call("build_edit", "cuts" to cuts("vignette", joins = false))
        assertFalse(text(ok), ok.second)
        assertEquals(3, editor.project.tracks.flatMap { it.clips }.size)
        assertTrue(text(call("build_edit", "cuts" to cuts("vignette"), "replace" to JsonPrimitive(true))).contains("suggest_treatments"))   // a fresh treatment is needed again
    }

    @Test fun scriptModeBlocksBuildUntilApproved() {
        ScriptMode.level = ScriptLevel.medium
        call("suggest_treatments")
        assertTrue(text(call("build_edit", "cuts" to cuts("vignette"))).contains("propose_script"))
        val beats = JsonArray(listOf(buildJsonObject { put("title", "Hook"); put("seconds", 2) }))
        assertTrue(text(call("propose_script", "title" to s("Day"), "beats" to beats)).startsWith("APPROVED"))
        assertFalse(call("build_edit", "cuts" to cuts("vignette")).second)
    }

    @Test fun offlineHidesAnalysisAndRefusesDirectCalls() {
        Privacy.offline = true
        val names = tools.definitions().map { it["name"]!!.jsonPrimitive.content }
        assertTrue(names.none { it in Privacy.blocked }); assertTrue(names.contains("request_selection")); assertTrue(names.contains("build_edit"))
        val r = call("get_frame"); assertTrue(r.second); assertTrue(text(r).contains("Offline mode"))
        assertEquals("picked", text(call("request_selection", "reason" to s("mark"))))
        Privacy.offline = false
        assertTrue(call("watch_asset", "asset_id" to s(asset.id)).first.first() is Content.Image)
    }

    @Test fun askUserOptionsCarryExplanations() {
        call("ask_user", "question" to s("Mood?"), "options" to JsonArray(listOf(buildJsonObject { put("label", "Calm"); put("info", "Slow and warm") }, s("Fun"))))
        assertEquals(listOf(AskOption("Calm", "Slow and warm"), AskOption("Fun")), host.asked.single())
    }

    @Test fun browseFolderOnlyInsideOpenedFolders() {
        assertTrue(text(call("browse_folder")).contains("/media/trip"))
        assertEquals("listing of /media/trip/day1", text(call("browse_folder", "path" to s("/media/trip/day1"))))
        assertTrue(call("browse_folder", "path" to s("/etc")).second)
        assertTrue(call("browse_folder", "path" to s("/media/trip-other")).second)
    }

    @Test fun treatmentsTemplatesAndCatalog() {
        assertEquals(16, Treatments.all.size); assertEquals(35, Templates.all.size)
        assertTrue(Treatments.all.all { LookPresets.preset(it.look) != null && it.transitions.size <= 2 && it.effects.size <= 2 })
        val a = Treatments.suggest(null, 3); assertEquals(3, a.map { it.look }.toSet().size)
        assertTrue(Treatments.suggest("noir mystery", 3).any { it.name == "Noir" })
        val clipId = editor.addClip(asset, duration = 3_000).id
        editor.addClip(asset, duration = 3_000)
        val note = editor.applyTemplate(Templates.named("Noir")!!)
        assertTrue(note, note.contains("styled 2 clips"))
        assertEquals(0.0, editor.project.clip(clipId)!!.look.saturation, 0.0)
        editor.undo(); assertEquals(1.0, editor.project.clip(clipId)!!.look.saturation, 0.0)
    }

    @Test fun musicLibraryRendersSongsOnTheBeat() {
        assertEquals(47, MusicLibrary.tracks.size); assertTrue(MusicLibrary.categories.containsAll(listOf("Cinematic", "Emotional", "Energetic")))
        val song = MusicLibrary.song("Sunny Day")!!
        val audio = MusicLibrary.render(song)
        assertEquals((24 * 60.0 / song.bpm * 4 * 44_100).toInt(), audio.size)
        assertTrue(audio.maxOf { kotlin.math.abs(it) } in 0.5f..0.85f)
        assertEquals(0f, audio.last(), 0.05f)   // fades out
        val f = MusicLibrary.file("Calm Ambient", java.io.File(System.getProperty("java.io.tmpdir"), "lumacut-music-test")); assertTrue(f.length() > 1_000_000)
        assertTrue(text(call("list_sounds")).contains("Sunny Day (120 BPM"))
    }

    @Test fun promptNamesTheModes() {
        ScriptMode.level = ScriptLevel.director; Privacy.offline = true
        val p = Prompt.system(skills)
        assertTrue(p.contains("OFFLINE MODE IS ON") && p.contains("SCRIPT MODE: DIRECTOR") && p.contains("creative-thinking"))
        Privacy.offline = false; ScriptMode.level = ScriptLevel.off
        assertFalse(Prompt.system(skills).contains("OFFLINE MODE IS ON"))
    }
}
