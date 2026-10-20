package app.lumacut.ui

import android.net.Uri
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumacut.*
import app.lumacut.core.*
import kotlinx.coroutines.delay

/** Offline mode: watch the files one by one and mark "start here" / "end here". Only the ranges go to Claude. */
@UnstableApi
@Composable
fun SelectionDialog(vm: EditorViewModel, req: PendingSelection) {
    val ctx = LocalContext.current
    val assets = vm.project.assets.filter { it.hasVideo && !it.isStill && (req.assetIds.isEmpty() || it.id in req.assetIds) }
    var current by remember { mutableStateOf(assets.firstOrNull()?.id) }
    val included = remember { mutableStateListOf<Id>() }
    val ranges = remember { mutableStateMapOf<Id, List<LongRange>>() }
    fun rs(id: Id): List<LongRange> = ranges[id] ?: emptyList()
    var start by remember { mutableStateOf<Long?>(null) }
    var message by remember { mutableStateOf("") }
    val asset = assets.firstOrNull { it.id == current }
    val player = remember { ExoPlayer.Builder(ctx).build() }
    DisposableEffect(Unit) { onDispose { player.release() } }
    LaunchedEffect(current) { start = null; asset?.let { player.setMediaItem(MediaItem.fromUri(Uri.parse(it.url))); player.prepare() } }
    var pos by remember { mutableStateOf(0L) }
    var scrubbing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { while (true) { if (!scrubbing) pos = player.currentPosition; delay(50) } }
    val marked = ranges.values.sumOf { it.size }

    fun summary(): String {
        val lines = assets.filter { it.id in included }.map { a ->
            val r = (ranges[a.id] ?: emptyList()).sortedBy { it.first }
            "- ${a.label} (asset_id=${a.id}, length ${a.duration} ms): " + if (r.isEmpty()) "no parts marked: use the whole file if you need it" else r.joinToString(", ") { "${it.first}-${it.last + 1}" }
        }
        return "The user marked these parts in their videos (start_ms-end_ms in each source file). Use these ranges; files that are not listed are not to be used:\n" + lines.joinToString("\n")
    }

    Dialog({ vm.assistant.finishSelection(null) }, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Pal.background).statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Lock, null, tint = Pal.accent); Column(Modifier.padding(start = 10.dp)) { Text(req.reason, color = Pal.text, fontWeight = FontWeight.SemiBold); Text("Offline mode: Claude never sees these videos. It only receives the start and end times you mark.", color = Pal.dim, fontSize = 11.sp) }
            }
            LazyColumn(Modifier.heightIn(max = 150.dp).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 10.dp)) {
                items(assets, key = { it.id }) { a ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(if (a.id == current) Pal.accentSoft else Color0).clickable { current = a.id }.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(a.id in included, { if (it) included.add(a.id) else included.remove(a.id) })
                        Column { Text(a.label, color = Pal.text, fontSize = 13.sp, maxLines = 1); Text("${formatTime(a.duration)} · ${(ranges[a.id] ?: emptyList()).size} parts", color = Pal.dim, fontSize = 11.sp) }
                    }
                }
            }
            HorizontalDivider(color = Pal.stroke)
            if (asset != null) Column(Modifier.weight(1f).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f, fill = false).fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(10.dp)).background(androidx.compose.ui.graphics.Color.Black)) {
                    AndroidView({ PlayerView(it).apply { this.player = player; useController = false } }, Modifier.fillMaxSize())
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconBtn(Icons.Filled.FastRewind, "Back one frame", { player.pause(); player.seekTo((pos - 33).coerceAtLeast(0)) })
                    IconBtn(Icons.Filled.PlayArrow, "Play or pause", { if (player.isPlaying) player.pause() else player.play() })
                    IconBtn(Icons.Filled.FastForward, "Forward one frame", { player.pause(); player.seekTo((pos + 33).coerceAtMost(asset.duration)) })
                    // Scrubbing: the picture follows the thumb (nearest keyframe while dragging), exact frame on release.
                    Slider(pos.toFloat(), {
                        if (!scrubbing) { scrubbing = true; player.pause(); player.setSeekParameters(androidx.media3.exoplayer.SeekParameters.CLOSEST_SYNC) }
                        pos = it.toLong(); player.seekTo(pos)
                    }, onValueChangeFinished = { player.setSeekParameters(androidx.media3.exoplayer.SeekParameters.EXACT); player.seekTo(pos); scrubbing = false },
                        valueRange = 0f..maxOf(1f, asset.duration.toFloat()), modifier = Modifier.weight(1f))
                    Text("${formatTime(pos)} / ${formatTime(asset.duration)}", color = Pal.dim, fontSize = 11.sp)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button({ start = pos }) { Text("Start here") }
                    Button({
                        val s = start ?: return@Button; val lo = minOf(s, pos); val hi = maxOf(s, pos)
                        if (hi - lo >= 200) { ranges[asset.id] = rs(asset.id) + listOf(lo until hi); if (asset.id !in included) included.add(asset.id); message = "" } else message = "That part is too short: move the playhead further before pressing End here."
                        start = null
                    }, enabled = start != null) { Text("End here") }
                    OutlinedButton({ ranges[asset.id] = rs(asset.id) + listOf(0L until asset.duration); if (asset.id !in included) included.add(asset.id) }) { Text("Whole clip") }
                }
                start?.let { Text("Start ${formatTime(it)}: now press End here", color = Pal.accent, fontSize = 12.sp) }
                (ranges[asset.id] ?: emptyList()).forEachIndexed { i, r ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(Pal.raised).padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("${formatTime(r.first)} – ${formatTime(r.last + 1)}", color = Pal.text, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        IconBtn(Icons.Filled.PlayCircle, "Play this part", { player.seekTo(r.first); player.play() }, size = 36)
                        IconBtn(Icons.Filled.Delete, "Remove", { ranges[asset.id] = (ranges[asset.id] ?: emptyList()).filterIndexed { k, _ -> k != i } }, size = 36)
                    }
                }
            } else Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) { Text("There are no videos to mark yet.", color = Pal.dim) }
            HorizontalDivider(color = Pal.stroke)
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(message.ifEmpty { if (marked == 0) "Press Start here and End here to mark a part. Files with no marked part are left out unless you tick them." else "$marked part${if (marked == 1) "" else "s"} marked in ${included.size} file${if (included.size == 1) "" else "s"}." }, color = if (message.isEmpty()) Pal.dim else androidx.compose.ui.graphics.Color(0xFFFFA94D), fontSize = 11.sp, modifier = Modifier.weight(1f))
                TextButton({ vm.assistant.finishSelection(null) }) { Text("Cancel") }
                Button({ vm.assistant.finishSelection(summary()) }, enabled = included.isNotEmpty()) { Text("Done") }
            }
        }
    }
}

