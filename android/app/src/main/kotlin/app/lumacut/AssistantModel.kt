package app.lumacut

import android.net.Uri
import android.view.SurfaceView
import androidx.compose.runtime.*
import androidx.media3.common.util.UnstableApi
import app.lumacut.ai.*
import app.lumacut.core.*
import app.lumacut.media.FrameTools
import app.lumacut.media.MediaProbe
import kotlinx.coroutines.*
import androidx.lifecycle.viewModelScope
import kotlinx.serialization.json.*
import java.io.File

class UiMessage(val role: Role, text: String, val toolName: String? = null) {
    enum class Role { User, Assistant, Tool, Notice }
    var text by mutableStateOf(text)
    var done by mutableStateOf(role != Role.Tool)
    var failed by mutableStateOf(false)
}

class PendingQuestion(val question: String, val options: List<AskOption>, val allowText: Boolean, val answer: CompletableDeferred<String>)
class PendingSelection(val reason: String, val assetIds: List<Id>, val answer: CompletableDeferred<String>)
class PendingScript(val draft: ScriptDraft, val answer: CompletableDeferred<String>)

val MODELS = listOf("claude-sonnet-5-5" to "Sonnet 5.5", "claude-opus-5-5" to "Opus 5.5", "claude-haiku-5-5" to "Haiku 5.5", "claude-fable-5-1" to "Fable 5.1")

/** The in-app assistant: chat state, the Claude API loop, the tools, and the dialogs the assistant can open (questions, range picker, script review). */
@UnstableApi
class AssistantModel(private val vm: EditorViewModel) {
    private val ctx get() = vm.getApplication<android.app.Application>()
    private val prefs get() = vm.prefs
    private val scope get() = vm.scope
    val messages = mutableStateListOf<UiMessage>()
    var running by mutableStateOf(false); private set
    var draft by mutableStateOf("")
    val queue = mutableStateListOf<String>()
    var question by mutableStateOf<PendingQuestion?>(null)
    var selectionRequest by mutableStateOf<PendingSelection?>(null)
    var scriptReview by mutableStateOf<PendingScript?>(null)
    private val history = mutableListOf<JsonObject>()
    private var job: Job? = null
    private var nextUp: String? = null
    private var sessionStartedOffline = false
    private var chatId = java.util.UUID.randomUUID().toString()

    var apiKey by mutableStateOf(prefs.getString("apiKey", "") ?: ""); private set
    var model by mutableStateOf(prefs.getString("model", MODELS[0].first) ?: MODELS[0].first); private set
    var offline by mutableStateOf(prefs.getBoolean("offline", false)); private set
    var scriptLevel by mutableStateOf(runCatching { ScriptLevel.valueOf(prefs.getString("scriptLevel", "off")!!) }.getOrDefault(ScriptLevel.off)); private set

    val workspace = Workspace(ctx)
    var roots by mutableStateOf(workspace.roots); private set

    private val skills = Skills(AssetSkillSource { path -> runCatching { ctx.assets.open(path).bufferedReader().readText() }.getOrNull() })
    private val registry: ToolRegistry

    init {
        Privacy.offline = offline; ScriptMode.level = scriptLevel
        registry = ToolRegistry({ vm.editor }, AndroidHost(), skills, ctx.assets.open("tools.json").bufferedReader().readText(), musicAsset = { name -> vm.musicAsset(name) })
    }

    fun updateApiKey(k: String) { apiKey = k.trim(); prefs.edit().putString("apiKey", apiKey).apply() }
    fun updateModel(m: String) { model = m; prefs.edit().putString("model", m).apply() }
    fun updateOffline(on: Boolean) { offline = on; Privacy.offline = on; prefs.edit().putBoolean("offline", on).apply() }
    fun updateScriptLevel(l: ScriptLevel) { scriptLevel = l; ScriptMode.level = l; ScriptMode.approved = false; prefs.edit().putString("scriptLevel", l.name).apply() }
    fun addRoot(uri: Uri) { workspace.add(uri); roots = workspace.roots }
    fun removeRoot(r: Workspace.Root) { workspace.remove(r); roots = workspace.roots }

    fun mention(ref: String) { draft = if (draft.isEmpty()) "$ref " else draft + (if (draft.endsWith(" ")) "" else " ") + "$ref " }

