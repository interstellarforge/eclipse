package app.lumacut

import android.app.Application
import android.content.ContentValues
import android.content.Context
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.CompositionPlayer
import app.lumacut.core.*
import app.lumacut.media.Composer
import app.lumacut.media.Exporter
import app.lumacut.media.MediaProbe
import app.lumacut.media.TransitionBake
import app.lumacut.media.TransitionCompositor
import kotlinx.coroutines.*
import java.io.File

enum class LeftTab(val label: String) { Media("Media"), Files("Files"), Titles("Titles"), Overlays("Overlays"), Audio("Audio"), Transitions("Transitions"), Effects("Effects"), Color("Color"), Templates("Templates"), Smart("Smart") }
enum class RightTab(val label: String) { Assistant("Assistant"), Adjust("Adjust"), Effects("Effects"), Inspector("Inspector") }

class ImportState {
    var total by mutableStateOf(0); var done by mutableStateOf(0); var current by mutableStateOf("")
    val failures = mutableStateListOf<String>()
}

@UnstableApi
class EditorViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx: Context get() = getApplication()
    val prefs = ctx.getSharedPreferences("lumacut", Context.MODE_PRIVATE)

    val editor = Editor()
    var project by mutableStateOf(editor.project); private set
    var canUndo by mutableStateOf(false); private set
    var canRedo by mutableStateOf(false); private set
    var projectName by mutableStateOf("Untitled")
    var hasUnsavedWork by mutableStateOf(false)
    private var savedSnapshot: Project? = null

    var selection by mutableStateOf<Id?>(null)
    var multiSelection = mutableStateListOf<Id>()
    var selectedTransition by mutableStateOf<Id?>(null)
    var leftTab by mutableStateOf(LeftTab.Media)
    var rightTab by mutableStateOf(RightTab.Assistant)
    var showAssistant by mutableStateOf(false)
    var showPanel by mutableStateOf(false)
    var showInspector by mutableStateOf(false)
    var status by mutableStateOf("")

    // Preview diagnostics: shown on the preview when the player fails or hangs, and in Menu > Diagnostics.
    var previewNote by mutableStateOf<String?>(null)
    private val events = ArrayDeque<String>()
    private val clock = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US)
    private fun trace(msg: String) { android.util.Log.i("Lumacut", msg); events.addLast(clock.format(java.util.Date()) + " " + msg); while (events.size > 80) events.removeFirst() }
    private var lastError: Throwable? = null
    private var stuckJob: Job? = null
    private fun stateName(st: Int) = when (st) { Player.STATE_IDLE -> "idle"; Player.STATE_BUFFERING -> "buffering"; Player.STATE_READY -> "ready"; else -> "ended" }
    private fun watchStuck(p: Player) {
        stuckJob?.cancel()
        if (p.playWhenReady && p.playbackState != Player.STATE_READY && p.playbackState != Player.STATE_ENDED) stuckJob = viewModelScope.launch {
            delay(3000)
            if (p.playWhenReady && p.playbackState != Player.STATE_READY) {
                previewNote = "Preview is not starting (${stateName(p.playbackState)}). Menu > Diagnostics has the details."
                if (builtDurationMs <= 0 && project.duration > 0) scheduleRebuild(0)   // never prepared: try again now
            }
        } else if (p.playbackState == Player.STATE_READY) previewNote = null
    }
    fun diagnostics(): String {
        val log = try { Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-t", "1500")).inputStream.bufferedReader().readLines()
            .filter { l -> listOf("Lumacut", "Eclipse", "media3", "Exo", "Composition", "Transformer", "MediaCodec", "Codec2", "AndroidRuntime", "Exception", " E ", "FATAL").any { it in l } }.takeLast(60).joinToString("\n") } catch (e: Exception) { "no log: ${e.message}" }
        val pi = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        return buildString {
            appendLine("Eclipse ${pi.versionName} (${pi.longVersionCode}) · ${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("Player: state=${stateName(player.playbackState)} playWhenReady=${player.playWhenReady} position=${player.currentPosition} builtDuration=$builtDurationMs projectDuration=${project.duration}")
            appendLine("Note: ${previewNote ?: "-"}")
            lastError?.let { appendLine("Last error: " + android.util.Log.getStackTraceString(it).take(1500)) }
            appendLine("Assets:"); project.assets.forEach { appendLine("- ${it.label} ${it.width}x${it.height} ${it.duration}ms video=${it.hasVideo} audio=${it.hasAudio} still=${it.isStill}") }
            appendLine("Tracks: " + project.tracks.joinToString { "${it.kind}:${it.clips.size}" } + " · transitions=${project.transitions.size}")
            appendLine("---- events ----"); events.forEach { appendLine(it) }
            appendLine("---- log (filtered) ----"); append(log)
        }
    }

    // Updates (GitHub Releases)
    var update by mutableStateOf<Updater.Update?>(null)
    var updateProgress by mutableStateOf<Float?>(null)
    /** `manual` also reports "up to date" and errors; the automatic launch check (at most daily) stays silent. */
    fun checkForUpdate(manual: Boolean) {
        val prefs = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)
        viewModelScope.launch {
            try {
                val u = Updater.check(ctx)
                // Launch check: download and hand over to Android's installer by itself, once per version (a cancelled install is not repeated).
                if (u != null) { update = u; if (manual || prefs.getLong("tried", 0) != u.versionCode) { prefs.edit().putLong("tried", u.versionCode).apply(); installUpdate() } }
                else if (manual) status = "Eclipse is up to date (${ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName})"
            } catch (e: Exception) { if (manual) status = "Update check failed: ${e.message}" }
        }
    }
    fun installUpdate() {
        val u = update ?: return
        viewModelScope.launch {
            try {
                updateProgress = 0f
                val apk = Updater.download(ctx, u) { updateProgress = it }
                updateProgress = null
                if (Updater.install(ctx, apk)) update = null else status = "Allow installs from Eclipse, then tap Update again"
            } catch (e: Exception) { updateProgress = null; status = "Update failed: ${e.message}" }
        }
    }

    val thumbs = mutableStateMapOf<Id, Bitmap>()
    val filmstrips = mutableStateMapOf<Id, List<Bitmap>>()
    val waveforms = mutableStateMapOf<Id, FloatArray>()
    val importState = ImportState()
    private val importQueue = ArrayDeque<Uri>()
    private var importWorkers = 0

    // Playback
    var playheadMs by mutableStateOf(0L)
    var isPlaying by mutableStateOf(false)
    // Two players: the default single-input graph (the best-tested path) for projects with one video lane, and the multi-input graph when clips overlap (transitions).
    private val players = arrayOfNulls<CompositionPlayer>(2)
    private var activeMulti by mutableStateOf(false)
    val player: CompositionPlayer get() { val i = if (activeMulti) 1 else 0; return players[i] ?: createPlayer(i == 1).also { players[i] = it } }
    private fun createPlayer(multi: Boolean): CompositionPlayer {
        val b = CompositionPlayer.Builder(ctx)
        if (multi) b.setVideoGraphFactory(androidx.media3.effect.MultipleInputVideoGraph.Factory())
        return b.build().also { p ->
            p.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) { if (p === player) syncPlaying(p) }
                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) { if (p === player) syncPlaying(p) }
                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    android.util.Log.e("Lumacut", "player error", error); lastError = error; trace("player error ${error.errorCodeName}: ${error.cause?.message ?: error.message}")
                    previewNote = "Preview error: ${error.errorCodeName} ${error.cause?.message ?: error.message}".take(240); if (p === player) syncPlaying(p)
                }
                override fun onPlaybackStateChanged(state: Int) { trace("player state ${stateName(state)} (playWhenReady=${p.playWhenReady}, ${if (multi) "multi" else "single"} graph)"); if (p === player) syncPlaying(p) }
            })
        }
    }
    // Icon follows the user's intent (playWhenReady), not the moment frames flow, so it flips on tap even while buffering.
    private fun syncPlaying(p: Player) { watchStuck(p); isPlaying = p.playWhenReady && p.playbackState != Player.STATE_ENDED && p.playbackState != Player.STATE_IDLE }
    private val previewCompositor = TransitionCompositor()
    private var rebuildJob: Job? = null
    private var watchdog: Job? = null
    private val previewPrefs get() = ctx.getSharedPreferences("preview", Context.MODE_PRIVATE)
    /** Preview shows transitions as cuts (kept across launches once a device has proven it cannot play the blended preview). */
    var simplePreview by mutableStateOf(previewPrefs.getBoolean("simple", false))
    fun usePreviewCuts(on: Boolean) { simplePreview = on; previewPrefs.edit().putBoolean("simple", on).apply(); scheduleRebuild(0); scheduleBakes() }

    // ---------- Rendered transitions ----------
    private val bakedByKey = mutableMapOf<String, Asset>()
    private val failedBakes = mutableSetOf<String>()
    private var bakeJob: Job? = null
    var bakingNote by mutableStateOf<String?>(null)
    private fun bakedFor(p: Project): Map<Id, Asset> = TransitionBake.jobs(p).mapNotNull { j -> bakedByKey[j.key]?.let { j.transition.id to it } }.toMap()

    /** Renders one transition's overlap into a short clip (cached by content). Null when this phone cannot render it. */
    private suspend fun bake(job: TransitionBake.Job): Asset? {
        val file = File(ctx.cacheDir, "bake/${job.key}.mp4")
        try {
            if (!file.exists() || file.length() == 0L) {
                val t0 = System.currentTimeMillis(); val tmp = File(file.parentFile, "${job.key}.part").also { it.parentFile?.mkdirs() }
                kotlinx.coroutines.withTimeout(40_000) { Exporter(ctx).export(job.mini, tmp) }
                tmp.renameTo(file); trace("transition rendered in ${System.currentTimeMillis() - t0} ms")
            }
            return MediaProbe.probe(ctx, Uri.fromFile(file)).copy(id = "bake-${job.key}", name = "Transition")
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (e: Throwable) { trace("transition render FAILED ${e.javaClass.simpleName}: ${e.message}"); file.delete(); return null }
    }

    private fun scheduleBakes() {
        bakeJob?.cancel(); bakingNote = null
        val p = project
        if (simplePreview || p.transitions.isEmpty() || debugLiveTransitions) return
        val todo = TransitionBake.jobs(p).filter { it.key !in bakedByKey && it.key !in failedBakes }
        if (todo.isEmpty()) return
        bakeJob = viewModelScope.launch {
            delay(700)   // let a burst of edits settle first
            todo.forEachIndexed { i, j ->
                bakingNote = "Rendering transition ${i + 1} of ${todo.size}…"
                val a = bake(j)
                if (a != null) { bakedByKey[j.key] = a; scheduleRebuild(0) } else failedBakes += j.key
            }
            bakingNote = null
        }
    }

    /** The project to export: transitions rendered into clips (single lane); if that fails the live two-lane transitions are used. */
    var debugLiveTransitions = false   // debug builds only: skip the rendered-transition path
    private suspend fun exportProject(p: Project = project): Project {
        if (p.transitions.isEmpty() || debugLiveTransitions) return p
        val baked = mutableMapOf<Id, Asset>()
        for (j in TransitionBake.jobs(p)) {
            bakingNote = "Rendering transitions…"
            val a = bakedByKey[j.key] ?: bake(j)?.also { bakedByKey[j.key] = it }
            if (a == null) { bakingNote = null; trace("export: transition render failed, using live transitions"); return p }
            baked[j.transition.id] = a
        }
        bakingNote = null
        return TransitionBake.substitute(p, baked)
    }
    private var builtDurationMs = -1L
    var playerView: androidx.media3.ui.PlayerView? = null

    // Export
    var exporting by mutableStateOf(false); var exportProgress by mutableStateOf(0f)
    var exportResult by mutableStateOf<String?>(null)

    val scope: CoroutineScope get() = viewModelScope
    val assistant = AssistantModel(this)

    init {
        editor.onChange = { refresh() }
        restoreRecovery()
        checkForUpdate(manual = false)
        viewModelScope.launch { while (true) { delay(33); if (isPlaying) { playheadMs = player.currentPosition.coerceAtLeast(0); if (playheadMs >= project.duration) pausePlayback() } } }
    }

    private fun refresh() {
        project = editor.project; canUndo = editor.canUndo; canRedo = editor.canRedo
        hasUnsavedWork = !(project.assets.isEmpty() && project.tracks.isEmpty()) && project != savedSnapshot
        if (selection != null && project.clip(selection!!) == null) selection = null
        if (selectedTransition != null && project.transitions.none { it.id == selectedTransition }) selectedTransition = null
        multiSelection.removeAll { project.clip(it) == null }
        scheduleRebuild(); scheduleBakes(); autosave()
    }

    // ---------- Preview ----------

    private fun scheduleRebuild(delayMs: Long = 250) {
        if (rebuildJob?.isActive != true) trace("rebuild scheduled")
        rebuildJob?.cancel(); watchdog?.cancel()
        rebuildJob = viewModelScope.launch {
            delay(delayMs)   // a batch of edits (the assistant's whole edit) builds the preview once
            val p = project
            val has = p.allClips.any { it.assetID != null || it.generator != null || it.text != null } && p.tracks.any { it.kind != TrackKind.text && it.clips.any { c -> c.assetID != null } }
            if (!has) { player.clearMediaItems(); builtDurationMs = 0; trace("nothing to preview"); return@launch }
            val t0 = System.currentTimeMillis()
            try {
                trace("build start: ${p.allClips.size} clips")
                // Overlaps become rendered transitions (or cuts until they are rendered): one video lane plays on every phone.
                val shown = if (debugLiveTransitions) p else TransitionBake.substitute(p, if (simplePreview) emptyMap() else bakedFor(p))
                val built = withContext(Dispatchers.Default) { Composer(ctx).build(shown, previewCompositor) }
                trace("build ok in ${System.currentTimeMillis() - t0} ms, ${built.composition.sequences.size} sequences")
                val pos = playheadMs
                if (built.multiLane != activeMulti) { player.pause(); player.clearMediaItems(); activeMulti = built.multiLane; trace("using ${if (built.multiLane) "multi" else "single"}-input graph") }
                player.setComposition(built.composition); player.prepare()
                player.seekTo(pos.coerceIn(0, maxOf(0, built.durationMs - 1)))
                builtDurationMs = built.durationMs
                previewNote = null
                trace("preview prepared (${built.durationMs} ms)")
                // Overlapping clips need the multi-input graph; if this device cannot get it going, fall back to cuts instead of a dead player.
                watchdog?.cancel()
                if (built.multiLane && !simplePreview) watchdog = viewModelScope.launch {
                    delay(8000)
                    if (player.playbackState != Player.STATE_READY && player.playbackState != Player.STATE_ENDED) {
                        trace("multi-lane preview never became ready: switching to cuts"); status = "This phone can't preview transitions: shown as cuts. Export still has them."
                        usePreviewCuts(true)
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) { trace("build cancelled"); throw e
            } catch (e: Throwable) { android.util.Log.e("Lumacut", "preview build failed", e); lastError = e; trace("build FAILED ${e.javaClass.simpleName}: ${e.message}"); previewNote = "Preview build failed: ${e.javaClass.simpleName} ${e.message}".take(240) }
        }
    }

    fun togglePlay() { if (builtDurationMs <= 0 && project.duration > 0) previewNote = "Preview is still being prepared…"; if (isPlaying) pausePlayback() else { if (playheadMs >= project.duration - 50) seek(0); player.play() } }
    fun pausePlayback() { player.pause() }
    fun seek(ms: Long) { playheadMs = ms.coerceIn(0, maxOf(0, project.duration)); if (builtDurationMs > 0) player.seekTo(playheadMs) }
    fun step(frames: Int) { pausePlayback(); seek(playheadMs + (frames * 1000L / project.fps)) }
    fun jumpToEdit(forward: Boolean) {
        val edges = (project.allClips.flatMap { listOf(it.start, it.end) } + listOf(0L, project.duration)).toSortedSet()
        (if (forward) edges.firstOrNull { it > playheadMs + 1 } else edges.lastOrNull { it < playheadMs - 1 })?.let { pausePlayback(); seek(it) }
    }

    // ---------- Import ----------

    fun importUris(uris: List<Uri>) {
        uris.forEach { u -> try { ctx.contentResolver.takePersistableUriPermission(u, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {} }
        val fresh = uris.filter { u -> u !in importQueue && project.assets.none { it.url == u.toString() } }
        if (fresh.isEmpty()) return
        importState.total += fresh.size; importQueue.addAll(fresh)
        while (importWorkers < 3 && importQueue.isNotEmpty()) { importWorkers++; viewModelScope.launch { importWorker() } }
    }

    private suspend fun importWorker() {
        while (importQueue.isNotEmpty()) {
            val uri = importQueue.removeFirst()
            importState.current = uri.lastPathSegment?.substringAfterLast('/') ?: ""
            try { importAsset(uri) } catch (e: Exception) { importState.failures += "${uri.lastPathSegment?.substringAfterLast('/')}: ${e.message}" }
            importState.done++
        }
        importWorkers--
        if (importWorkers == 0) { importState.total = 0; importState.done = 0; importState.current = "" }
    }

    fun cancelImports() { importState.total -= importQueue.size; importQueue.clear() }

    /** Registers the file (reusing the entry if it is already in the library), then fills in thumbnail and waveform. */
    suspend fun importAsset(uri: Uri): Asset {
        project.assets.firstOrNull { it.url == uri.toString() }?.let { return it }
        val asset = MediaProbe.probe(ctx, uri)
        editor.apply(Command.AddAsset(asset))
        viewModelScope.launch {
            MediaProbe.thumbnail(ctx, asset)?.let { thumbs[asset.id] = it }
            if (asset.hasAudio && !asset.hasVideo || asset.hasAudio) waveforms[asset.id] = MediaProbe.waveform(ctx, asset)
        }
        return asset
    }

    fun ensureFilmstrip(asset: Asset) {
        if (filmstrips.containsKey(asset.id) || !asset.hasVideo) return
        filmstrips[asset.id] = emptyList()
        viewModelScope.launch { filmstrips[asset.id] = MediaProbe.filmstrip(ctx, asset) }
    }

    fun ensureAssetMedia(asset: Asset) {
        if (thumbs[asset.id] == null && asset.hasVideo) viewModelScope.launch { MediaProbe.thumbnail(ctx, asset)?.let { thumbs[asset.id] = it } }
        if (asset.hasAudio && waveforms[asset.id] == null) { waveforms[asset.id] = FloatArray(0); viewModelScope.launch { waveforms[asset.id] = MediaProbe.waveform(ctx, asset) } }
    }

    /** A built-in song as an imported asset (rendered once into the cache). */
    suspend fun musicAsset(name: String): Asset? {
        val song = MusicLibrary.song(name) ?: return null
        val file = withContext(Dispatchers.Default) { MusicLibrary.file(song.name, File(ctx.cacheDir, "music")) }
        return importAsset(Uri.fromFile(file))
    }

    // ---------- Edits (all wrap one command or a transaction; errors become the status line) ----------

    fun run(quiet: Boolean = false, block: Editor.() -> Unit) {
        try { editor.block() } catch (e: EditError) { if (!quiet) status = e.message ?: "That edit isn't possible" } catch (e: Exception) { status = e.message ?: "error" }
    }
    fun undo() = editor.undo()
    fun redo() = editor.redo()

    val selectedClip: Clip? get() = selection?.let { project.clip(it) }
    val selectedTransitionValue: Transition? get() = project.transitions.firstOrNull { it.id == selectedTransition }

    fun selectClip(id: Id?, additive: Boolean = false) {
        selectedTransition = null
        if (additive && selection != null && id != null && selection != id) { if (id in multiSelection) multiSelection.remove(id) else multiSelection.add(id) }
        else { multiSelection.clear(); selection = id }
        if (id != null && selection == id) rightTab = if (rightTab == RightTab.Assistant) RightTab.Adjust else rightTab
    }
    fun selectTransition(id: Id) { selection = null; multiSelection.clear(); selectedTransition = id; rightTab = RightTab.Adjust; showInspector = true }

    fun addToTimeline(asset: Asset) = run { addClip(asset) }
    fun splitAtPlayhead() { val c = selectedClip?.takeIf { playheadMs > it.start && playheadMs < it.end } ?: project.allClips.firstOrNull { playheadMs > it.start && playheadMs < it.end } ?: return; run { apply(Command.SplitClip(c.id, playheadMs)) } }
    fun deleteSelection(ripple: Boolean = false) {
        val ids = (multiSelection + listOfNotNull(selection)).distinct()
        selectedTransition?.let { id -> run { apply(Command.RemoveTransition(id)) }; selectedTransition = null; return }
        if (ids.isEmpty()) return
        run { transaction { ids.forEach { if (project.clip(it) != null) apply(if (ripple) Command.RippleRemove(it) else Command.RemoveClip(it)) } } }
        selection = null; multiSelection.clear()
    }
    fun duplicateSelection() { val id = selection ?: return; run { selection = duplicate(id).id } }
    fun groupSelection() { val ids = (multiSelection + listOfNotNull(selection)).distinct(); if (ids.size < 2) { status = "Tap a second clip with Select more, then group"; return }; run { apply(Command.Group(ids)) } }
    fun ungroupSelection() { val id = selection ?: return; run { apply(Command.Ungroup(id)) } }
    fun detachAudioSelection() { val id = selection ?: return; run { detachAudio(id) } }
    fun resetSelection() { val id = selection ?: return; run { resetClip(id) } }

    fun applyLook(name: String) {
        val preset = LookPresets.preset(name) ?: return
        val targets = selectedClip?.let { listOf(it.id) } ?: project.tracks.filter { it.kind == TrackKind.video }.flatMap { it.clips }.filter { it.assetID != null }.map { it.id }
        if (targets.isEmpty()) { status = "Add a clip first."; return }
        run { transaction { targets.forEach { id -> apply(Command.SetLook(id, project.clip(id)!!.look.withColourOf(preset))) } } }
    }
    fun addEffect(type: EffectType) { val c = selectedClip; if (c == null) { status = "Select a clip first."; return }; run { apply(Command.AddEffect(c.id, Effect(type = type))) } }
    fun addTransitionTo(type: TransitionType) {
        val c = selectedClip
        if (c == null) { status = "Select a clip, then pick a transition for the join after it."; return }
        run { addTransitionAfter(c.id, type, 800) }
    }
    fun addTitle(preset: TitlePreset) = run { val c = addTitle(preset.sampleText, playheadMs); apply(Command.SetTextStyle(c.id, preset.style)); selection = c.id }
    fun addOverlay(kind: GeneratorKind) = run { selection = addOverlay(kind, playheadMs, 4_000, 0.5).id }
    fun addSticker(emoji: String) = run { selection = addSticker(emoji, playheadMs).id }
    fun applyTemplate(t: EditTemplate) = run { status = applyTemplate(t) }

    // ---------- Projects ----------

    private val projectsDir get() = File(ctx.filesDir, "projects").also { it.mkdirs() }
    private val recoveryFile get() = File(ctx.filesDir, "recovery.moviemaker")
    private var autosaveJob: Job? = null

    private fun autosave() { autosaveJob?.cancel(); autosaveJob = viewModelScope.launch(Dispatchers.IO) { delay(800); try { recoveryFile.writeText(ProjectIO.encode(project)) } catch (_: Exception) {} } }
    private fun restoreRecovery() { try { if (recoveryFile.exists()) { val p = ProjectIO.decode(recoveryFile.readText()); if (p.assets.isNotEmpty() || p.tracks.isNotEmpty()) { editor.replace(p); loadMediaFor(p) } } } catch (_: Exception) {} }
    private fun loadMediaFor(p: Project) { p.assets.forEach { ensureAssetMedia(it) } }

    fun savedProjects(): List<File> = projectsDir.listFiles { f -> f.extension == "moviemaker" }?.sortedByDescending { it.lastModified() } ?: emptyList()
    fun save(name: String = projectName) {
        val safe = safeName(name)
        File(projectsDir, "$safe.moviemaker").writeText(ProjectIO.encode(project)); projectName = safe; savedSnapshot = project; hasUnsavedWork = false; status = "Saved “$safe”"
    }
    fun open(file: File) { try { val p = ProjectIO.decode(file.readText()); editor.replace(p); projectName = file.nameWithoutExtension; savedSnapshot = p; hasUnsavedWork = false; loadMediaFor(p); seek(0) } catch (e: Exception) { status = "Can't open: ${e.message}" } }
    fun newProject() { editor.replace(Project()); projectName = "Untitled"; savedSnapshot = editor.project; hasUnsavedWork = false; selection = null; seek(0); thumbs.clear(); waveforms.clear(); filmstrips.clear() }
    fun deleteSaved(file: File) { file.delete() }
    fun savedExists(name: String) = File(projectsDir, "${safeName(name)}.moviemaker").exists()
    fun projectsPath(): String = projectsDir.absolutePath
    fun safeName(name: String) = name.trim().ifEmpty { "Untitled" }.replace(Regex("[^A-Za-z0-9 _-]"), "_")
    /** Copy the project to any place the user picks (Downloads, Drive, SD card) through the system file picker. */
    fun exportProjectTo(uri: Uri) { try { ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(ProjectIO.encode(project).toByteArray()) }; status = "Saved a copy" } catch (e: Exception) { status = "Can't save: ${e.message}" } }
    fun openProjectFrom(uri: Uri) {
        try {
            val p = ProjectIO.decode(ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() })
            editor.replace(p); projectName = uri.lastPathSegment?.substringAfterLast('/')?.substringBeforeLast('.')?.ifBlank { null } ?: "Untitled"
            savedSnapshot = p; hasUnsavedWork = false; loadMediaFor(p); seek(0)
        } catch (e: Exception) { status = "Can't open: ${e.message}" }
    }

    // ---------- Export ----------

    enum class Quality(val label: String, val bitsPerPixel: Double) { Low("Small file", 0.05), Medium("Balanced", 0.09), High("Best", 0.14) }
    class ExportOptions(val name: String, val shortSide: Int, val fps: Int, val quality: Quality) {
        /** Output size: the canvas scaled so its short side matches (0 = as edited), even numbers for the encoder. */
        fun size(p: Project): Pair<Int, Int> {
            if (shortSide == 0) return p.width to p.height
            val k = shortSide.toDouble() / minOf(p.width, p.height)
            return (Math.round(p.width * k / 2).toInt() * 2) to (Math.round(p.height * k / 2).toInt() * 2)
        }
        fun bitrate(p: Project): Int { val (w, h) = size(p); return (w.toLong() * h * fps * quality.bitsPerPixel).toInt() }
        fun megabytes(p: Project): Int = ((bitrate(p) + 128_000L) / 8.0 * p.duration / 1000 / 1_000_000).toInt().coerceAtLeast(1)
    }
    var exportOptions by mutableStateOf(ExportOptions(projectName, prefs.getInt("exportShort", 0), prefs.getInt("exportFps", 30), Quality.values().getOrElse(prefs.getInt("exportQuality", 1)) { Quality.Medium }))
    fun updateExportOptions(o: ExportOptions) { exportOptions = o; prefs.edit().putInt("exportShort", o.shortSide).putInt("exportFps", o.fps).putInt("exportQuality", o.quality.ordinal).apply() }
    /** Opens the saved video in the user's video app. */
    fun openExported() { exportResult?.let { try { ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(it), "video/mp4").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (e: Exception) { status = "No app can play this video" } } }
    fun shareExported() { exportResult?.let { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("video/mp4").putExtra(Intent.EXTRA_STREAM, Uri.parse(it)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Share video").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }

    fun export(onDone: (String) -> Unit = {}) {
        if (exporting || project.duration == 0L) return
        exporting = true; exportProgress = 0f; pausePlayback()
        rebuildJob?.cancel(); bakeJob?.cancel(); bakingNote = null; player.clearMediaItems(); builtDurationMs = -1   // free the preview's decoders: the exporter needs them
        viewModelScope.launch {
            try {
                val tmp = File(ctx.cacheDir, "export-${System.currentTimeMillis()}.mp4")
                trace("export start")
                var lastTen = -1
                val o = exportOptions; val (w, h) = o.size(project)
                val exportable = exportProject(project.copy(width = w, height = h, fps = o.fps))
                Exporter(ctx).export(exportable, tmp, { exportProgress = it; val d = (it * 10).toInt(); if (d != lastTen) { lastTen = d; trace("export ${d * 10}%") } }, bitrate = o.bitrate(project), outputFps = o.fps)
                val uri = saveToMovies(tmp, o.name.ifBlank { projectName }); tmp.delete()
                exportResult = uri.toString(); status = "Exported to Movies/Eclipse"; trace("export done"); onDone(uri.toString())
            } catch (e: Exception) { trace("export FAILED ${e.message}"); status = "Export failed: ${e.message}" } finally { exporting = false; scheduleRebuild(0) }
        }
    }

    suspend fun exportToUri(name: String?): String {
        val tmp = File(ctx.cacheDir, "export-${System.currentTimeMillis()}.mp4")
        Exporter(ctx).export(exportProject(), tmp, onProgress = { exportProgress = it })
        val uri = saveToMovies(tmp, name ?: projectName); tmp.delete()
        return uri.toString()
    }

    private suspend fun saveToMovies(file: File, name: String): Uri = withContext(Dispatchers.IO) {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "${name.replace(Regex("[\\\\/:*?\"<>|]"), "_")}.mp4"); put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/Eclipse")
        }
        val uri = ctx.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: throw IllegalStateException("can't create the file")
        ctx.contentResolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
        uri
    }

    /** Debug aid (launch with --ez demo true): builds a small sample project from files pushed to /sdcard/Movies. */
    fun loadDemo(level: Int = 9) = viewModelScope.launch {
        try {
            val a = importAsset(Uri.parse("file:///sdcard/Movies/beach-walk.mp4")); val b = importAsset(Uri.parse("file:///sdcard/Movies/city-night.mp4"))
            val c1 = editor.addClip(a, duration = 3_000); val c2 = if (level == 0) c1 else editor.addClip(b, sourceIn = 1_000, duration = 3_000)
            if (level >= 3) { editor.apply(Command.SetLook(c1.id, LookPresets.preset("Golden hour")!!)); editor.apply(Command.AddEffect(c1.id, Effect(type = EffectType.vignette, amount = 0.5))) }
            if (level >= 2) editor.addTransitionAfter(c1.id, TransitionType.crossfade, 800)
            if (level >= 4) editor.addTitle("Summer in Lisbon", 500, 2_500).also { editor.apply(Command.SetTextStyle(it.id, TitlePreset.movie.style)) }
            if (level == 13) editor.addClip(a, sourceIn = 500, duration = 2_000)
            if (level in 10..12) {   // phone-sized project: many clips, a few transitions
                val ids = mutableListOf(c1.id, c2.id)
                repeat(12) { i -> ids += editor.addClip(if (i % 2 == 0) a else b, sourceIn = 500L * (i % 5), duration = 2_000).id }
                if (level == 10) editor.apply(Command.SetSpeed(ids[5], 1.5)); if (level != 12) { editor.addTransitionAfter(ids[3], TransitionType.crossfade, 600); editor.addTransitionAfter(ids[7], TransitionType.crossfade, 600) }
            }
            projectName = "Demo"
        } catch (e: Exception) { status = "Demo: ${e.message}" }
    }

    // ---------- Tray and drag-and-drop ----------

    /** Category shown in the one-row tray above the navigation (null = tray hidden). */
    var trayTab by mutableStateOf<LeftTab?>(LeftTab.Media)
    enum class DragKind { Transition, Effect, Look, Overlay, Title, Media }
    class DragPayload(val kind: DragKind, val key: String, val label: String)
    sealed interface DropTarget {
        data class OnClip(val id: Id) : DropTarget
        data class AfterClip(val id: Id) : DropTarget          // the join between this clip and the next
        data class AtTime(val ms: Long) : DropTarget
    }
    var drag by mutableStateOf<DragPayload?>(null)
    var dragPos by mutableStateOf(Offset.Zero)                  // pointer, window coordinates
    var dropTarget by mutableStateOf<DropTarget?>(null)
    /** Filled by the timeline while it is on screen (not state: read only while dragging). */
    val clipBounds = HashMap<Id, Rect>()
    var timelineRect: Rect = Rect.Zero
    var xToMs: (Float) -> Long = { 0L }

    fun dragStart(p: DragPayload, at: Offset) { drag = p; dragPos = at; dragMove(Offset.Zero) }
    fun dragMove(delta: Offset) {
        val p = drag ?: return
        dragPos += delta
        val pos = dragPos
        val overId = clipBounds.entries.firstOrNull { it.value.contains(pos) }?.key
        dropTarget = when (p.kind) {
            DragKind.Transition -> overId?.let { id ->
                val track = project.trackOf(id); val clips = track?.clips?.sortedBy { it.start } ?: return@let null
                val i = clips.indexOfFirst { it.id == id }; val r = clipBounds[id]!!
                val left = pos.x < r.center.x
                val join = if (left) clips.getOrNull(i - 1) else clips[i]
                join?.takeIf { j -> clips.any { it.start == j.end } }?.let { DropTarget.AfterClip(it.id) }
            }
            DragKind.Effect, DragKind.Look -> overId?.let { DropTarget.OnClip(it) }
            DragKind.Overlay, DragKind.Title, DragKind.Media -> if (timelineRect.contains(pos)) DropTarget.AtTime(xToMs(pos.x)) else null
        }
    }
    fun dragEnd() {
        val p = drag; val t = dropTarget
        drag = null; dropTarget = null
        if (p == null) return
        if (t == null) { status = "Drop it on the timeline"; return }
        when {
            p.kind == DragKind.Transition && t is DropTarget.AfterClip -> run { addTransitionAfter(t.id, TransitionType.valueOf(p.key), 800) }
            p.kind == DragKind.Effect && t is DropTarget.OnClip -> { selectClip(t.id); run { apply(Command.AddEffect(t.id, Effect(type = EffectType.valueOf(p.key)))) } }
            p.kind == DragKind.Look && t is DropTarget.OnClip -> { selectClip(t.id); applyLook(p.key) }
            p.kind == DragKind.Overlay && t is DropTarget.AtTime -> run { selection = addOverlay(GeneratorKind.valueOf(p.key), t.ms, 4_000, 0.5).id }
            p.kind == DragKind.Title && t is DropTarget.AtTime -> { val preset = TitlePreset.valueOf(p.key); run { val c = addTitle(preset.sampleText, t.ms); apply(Command.SetTextStyle(c.id, preset.style)); selection = c.id } }
            p.kind == DragKind.Media && t is DropTarget.AtTime -> project.asset(p.key)?.let { a -> run { selection = addClip(a, start = t.ms).id } }
        }
    }
    fun dragCancel() { drag = null; dropTarget = null }

    override fun onCleared() { players.forEach { it?.release() }; super.onCleared() }
}
