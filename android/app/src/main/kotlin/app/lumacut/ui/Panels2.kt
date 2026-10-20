package app.lumacut.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.*
import app.lumacut.core.*
import app.lumacut.media.TransitionCompositor
import kotlinx.coroutines.launch

/** A tile with a picture (or an icon) and text, shown as small previews, large previews, a list or a detail list. */
@Composable
fun <T> Gallery(items: List<T>, mode: ViewMode, key: (T) -> Any, title: (T) -> String, subtitle: (T) -> String? = { null }, detail: (T) -> String? = { null },
                picture: @Composable (T, Modifier) -> Unit, onClick: (T) -> Unit, header: @Composable () -> Unit = {}) {
    LazyVerticalGrid(GridCells.Fixed(mode.columns), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) { Column { header() } }
        items(items, key = key) { t ->
            if (mode.row) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Pal.raised).clickable { onClick(t) }.padding(6.dp), verticalAlignment = Alignment.Top) {
                picture(t, Modifier.width(if (mode == ViewMode.Detail) 120.dp else 72.dp).aspectRatio(16f / 9).clip(RoundedCornerShape(8.dp)))
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(title(t), color = Pal.text, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                    subtitle(t)?.let { Text(it, color = Pal.dim, fontSize = 11.sp, maxLines = 1) }
                    if (mode == ViewMode.Detail) detail(t)?.let { Text(it, color = Pal.dim, fontSize = 11.sp, maxLines = 4, overflow = TextOverflow.Ellipsis) }
                }
            } else Column(Modifier.clip(RoundedCornerShape(12.dp)).background(Pal.raised).clickable { onClick(t) }.padding(if (mode == ViewMode.Small) 4.dp else 6.dp)) {
                picture(t, Modifier.fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(8.dp)))
                Text(title(t), color = Pal.text, fontSize = if (mode == ViewMode.Small) 10.sp else 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
                if (mode == ViewMode.Large) subtitle(t)?.let { Text(it, color = Pal.dim, fontSize = 10.sp, maxLines = 1) }
            }
        }
    }
}

@Composable
private fun IconTile(icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, tint: Color = Pal.accent) =
    Box(modifier.background(Pal.panel), Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(28.dp)) }

@Composable
fun TitlesPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.Large) }
    PanelHeader("Titles", "Tap to add at the playhead. Select a title to change text, size, colour and animation.") { ViewModeMenu(mode) { mode = it } }
    Gallery(TitlePreset.entries, mode, { it.name }, { it.label }, { null }, { "“${it.sampleText}”" }, { p, m -> PreviewImage(p, m) { Previews.title(p) } }, { vm.addTitle(it) }) {
        SectionTitle("Stickers")
        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("🔥", "❤️", "😂", "😎", "🎉", "👏", "⭐️", "✨", "🚀", "💯", "👍", "😍", "🌴", "☀️", "🏆", "🎵", "📍", "⚡️").forEach { e ->
                Box(Modifier.clip(RoundedCornerShape(10.dp)).background(Pal.raised).clickable { vm.addSticker(e) }.padding(horizontal = 10.dp, vertical = 6.dp)) { Text(e, fontSize = 22.sp) }
            }
        }
    }
}

@Composable
fun OverlaysPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.Large) }
    PanelHeader("Overlays", "Drawn layers above your picture: confetti, snow, rain, light. Tap to add at the playhead.") { ViewModeMenu(mode) { mode = it } }
    Gallery(GeneratorKind.entries, mode, { it.name }, { it.title }, { null }, { it.summary }, { k, m -> PreviewImage(k, m) { Previews.overlay(k) } }, { vm.addOverlay(it) })
}

@Composable
fun TransitionsPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.List) }
    val selected = vm.selectedClip
    PanelHeader("Transitions", "${TransitionType.entries.size} styles. Select a clip, then tap one to join it to the next clip. On Android each style plays as the nearest of dissolve, dip, push or zoom/spin.") { ViewModeMenu(mode) { mode = it } }
    Gallery(TransitionType.entries, mode, { it.name }, { it.title }, { TransitionCompositor.family(it).name }, { "Plays as a ${TransitionCompositor.family(it).name.lowercase()} on Android." },
        { t, m -> IconTile(Icons.Filled.CallMerge, m, Pal.transition) }, { vm.addTransitionTo(it) })
}