    // ---------- Chat ----------

    fun newChat() { cancelRun(); messages.clear(); history.clear(); queue.clear(); chatId = java.util.UUID.randomUUID().toString(); sessionStartedOffline = false }

    fun send(text: String = draft, shown: String? = null) {
        val t = text.trim(); if (t.isEmpty()) return
        if (text == draft) draft = ""
        if (running) { queue.add(t); return }
        if (apiKey.isEmpty()) { messages += UiMessage(UiMessage.Role.Notice, "Add your Claude API key in Settings (the gear in the Assistant) to chat.").also { it.failed = true }; return }
        // A session that already saw footage keeps it in its memory: when offline mode is on, start a clean one.
        if (offline && history.isNotEmpty() && !sessionStartedOffline) {
            history.clear()
            messages += UiMessage(UiMessage.Role.Notice, "Offline mode: started a fresh Claude session, so nothing it saw of your clips earlier is carried over. Claude now only knows what you tell it and the parts you mark.")
        }
        if (history.isEmpty()) sessionStartedOffline = offline else if (!offline) sessionStartedOffline = false
        messages += UiMessage(UiMessage.Role.User, shown ?: t)
        running = true
        val sel = vm.selectedClip?.let { "selected clip ${it.id}" } ?: "nothing selected"
        val counts = "${vm.project.assets.size} imported files, ${vm.project.allClips.size} clips on the timeline, movie length ${vm.project.duration} ms"
        val content = "$t\n\n[Editor state: playhead at ${vm.playheadMs} ms; $sel; $counts.]"
        history += buildJsonObject { put("role", "user"); put("content", JsonArray(listOf(buildJsonObject { put("type", "text"); put("text", content) }))) }
        var current: UiMessage? = null
        val toolRows = mutableMapOf<String, UiMessage>()
        job = scope.launch {
            val client = ClaudeClient({ apiKey }, { model })
            try {
                client.run(history, system = { Prompt.system(skills, "\nYou run on an Android phone or tablet; times are milliseconds and the same tools apply.\n") },
                    tools = { registry.definitions() }, runTool = { name, input -> withContext(Dispatchers.Main.immediate) { registry.call(name, input) } }) { e ->
                    withContext(Dispatchers.Main.immediate) {
                        when (e) {
                            is ChatEvent.TextDelta -> { if (current == null) { current = UiMessage(UiMessage.Role.Assistant, "").also { messages += it } }; current!!.text += e.text }
                            is ChatEvent.ToolUse -> { current = null; UiMessage(UiMessage.Role.Tool, friendly(e.name), e.name).also { it.done = false; messages += it; toolRows[e.id] = it } }
                            is ChatEvent.ToolResult -> toolRows[e.id]?.let { it.done = true; it.failed = e.isError }
                            is ChatEvent.Failed -> messages += UiMessage(UiMessage.Role.Notice, e.message).also { it.failed = true }
                            is ChatEvent.Finished -> {}
                        }
                    }
                }
            } catch (_: CancellationException) { } finally {
                running = false; question?.answer?.complete("(stopped)"); question = null
                runNext()
            }
        }
    }

    private fun friendly(name: String) = name.replace('_', ' ').replaceFirstChar { it.uppercase() }

    private fun runNext() {
        nextUp?.let { nextUp = null; send(it); return }
        if (queue.isNotEmpty()) { val all = queue.joinToString("\n\n"); queue.clear(); send(all) }
    }

    fun sendNow(index: Int) {
        if (index !in queue.indices) return
        nextUp = queue.removeAt(index)
        if (running) cancelRun(announce = false) else runNext()
    }

    fun removeQueued(index: Int) { if (index in queue.indices) queue.removeAt(index) }

    private fun cancelRun(announce: Boolean = true) {
        job?.cancel(); question?.answer?.complete("(the user sent a new message)"); selectionRequest?.answer?.complete("(cancelled)"); scriptReview?.answer?.complete("CHANGES REQUESTED: the user stopped the task")
        question = null; selectionRequest = null; scriptReview = null
    }

    fun stop() { queue.clear(); nextUp = null; cancelRun(); messages += UiMessage(UiMessage.Role.Notice, "Stopped. Edits already made stay in the timeline (undo with Undo).") }