private val Color0 = androidx.compose.ui.graphics.Color.Transparent

/** Script modes: the drafted script, editable, with approve / request changes. */
@UnstableApi
@Composable
fun ScriptDialog(vm: EditorViewModel, req: PendingScript) {
    var title by remember(req) { mutableStateOf(req.draft.title) }
    var logline by remember(req) { mutableStateOf(req.draft.logline) }
    val beats = remember(req) { mutableStateListOf(*req.draft.beats.toTypedArray()) }
    var feedback by remember(req) { mutableStateOf("") }
    fun current() = ScriptDraft(title, logline, beats.toList(), req.draft.notes)
    fun render(d: ScriptDraft) = d.render { id -> vm.project.asset(id)?.label }
    Dialog({ vm.assistant.finishScript("CHANGES REQUESTED: the user closed the script window without approving. Ask what they want changed.") }, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Pal.background).statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Filled.MenuBook, null, tint = Pal.accent, modifier = Modifier.padding(top = 4.dp))
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    BasicField(title, { title = it }, 18, "Title"); BasicField(logline, { logline = it }, 13, "The idea in a sentence")
                    Text("${vm.assistant.scriptLevel.label} mode · about ${beats.sumOf { it.seconds }.toInt()} s", color = Pal.dim, fontSize = 11.sp)
                }
            }
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(beats.size) { i ->
                    val b = beats[i]
                    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(24.dp).clip(androidx.compose.foundation.shape.CircleShape).background(Pal.accent), Alignment.Center) { Text("${i + 1}", color = androidx.compose.ui.graphics.Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                            BasicField(b.title, { beats[i] = b.copy(title = it) }, 14, "Beat", Modifier.weight(1f).padding(horizontal = 8.dp))
                            IconBtn(Icons.Filled.ArrowUpward, "Move up", { if (i > 0) { val t = beats[i]; beats[i] = beats[i - 1]; beats[i - 1] = t } }, size = 32, enabled = i > 0)
                            IconBtn(Icons.Filled.ArrowDownward, "Move down", { if (i < beats.lastIndex) { val t = beats[i]; beats[i] = beats[i + 1]; beats[i + 1] = t } }, size = 32, enabled = i < beats.lastIndex)
                            IconBtn(Icons.Filled.Delete, "Remove", { beats.removeAt(i) }, size = 32)
                        }
                        BasicField(b.detail, { beats[i] = b.copy(detail = it) }, 12, "What this beat shows")
                        if (b.assetID != null) Text("${vm.project.asset(b.assetID)?.label ?: "?"}${if (b.startMs != null && b.endMs != null) " ${formatTime(b.startMs)}–${formatTime(b.endMs)}" else ""}", color = Pal.dim, fontSize = 11.sp, maxLines = 1)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("%.1f s".format(b.seconds), color = Pal.text, fontSize = 12.sp)
                            IconBtn(Icons.Filled.Remove, "Shorter", { beats[i] = b.copy(seconds = (b.seconds - 0.5).coerceAtLeast(0.5)) }, size = 30)
                            IconBtn(Icons.Filled.Add, "Longer", { beats[i] = b.copy(seconds = (b.seconds + 0.5).coerceAtMost(60.0)) }, size = 30)
                            ComboField("join", b.join, listOf("cut") + TransitionType.entries.map { it.name }, { beats[i] = b.copy(join = it) }, Modifier.weight(1f))
                            ComboField("sound", b.sound, listOf("keep", "mute", "keep 0.6, music lower", "music only", "keep, fade out", "keep, fade in"), { beats[i] = b.copy(sound = it) }, Modifier.weight(1f))
                        }
                        BasicField(b.text, { beats[i] = b.copy(text = it) }, 12, "Text on screen (optional)")
                    } }
                }
                item { OutlinedButton({ beats += ScriptBeat(title = "New beat") }) { Icon(Icons.Filled.Add, null); Spacer(Modifier.width(4.dp)); Text("Add a beat") } }
                if (req.draft.notes.isNotEmpty()) item { Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(10.dp)) { Text("Notes", color = Pal.dim, fontSize = 11.sp, fontWeight = FontWeight.SemiBold); Text(req.draft.notes, color = Pal.text, fontSize = 12.sp) } } }
            }
            HorizontalDivider(color = Pal.stroke)
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(feedback, { feedback = it }, placeholder = { Text("Or tell the Assistant what to change…") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton({ vm.assistant.finishScript("CHANGES REQUESTED: the user closed the script window without approving. Ask what they want changed.") }) { Text("Close") }
                    Spacer(Modifier.weight(1f))
                    OutlinedButton({ vm.assistant.finishScript("CHANGES REQUESTED: $feedback\nThe user's current version of the script:\n" + render(current())) }, enabled = feedback.isNotBlank()) { Text("Request changes") }
                    Button({ vm.assistant.finishScript("APPROVED. Build exactly this script with build_edit:\n" + render(current())) }, enabled = beats.isNotEmpty()) { Text("Approve and build") }
                }
            }
        }
    }
}

