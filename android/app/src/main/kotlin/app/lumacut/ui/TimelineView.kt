package app.lumacut.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.EditorViewModel
import app.lumacut.RightTab
import app.lumacut.core.*
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

private val LANE = 58.dp
private val RULER = 26.dp
private val HEADER = 64.dp

@UnstableApi
@Composable
fun Timeline(vm: EditorViewModel, modifier: Modifier = Modifier) {
    val project = vm.project
    var ppm by remember { mutableStateOf(0.09f) }   // pixels per millisecond
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    var viewport by remember { mutableStateOf(0) }
    val widthPx = (maxOf(project.duration + 12_000, 20_000L) * ppm * density.density).toInt()
    val laneW = with(density) { widthPx.toDp() }
    val px = density.density

    SideEffect { vm.xToMs = { x -> ((x - vm.timelineRect.left + scroll.value) / (ppm * px)).toLong().coerceAtLeast(0) } }
    // Dragging an item near the left or right edge scrolls the timeline.
    LaunchedEffect(vm.drag != null) {
        while (vm.drag != null) {
            val r = vm.timelineRect; val x = vm.dragPos.x; val edge = 56 * px
            if (vm.dragPos.y in r.top..r.bottom) { if (x < r.left + edge) scroll.scrollBy(-14f) else if (x > r.right - edge) scroll.scrollBy(14f) }
            kotlinx.coroutines.delay(16)
        }
    }
    LaunchedEffect(vm.playheadMs, vm.isPlaying) {
        if (vm.isPlaying) {
            val x = (vm.playheadMs * ppm * px).toInt()
            if (x < scroll.value + 40 || x > scroll.value + viewport - 120) scroll.scrollTo((x - 120).coerceAtLeast(0))
        }
    }

    Column(modifier.background(Pal.panel)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconBtn(Icons.Filled.ContentCut, "Split at playhead", { vm.splitAtPlayhead() }, size = 38)
            IconBtn(Icons.Filled.ContentCopy, "Duplicate", { vm.duplicateSelection() }, enabled = vm.selection != null, size = 38)
            IconBtn(Icons.Filled.Delete, "Delete", { vm.deleteSelection() }, enabled = vm.selection != null || vm.selectedTransition != null, size = 38)
            IconBtn(Icons.Filled.Link, "Group clips", { vm.groupSelection() }, enabled = vm.selection != null, size = 38)
            IconBtn(Icons.Filled.AudioFile, "Detach audio", { vm.detachAudioSelection() }, enabled = vm.selection != null, size = 38)
            IconBtn(Icons.Filled.RestartAlt, "Reset clip", { vm.resetSelection() }, enabled = vm.selection != null, size = 38)
            Spacer(Modifier.weight(1f))
            IconBtn(Icons.Filled.ZoomOut, "Zoom out", { ppm = (ppm / 1.4f).coerceAtLeast(0.01f) }, size = 38)
            IconBtn(Icons.Filled.ZoomIn, "Zoom in", { ppm = (ppm * 1.4f).coerceAtMost(0.6f) }, size = 38)
            IconBtn(Icons.Filled.FitScreen, "Fit", { if (project.duration > 0) ppm = ((viewport / px - 40) / project.duration).coerceIn(0.01f, 0.6f) }, size = 38)
        }
        Row(Modifier.fillMaxSize()) {
            // Track headers
            Column(Modifier.width(HEADER).fillMaxHeight().verticalScroll(rememberScrollState(), enabled = false)) {
                Spacer(Modifier.height(RULER))
                project.tracks.forEachIndexed { i, t -> TrackHeader(vm, t, i) }
            }
            Box(Modifier.weight(1f).fillMaxHeight().onSizeChanged { viewport = it.width }.onGloballyPositioned { vm.timelineRect = it.boundsInRoot() }) {
                Box(Modifier.fillMaxSize().horizontalScroll(scroll)) {
                    Box(Modifier.width(laneW).fillMaxHeight()
                        .pointerInput(ppm) { detectTapGestures { o -> vm.seek((o.x / (ppm * px)).toLong()); vm.selectClip(null) } }) {
                        // Ruler
                        Canvas(Modifier.width(laneW).height(RULER).pointerInput(ppm) {
                            detectDragGestures(onDragStart = { vm.pausePlayback(); vm.seek((it.x / (ppm * px)).toLong()) }) { change, _ -> vm.seek((change.position.x / (ppm * px)).toLong()) }
                        }) {
                            val step = when { ppm * 1000 >= 160 -> 500; ppm * 1000 >= 80 -> 1000; ppm * 1000 >= 36 -> 2000; ppm * 1000 >= 16 -> 5000; else -> 10000 }
                            var t = 0L
                            val paint = android.graphics.Paint().apply { color = 0x99FFFFFF.toInt(); textSize = 10.sp.toPx(); isAntiAlias = true }
                            while (t * ppm * px < size.width) {
                                val x = t * ppm * px
                                drawLine(Color.White.copy(alpha = 0.35f), Offset(x, size.height - 8.dp.toPx()), Offset(x, size.height), 1f)
                                drawContext.canvas.nativeCanvas.drawText("%d:%02d".format(t / 60000, (t / 1000) % 60) + if (t % 1000 != 0L) ".5" else "", x + 3.dp.toPx(), 11.dp.toPx(), paint)
                                t += step
                            }
                        }
                        Column(Modifier.padding(top = RULER)) {
                            project.tracks.forEach { track ->
                                Box(Modifier.height(LANE).width(laneW).padding(vertical = 2.dp)) {
                                    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha = 0.04f)))
                                    track.clips.forEach { clip -> ClipItem(vm, track, clip, ppm) }
                                    project.transitions.forEach { tr ->
                                        val from = track.clips.firstOrNull { it.id == tr.fromClip }; val to = track.clips.firstOrNull { it.id == tr.toClip }
                                        if (from != null && to != null) TransitionBand(vm, tr, to.start, from.end - to.start, ppm)
                                    }
                                }
                            }
                        }
                        (vm.dropTarget as? EditorViewModel.DropTarget.AtTime)?.let { t -> Box(Modifier.offset(x = (t.ms * ppm).dp - 1.dp).width(3.dp).fillMaxHeight().background(Color(0xFFFFD60A))) }
                        // Playhead
                        val x = vm.playheadMs * ppm
                        Box(Modifier.offset(x = x.dp - 1.dp).width(2.dp).fillMaxHeight().background(Pal.accent))
                        Box(Modifier.offset(x = x.dp - 6.dp).size(12.dp).clip(androidx.compose.foundation.shape.CircleShape).background(Pal.accent))
                    }
                }
                if (project.tracks.isEmpty()) Text("Add a clip from Media to start", color = Pal.dim, fontSize = 13.sp, modifier = Modifier.align(Alignment.Center))
            }
        }
    }
}