    fun answerQuestion(text: String) { question?.answer?.complete(text); question = null }
    fun dismissQuestion() { stop(); }
    fun finishSelection(summary: String?) { selectionRequest?.answer?.complete(summary ?: "(the user cancelled the selection)"); selectionRequest = null }
    fun finishScript(reply: String) { scriptReview?.answer?.complete(reply); scriptReview = null }

    /** The user opened the range picker themselves ("Select parts…"); the result becomes a message. */
    fun openSelectionManually() { val d = CompletableDeferred<String>(); selectionRequest = PendingSelection("Mark the parts of your videos that matter", emptyList(), d); scope.launch { val r = d.await(); if (!r.startsWith("(")) send(r, "I marked the parts that matter.") } }

    // ---------- What the tools can reach in the app ----------

    private inner class AndroidHost : Host {
        override fun playheadMs() = vm.playheadMs
        override fun workspaceRoots() = workspace.virtualPaths()

        override suspend fun importMedia(uriOrPath: String): Asset = withContext(Dispatchers.Main.immediate) {
            val uri = if (uriOrPath.startsWith("/")) workspace.resolve(uriOrPath)?.uri ?: throw ToolError("file not found in the opened folders: $uriOrPath") else Uri.parse(uriOrPath)
            vm.importAsset(uri)
        }

        override suspend fun ask(question: String, options: List<AskOption>, allowText: Boolean): String {
            val d = CompletableDeferred<String>()
            withContext(Dispatchers.Main.immediate) { this@AssistantModel.question?.answer?.complete("(the user moved on to another question)"); this@AssistantModel.question = PendingQuestion(question, options, allowText, d); vm.showAssistant = true }
            return d.await()
        }

        override suspend fun pickRanges(reason: String, assetIds: List<Id>): String {
            val d = CompletableDeferred<String>()
            withContext(Dispatchers.Main.immediate) { selectionRequest = PendingSelection(reason, assetIds, d); vm.showAssistant = true }
            return d.await()
        }

        override suspend fun reviewScript(draft: ScriptDraft): String {
            val d = CompletableDeferred<String>()
            withContext(Dispatchers.Main.immediate) { scriptReview = PendingScript(draft, d); vm.showAssistant = true }
            return d.await()
        }

        override suspend fun browseFolder(path: String, depth: Int) = workspace.describe(path, depth)

        override suspend fun contactSheet(asset: Asset, frames: Int, startMs: Ms?, endMs: Ms?) = FrameTools.contactSheet(ctx, asset, frames, startMs, endMs)

        private suspend fun surface(): SurfaceView? = withContext(Dispatchers.Main.immediate) { vm.playerView?.videoSurfaceView as? SurfaceView }

        private suspend fun frameAt(ms: Long): android.graphics.Bitmap? {
            val view = surface() ?: return null
            withContext(Dispatchers.Main.immediate) { vm.pausePlayback(); vm.player.seekTo(ms) }
            FrameTools.settle()
            return withContext(Dispatchers.Main.immediate) { FrameTools.grab(view) }
        }

        override suspend fun timelineFrame(project: Project, atMs: Ms): ByteArray? = frameAt(atMs.coerceIn(0, maxOf(0, project.duration - 1)))?.let { FrameTools.jpeg(it) }

        override suspend fun timelineSheet(project: Project, frames: Int, startMs: Ms?, endMs: Ms?): ByteArray? {
            if (project.duration == 0L) return null
            val a = (startMs ?: 0).coerceAtLeast(0); val b = (endMs ?: project.duration).coerceAtMost(project.duration)
            val keep = vm.playheadMs
            val shots = (0 until frames).mapNotNull { i -> val t = a + ((b - a) * (i + 0.5) / frames).toLong(); frameAt(t)?.let { t to it } }
            withContext(Dispatchers.Main.immediate) { vm.seek(keep) }
            return FrameTools.sheet(shots, columns = if (frames > 8) 4 else 3)
        }

        override suspend fun export(project: Project, name: String?): String = vm.exportToUri(name)

        override suspend fun assetInfo(asset: Asset): String =
            "name: ${asset.label}\nduration: ${asset.duration} ms\npicture: ${if (asset.hasVideo) "${asset.width}x${asset.height}" else "none"}\nsound: ${if (asset.hasAudio) "yes" else "none"}"
    }
}