@Composable
private fun BasicField(value: String, onChange: (String) -> Unit, size: Int, hint: String, modifier: Modifier = Modifier) {
    androidx.compose.foundation.text.BasicTextField(value, onChange, modifier = modifier.fillMaxWidth(), textStyle = androidx.compose.ui.text.TextStyle(color = Pal.text, fontSize = size.sp, fontWeight = if (size >= 14) FontWeight.SemiBold else FontWeight.Normal),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(Pal.accent), decorationBox = { inner -> Box { if (value.isEmpty()) Text(hint, color = Pal.dim, fontSize = size.sp); inner() } })
}

/** A text field with a dropdown of ready-made choices: pick one or type your own. */
@Composable
fun ComboField(label: String, value: String, presets: List<String>, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Row(modifier.clip(RoundedCornerShape(8.dp)).background(Pal.panel).padding(start = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicField(value, onChange, 12, label, Modifier.weight(1f))
        Box { IconBtn(Icons.Filled.ArrowDropDown, "Choose", { open = true }, size = 30); DropdownMenu(open, { open = false }) { presets.forEach { p -> DropdownMenuItem(text = { Text(p) }, onClick = { open = false; onChange(p) }) } } }
    }
}

@UnstableApi
@Composable
fun ExportDialog(vm: EditorViewModel, onDismiss: () -> Unit) {
    val o = vm.exportOptions
    var name by remember { mutableStateOf(vm.projectName) }
    val p = vm.project
    val done = vm.exportResult != null && !vm.exporting
    fun opts(shortSide: Int = o.shortSide, fps: Int = o.fps, q: EditorViewModel.Quality = o.quality) = EditorViewModel.ExportOptions(name, shortSide, fps, q)
    fun sizeLabel(short: Int) = EditorViewModel.ExportOptions(name, short, o.fps, o.quality).size(p).let { "${it.first}×${it.second}" }
    val sizes = listOf(0 to "As edited", 720 to "720p", 1080 to "1080p", 1440 to "1440p", 2160 to "4K").filter { it.first == 0 || it.first <= 2160 }
    AlertDialog(onDismissRequest = { if (!vm.exporting) onDismiss() }, confirmButton = {
        when {
            done -> Row { TextButton({ vm.shareExported() }) { Text("Share") }; TextButton({ vm.openExported() }) { Text("Open") } }
            !vm.exporting -> TextButton({ vm.updateExportOptions(opts()); vm.exportResult = null; vm.export() }, enabled = name.isNotBlank()) { Text("Export") }
        }
    }, dismissButton = { if (!vm.exporting) TextButton(onDismiss) { Text(if (done) "Done" else "Cancel") } }, title = { Text(if (done) "Exported" else "Export video") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.verticalScroll(rememberScrollState())) {
            if (!vm.exporting && !done) {
                OutlinedTextField(name, { name = it }, singleLine = true, label = { Text("File name") }, suffix = { Text(".mp4") }, modifier = Modifier.fillMaxWidth())
                Text("Size", color = Pal.dim, fontSize = 12.sp)
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { sizes.forEach { (s, l) -> FilterChip(o.shortSide == s, { vm.updateExportOptions(opts(shortSide = s)) }, { Text(if (s == 0) l else "$l") }) } }
                Text(sizeLabel(o.shortSide), color = Pal.text, fontSize = 13.sp)
                Text("Frame rate", color = Pal.dim, fontSize = 12.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf(24, 30, 60).forEach { f -> FilterChip(o.fps == f, { vm.updateExportOptions(opts(fps = f)) }, { Text("$f fps") }) } }
                Text("Quality", color = Pal.dim, fontSize = 12.sp)
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { EditorViewModel.Quality.values().forEach { q -> FilterChip(o.quality == q, { vm.updateExportOptions(opts(q = q)) }, { Text(q.label) }) } }
                Text("About ${EditorViewModel.ExportOptions(name, o.shortSide, o.fps, o.quality).megabytes(p)} MB · ${formatTime(p.duration)} · H.264 with AAC sound · saved to Movies/Eclipse", color = Pal.dim, fontSize = 12.sp)
            }
            if (vm.exporting) {
                Text(vm.bakingNote ?: "Exporting ${vm.exportOptions.name}…", color = Pal.dim, fontSize = 13.sp)
                LinearProgressIndicator({ vm.exportProgress }, Modifier.fillMaxWidth(), color = Pal.accent); Text("${(vm.exportProgress * 100).toInt()} %", color = Pal.dim)
            }
            if (done) Text("Saved to Movies/Eclipse. Open it in your video app, or share it.", color = Pal.text)
        }
    })
}