@Composable
private fun TrackHeader(vm: EditorViewModel, track: Track, index: Int) {
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.height(LANE).padding(vertical = 2.dp, horizontal = 3.dp)) {
        Card(Modifier.fillMaxSize().clickable { menu = true }) {
            Row(Modifier.fillMaxSize().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(when (track.kind) { TrackKind.video -> Icons.Filled.Movie; TrackKind.audio -> Icons.Filled.MusicNote; TrackKind.text -> Icons.Filled.TextFields }, null, tint = Pal.dim, modifier = Modifier.size(16.dp))
                Column(Modifier.padding(start = 3.dp)) {
                    Text(track.name ?: "${track.kind.name.replaceFirstChar { it.uppercase() }} ${vm.project.tracks.take(index + 1).count { it.kind == track.kind }}", color = Pal.text, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row {
                        if (track.locked) Icon(Icons.Filled.Lock, null, tint = Pal.accent, modifier = Modifier.size(12.dp))
                        if (track.muted) Icon(Icons.Filled.VolumeOff, null, tint = Pal.accent, modifier = Modifier.size(12.dp))
                        if (track.hidden) Icon(Icons.Filled.VisibilityOff, null, tint = Pal.accent, modifier = Modifier.size(12.dp))
                        if (track.duck) Icon(Icons.Filled.TrendingDown, null, tint = Pal.accent, modifier = Modifier.size(12.dp))
                    }
                }
            }
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem(text = { Text(if (track.locked) "Unlock track" else "Lock track") }, onClick = { menu = false; vm.run { apply(Command.SetTrackLocked(track.id, !track.locked)) } })
            if (track.kind == TrackKind.audio) {
                DropdownMenuItem(text = { Text(if (track.muted) "Unmute track" else "Mute track") }, onClick = { menu = false; vm.run { apply(Command.SetTrackFlags(track.id, !track.muted, track.hidden)) } })
                DropdownMenuItem(text = { Text(if (track.duck) "Ducking off" else "Duck under speech and clip sound") }, onClick = { menu = false; vm.run { apply(Command.SetTrackDuck(track.id, !track.duck)) } })
            } else DropdownMenuItem(text = { Text(if (track.hidden) "Show track" else "Hide track") }, onClick = { menu = false; vm.run { apply(Command.SetTrackFlags(track.id, track.muted, !track.hidden)) } })
            DropdownMenuItem(text = { Text("Remove track and its clips") }, onClick = { menu = false; vm.run { apply(Command.RemoveTrack(track.id)) } })
        }
    }
}