@Composable
fun EffectsPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.List) }
    PanelHeader("Effects", "Select a video clip, then tap an effect to add it. Adjust the strength in Adjust.") { ViewModeMenu(mode) { mode = it } }
    Gallery(EffectType.entries.filter { it != EffectType.chromaKey && it != EffectType.removeBackground }, mode, { it.name }, { it.title }, { null }, { it.summary },
        { t, m -> PreviewImage(t, m) { Previews.look(Look(), listOf(t)) } }, { vm.addEffect(it) })
}

@Composable
fun ColorPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.Large) }
    PanelHeader("Color", "Looks apply to the selected clip, or to every clip when nothing is selected.") { ViewModeMenu(mode) { mode = it } }
    Gallery(LookPresets.names, mode, { it }, { it }, { null }, { null }, { n, m -> PreviewImage(n, m) { Previews.look(LookPresets.preset(n)!!) } }, { vm.applyLook(it) })
}

@Composable
fun TemplatesPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.Large) }
    var category by remember { mutableStateOf("All") }
    val list = Templates.all.filter { category == "All" || it.category == category }
    PanelHeader("Templates", "${Templates.all.size} film styles: colour, effects, joins, titles and overlay in one tap.") { ViewModeMenu(mode) { mode = it } }
    Gallery(list, mode, { it.id }, { it.name }, { it.category }, { "${it.summary}\n${it.pace}" }, { t, m -> PreviewImage(t.id, m) { Previews.template(t) } }, { vm.applyTemplate(it) }) {
        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            (listOf("All") + Templates.categories).forEach { c -> Pill(c, category == c) { category = c } }
        }
    }
}

@UnstableApi
@Composable
fun AudioPanel(vm: EditorViewModel) {
    val audio = vm.project.assets.filter { !it.hasVideo }
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenMultipleDocuments()) { vm.importUris(it) }
    var category by remember { mutableStateOf("All") }
    var busy by remember { mutableStateOf<String?>(null) }
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val recorder = remember { app.lumacut.media.VoiceRecorder(ctx) }
    var recording by remember { mutableStateOf(false) }
    val permission = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) { try { recorder.start(); recording = true } catch (e: Exception) { vm.status = "Can't record: ${e.message}" } } else vm.status = "Microphone access is off. Allow it in the phone's settings to record a voice-over."
    }
    fun toggleRecord() {
        if (recording) {
            recording = false
            val f = recorder.stop()
            if (f == null) vm.status = "Nothing was recorded." else vm.scope.launch { try { val a = vm.importAsset(android.net.Uri.fromFile(f)); vm.run { addClip(a, start = vm.playheadMs) } } catch (e: Exception) { vm.status = "Can't import the recording: ${e.message}" } }
        } else if (androidx.core.content.ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED) { try { recorder.start(); recording = true } catch (e: Exception) { vm.status = "Can't record: ${e.message}" } }
        else permission.launch(android.Manifest.permission.RECORD_AUDIO)
    }
    DisposableEffect(Unit) { onDispose { if (recording) recorder.stop() } }
    PanelHeader("Audio", "Free music made by the app (tempo known), your own sound files and voice-over. Music beds duck under speech.") {
        IconBtn(if (recording) Icons.Filled.Stop else Icons.Filled.Mic, if (recording) "Stop and add the voice-over" else "Record a voice-over at the playhead", { toggleRecord() }, active = recording, tint = if (recording) Pal.danger else null)
        Button({ picker.launch(arrayOf("audio/*")) }) { Icon(Icons.Filled.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Add file") }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (audio.isNotEmpty()) { item { SectionTitle("Your audio") }
            items(audio, key = { it.id }) { a ->
                LaunchedEffect(a.id) { vm.ensureAssetMedia(a) }
                Card(Modifier.fillMaxWidth()) { Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.MusicNote, null, tint = Pal.audio)
                    Column(Modifier.padding(start = 10.dp).weight(1f)) { Text(a.label, color = Pal.text, fontSize = 14.sp, maxLines = 1); Text(formatTime(a.duration), color = Pal.dim, fontSize = 11.sp) }
                    IconBtn(Icons.Filled.AddCircle, "Add at the playhead", { vm.run { addClip(a, start = vm.playheadMs) } }, tint = Pal.accent)
                    IconBtn(Icons.Filled.LibraryMusic, "Add as music bed (ducks under speech)", { vm.run { addMusicBed(a, 0); val t = project.tracks.lastOrNull { it.kind == TrackKind.audio }; if (t != null) apply(Command.SetTrackDuck(t.id, true)) } })
                } }
            }
        }
        item { SectionTitle("Music library (${MusicLibrary.tracks.size} songs)") }
        item { androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { (listOf("All") + MusicLibrary.categories).forEach { c -> Pill(c, category == c) { category = c } } } }
        items(MusicLibrary.tracks.filter { category == "All" || it.category == category }, key = { it.name }) { t ->
            Card(Modifier.fillMaxWidth()) { Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LibraryMusic, null, tint = Pal.accent)
                Column(Modifier.padding(start = 10.dp).weight(1f)) { Text(t.name, color = Pal.text, fontSize = 14.sp, maxLines = 1); Text("${t.bpm.toInt()} BPM · ${t.mood}", color = Pal.dim, fontSize = 11.sp, maxLines = 2) }
                if (busy == t.name) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = Pal.accent)
                else IconBtn(Icons.Filled.AddCircle, "Add as music bed", { busy = t.name; vm.scope.launch { try { val a = vm.musicAsset(t.name); if (a != null) vm.run { addMusicBed(a, 0); val tr = project.tracks.lastOrNull { it.kind == TrackKind.audio }; if (tr != null) apply(Command.SetTrackDuck(tr.id, true)) } } finally { busy = null } } }, tint = Pal.accent)
            } }
        }
    }
}