@UnstableApi
@Composable
private fun ClipItem(vm: EditorViewModel, track: Track, clip: Clip, ppm: Float) {
    val asset = vm.project.asset(clip.assetID)
    val selected = vm.selection == clip.id || clip.id in vm.multiSelection
    val density = LocalDensity.current.density
    var moveMs by remember(clip) { mutableStateOf(0L) }
    var leftMs by remember(clip) { mutableStateOf(0L) }
    var rightMs by remember(clip) { mutableStateOf(0L) }
    var menu by remember { mutableStateOf(false) }
    val start = clip.start + moveMs + leftMs
    val duration = (clip.duration - leftMs + rightMs).coerceAtLeast(100)
    val color = when { clip.generator != null -> Pal.overlay; track.kind == TrackKind.audio -> Pal.audio; track.kind == TrackKind.text -> Pal.title; else -> Pal.video }
    val wDp = (duration * ppm).dp.coerceAtLeast(6.dp)
    val locked = track.locked

    fun snap(ms: Long): Long {
        val edges = vm.project.allClips.filter { it.id != clip.id }.flatMap { listOf(it.start, it.end) } + vm.playheadMs + 0L
        val tol = (10 / (ppm * density)).toLong()
        return edges.minByOrNull { abs(it - ms) }?.takeIf { abs(it - ms) <= tol } ?: ms
    }

    LaunchedEffect(asset?.id) { if (asset != null && track.kind == TrackKind.video && clip.generator == null) vm.ensureFilmstrip(asset) }

    DisposableEffect(clip.id) { onDispose { vm.clipBounds.remove(clip.id) } }
    val target = vm.dropTarget
    val hot = target is EditorViewModel.DropTarget.OnClip && target.id == clip.id
    val joinHere = target is EditorViewModel.DropTarget.AfterClip && target.id == clip.id
    Box(Modifier.offset(x = (start * ppm).dp).width(wDp).fillMaxHeight().onGloballyPositioned { vm.clipBounds[clip.id] = it.boundsInRoot() }.clip(RoundedCornerShape(8.dp)).background(color.copy(alpha = 0.85f))
        .border(if (hot) BorderStroke(3.dp, Color(0xFFFFD60A)) else if (selected) BorderStroke(2.dp, Color.White) else BorderStroke(0.dp, Color.Transparent), RoundedCornerShape(8.dp))
        .pointerInput(clip.id, selected) { detectTapGestures { if (selected && vm.selection == clip.id) menu = true else vm.selectClip(clip.id) } }
        .pointerInput(clip.id, ppm, locked) {
            if (!locked) detectDragGesturesAfterLongPress(onDragStart = { vm.selectClip(clip.id) },
                onDragEnd = {
                    val target = snap(clip.start + moveMs).let { s -> val e = snap(clip.start + moveMs + clip.duration) - clip.duration; if (abs(s - (clip.start + moveMs)) <= abs(e - (clip.start + moveMs))) s else e }
                    val m = moveMs; moveMs = 0
                    if (m != 0L) vm.run { apply(Command.MoveClip(clip.id, maxOf(0L, target))) }
                }, onDragCancel = { moveMs = 0 }) { change, drag -> change.consume(); moveMs += (drag.x / (ppm * density)).toLong().let { if (it == 0L) 0 else it } }
        }) {
        // Content
        val strip = vm.filmstrips[clip.assetID]
        if (track.kind == TrackKind.video && clip.generator == null && !strip.isNullOrEmpty()) {
            Row(Modifier.fillMaxSize().alpha(0.8f)) { val n = strip.size; strip.forEach { b -> androidx.compose.foundation.Image(b.asImageBitmap(), null, Modifier.weight(1f).fillMaxHeight(), contentScale = androidx.compose.ui.layout.ContentScale.Crop) } }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent))))
        }
        val levels = vm.waveforms[clip.assetID]
        if (levels != null && levels.isNotEmpty() && asset?.hasAudio == true && (track.kind == TrackKind.audio)) Waveform(levels, clip, asset)
        Text(clip.text ?: clip.generator?.title ?: asset?.label ?: "", color = Color.White, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 10.dp, top = 3.dp, end = 4.dp))
        if (clip.speed != 1.0) Text("${"%.2g".format(clip.speed)}x", color = Color.White, fontSize = 9.sp, modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp))
        if (clip.groupID != null) Icon(Icons.Filled.Link, null, tint = Color.White, modifier = Modifier.align(Alignment.BottomStart).padding(3.dp).size(11.dp))
        if (locked) Icon(Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.align(Alignment.TopEnd).padding(3.dp).size(11.dp))
        if (joinHere) Box(Modifier.align(Alignment.CenterEnd).width(8.dp).fillMaxHeight().background(Color(0xFFFFD60A)))
        // Trim handles
        if (selected && !locked) {
            val commit = {
                val l = leftMs; val r = rightMs; leftMs = 0; rightMs = 0
                if (l != 0L || r != 0L) vm.run { apply(Command.TrimClip(clip.id, clip.sourceIn + (l * clip.speed).roundToLong(), clip.duration - l + r, clip.start + l)) }
            }
            val maxLeft = if (asset != null && !asset.isStill) -(clip.sourceIn / clip.speed).toLong() else -clip.start
            val maxRight = if (asset != null && !asset.isStill) ((asset.duration - clip.sourceIn - clip.sourceLength) / clip.speed).toLong() else 60_000L
            TrimHandle(Modifier.align(Alignment.CenterStart), onEnd = commit) { dx -> leftMs = (leftMs + (dx / (ppm * density)).toLong()).coerceIn(maxLeft.coerceAtLeast(-clip.start), clip.duration - 100) }
            TrimHandle(Modifier.align(Alignment.CenterEnd), onEnd = commit) { dx -> rightMs = (rightMs + (dx / (ppm * density)).toLong()).coerceIn(-clip.duration + 100, maxRight) }
        }
        DropdownMenu(menu, { menu = false }) { ClipMenu(vm, clip, track) { menu = false } }
    }
}

@Composable
private fun TrimHandle(modifier: Modifier, onEnd: () -> Unit, onDrag: (Float) -> Unit) {
    Box(modifier.width(14.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.35f)).pointerInput(Unit) { detectHorizontalDragGestures(onDragEnd = onEnd, onDragCancel = onEnd) { change, dx -> change.consume(); onDrag(dx) } }, Alignment.Center) {
        Box(Modifier.width(3.dp).height(20.dp).clip(RoundedCornerShape(2.dp)).background(Color.White))
    }
}

@UnstableApi
@Composable
private fun TransitionBand(vm: EditorViewModel, tr: Transition, startMs: Long, lenMs: Long, ppm: Float) {
    val selected = vm.selectedTransition == tr.id
    Box(Modifier.offset(x = (startMs * ppm).dp).width((lenMs * ppm).dp.coerceAtLeast(14.dp)).fillMaxHeight().clip(RoundedCornerShape(6.dp)).background(Pal.transition.copy(alpha = 0.85f))
        .border(BorderStroke(if (selected) 2.dp else 1.dp, if (selected) Color.White else Pal.transition), RoundedCornerShape(6.dp))
        .clickable { vm.selectTransition(tr.id) }, Alignment.Center) {
        Icon(Icons.Filled.CallMerge, tr.type.title, tint = Color.White, modifier = Modifier.size(14.dp))
    }
}