@UnstableApi
@Composable
fun SmartPanel(vm: EditorViewModel) {
    val c = vm.selectedClip
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { PanelHeader("Smart tools", "Everything they do can be undone.") }
        item {
            Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Speed ramps", color = Pal.text, fontWeight = FontWeight.SemiBold)
                Text(if (c?.assetID != null) "Smooth slow-motion and fast curves inside the selected clip." else "Select a video or audio clip first.", color = Pal.dim, fontSize = 12.sp)
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SpeedRamp.presets.forEach { (name, pts) -> Pill(name) { val id = vm.selection ?: return@Pill; vm.run { apply(Command.RampSpeed(id, pts, 20)) } } }
                }
            } }
        }
        item {
            Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Vertical video (9:16)", color = Pal.text, fontWeight = FontWeight.SemiBold)
                Text("Sets a vertical canvas and fills it with the selected clip (or every video clip), centred. It does not follow the subject.", color = Pal.dim, fontSize = 12.sp)
                Button({
                    vm.run { transaction {
                        apply(Command.SetFormat(1080, 1920, project.fps))
                        val targets = vm.selectedClip?.let { listOf(it) } ?: project.tracks.filter { it.kind == TrackKind.video }.flatMap { it.clips }.filter { it.assetID != null }
                        for (clip in targets) {
                            val a = project.asset(clip.assetID) ?: continue
                            if (a.width > 0 && a.height > 0) { val sw = 1080.0 / a.width; val sh = 1920.0 / a.height; apply(Command.SetTransform(clip.id, clip.opacity, maxOf(sw, sh) / minOf(sw, sh), clip.offsetX, clip.offsetY)) }
                        }
                    } }
                }) { Text("Make vertical") }
            } }
        }
        item {
            Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Ask the Assistant", color = Pal.text, fontWeight = FontWeight.SemiBold)
                Button({ vm.showAssistant = true; vm.assistant.send("[GUIDED EDIT] Guide me step by step through making a film from my clips. Use the guided-edit skill and ask me one question at a time.", "Guided edit: ask me step by step") }) { Text("Guided edit") }
                OutlinedButton({ vm.showAssistant = true; vm.assistant.send("Review my current edit and suggest three concrete improvements. Do not change anything yet.", "Suggest improvements") }) { Text("Suggest improvements") }
            } }
        }
    }
}