@Composable
private fun Waveform(levels: FloatArray, clip: Clip, asset: Asset) {
    androidx.compose.foundation.Canvas(Modifier.fillMaxSize().padding(vertical = 8.dp)) {
        val from = (clip.sourceIn.toDouble() / asset.duration * levels.size).toInt().coerceIn(0, levels.size - 1)
        val to = ((clip.sourceIn + clip.sourceLength).toDouble() / asset.duration * levels.size).toInt().coerceIn(from + 1, levels.size)
        val bars = (size.width / 3.dp.toPx()).toInt().coerceAtLeast(1)
        val volume = clip.volume.toFloat().coerceIn(0f, 2f)
        for (i in 0 until bars) {
            val a = from + (to - from) * i / bars; val b = maxOf(a + 1, from + (to - from) * (i + 1) / bars)
            var peak = 0f; for (k in a until minOf(b, levels.size)) peak = maxOf(peak, levels[k])
            val t = i.toFloat() / bars * clip.duration
            var g = volume
            if (clip.fadeIn > 0 && t < clip.fadeIn) g *= t / clip.fadeIn
            if (clip.fadeOut > 0 && t > clip.duration - clip.fadeOut) g *= (clip.duration - t) / clip.fadeOut
            val h = maxOf(2f, peak * g * size.height)
            drawRect(Color.White.copy(alpha = 0.75f), Offset(i * size.width / bars, (size.height - h) / 2), Size(maxOf(1f, size.width / bars - 1.5f), h))
        }
    }
}

@UnstableApi
@Composable
fun ClipMenu(vm: EditorViewModel, clip: Clip, track: Track, close: () -> Unit) {
    @Composable fun item(label: String, f: () -> Unit) = DropdownMenuItem(text = { Text(label) }, onClick = { close(); f() })
    item("Mention in Assistant") {
        val name = vm.project.asset(clip.assetID)?.label ?: clip.text ?: clip.generator?.title ?: "clip"
        val src = if (clip.assetID == null) "" else ", source ${formatTime(clip.sourceIn)}–${formatTime(clip.sourceIn + clip.sourceLength)}"
        vm.assistant.mention("[clip \"$name\" clip_id=${clip.id}, timeline ${formatTime(clip.start)}–${formatTime(clip.end)}$src]"); vm.showAssistant = true
    }
    item("Edit (adjust)") { vm.showInspector = true }
    item("Split at playhead") { vm.selectClip(clip.id); vm.splitAtPlayhead() }
    item("Duplicate") { vm.selectClip(clip.id); vm.duplicateSelection() }
    item("Delete") { vm.selectClip(clip.id); vm.deleteSelection() }
    item("Delete and close the gap") { vm.selectClip(clip.id); vm.deleteSelection(ripple = true) }
    if (track.kind == TrackKind.video && vm.project.asset(clip.assetID)?.hasAudio == true && !clip.muted) item("Detach audio") { vm.selectClip(clip.id); vm.detachAudioSelection() }
    if (track.kind == TrackKind.video && vm.project.asset(clip.assetID)?.hasAudio == true) item(if (clip.muted) "Unmute clip sound" else "Mute clip sound") { vm.run { apply(Command.SetMuted(clip.id, !clip.muted)) } }
    item(if (clip.groupID == null) "Group (select more first)" else "Ungroup") { vm.selectClip(clip.id); if (clip.groupID == null) vm.groupSelection() else vm.ungroupSelection() }
    item("Reset clip") { vm.selectClip(clip.id); vm.resetSelection() }
}
