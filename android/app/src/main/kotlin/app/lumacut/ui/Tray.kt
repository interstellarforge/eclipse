package app.lumacut.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.*
import app.lumacut.EditorViewModel.DragKind
import app.lumacut.EditorViewModel.DragPayload
import app.lumacut.core.*

/** Tabs whose items live in the one-row tray (drag them onto the timeline). The others open as a sheet. */
val TRAY_TABS = listOf(LeftTab.Media, LeftTab.Titles, LeftTab.Overlays, LeftTab.Transitions, LeftTab.Effects, LeftTab.Color, LeftTab.Templates)

private val TILE = 76.dp

/** One item high: a row of small tiles. Tap applies to the selection or playhead; press and hold, then drag onto the timeline. */
@UnstableApi
@Composable
fun Tray(vm: EditorViewModel, tab: LeftTab, modifier: Modifier = Modifier) {
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenMultipleDocuments()) { vm.importUris(it) }
    LazyRow(modifier.fillMaxWidth().height(96.dp).background(Pal.panel), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        when (tab) {
            LeftTab.Media -> {
                item { Tile("Import", null, { Icon(Icons.Filled.Add, null, tint = Pal.accent) }, onTap = { picker.launch(arrayOf("video/*", "image/*", "audio/*")) }) }
                items(vm.project.assets, key = { it.id }) { a ->
                    LaunchedEffect(a.id) { vm.ensureAssetMedia(a) }
                    val thumb = vm.thumbs[a.id]
                    Tile(a.label, DragPayload(DragKind.Media, a.id, a.label), {
                        if (thumb != null) Image(thumb.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) else Icon(if (a.hasVideo) Icons.Filled.Movie else Icons.Filled.GraphicEq, null, tint = Pal.dim)
                    }, vm = vm, onTap = { vm.addToTimeline(a) })
                }
            }
            LeftTab.Titles -> items(TitlePreset.entries.toList(), key = { it.name }) { p -> Tile(p.label, DragPayload(DragKind.Title, p.name, p.label), { PreviewImage(p, Modifier.fillMaxSize()) { Previews.title(p) } }, vm = vm, onTap = { vm.addTitle(p) }) }
            LeftTab.Overlays -> items(GeneratorKind.entries.toList(), key = { it.name }) { k -> Tile(k.title, DragPayload(DragKind.Overlay, k.name, k.title), { PreviewImage(k, Modifier.fillMaxSize()) { Previews.overlay(k) } }, vm = vm, onTap = { vm.addOverlay(k) }) }
            LeftTab.Transitions -> items(TransitionType.entries.toList(), key = { it.name }) { t -> Tile(t.title, DragPayload(DragKind.Transition, t.name, t.title), { Icon(Icons.Filled.CallMerge, null, tint = Pal.transition, modifier = Modifier.size(28.dp)) }, vm = vm, onTap = { vm.addTransitionTo(t) }) }
            LeftTab.Effects -> items(EffectType.entries.filter { it != EffectType.chromaKey && it != EffectType.removeBackground }, key = { it.name }) { t -> Tile(t.title, DragPayload(DragKind.Effect, t.name, t.title), { PreviewImage(t, Modifier.fillMaxSize()) { Previews.look(Look(), listOf(t)) } }, vm = vm, onTap = { vm.addEffect(t) }) }
            LeftTab.Color -> items(LookPresets.names, key = { it }) { n -> Tile(n, DragPayload(DragKind.Look, n, n), { PreviewImage(n, Modifier.fillMaxSize()) { Previews.look(LookPresets.preset(n)!!) } }, vm = vm, onTap = { vm.applyLook(n) }) }
            LeftTab.Templates -> items(Templates.all, key = { it.id }) { t -> Tile(t.name, null, { PreviewImage(t.id, Modifier.fillMaxSize()) { Previews.template(t) } }, onTap = { vm.applyTemplate(t) }) }
            else -> {}
        }
    }
}

@Composable
private fun Tile(label: String, payload: DragPayload?, picture: @Composable BoxScope.() -> Unit, vm: EditorViewModel? = null, onTap: () -> Unit) {
    var origin by remember { mutableStateOf(Offset.Zero) }
    val haptic = LocalHapticFeedback.current
    Column(Modifier.width(TILE).onGloballyPositioned { origin = it.positionInRoot() }
        .pointerInput(Unit) { detectTapGestures { onTap() } }
        .pointerInput(payload) {
            if (payload != null && vm != null) detectDragGesturesAfterLongPress(
                onDragStart = { o -> haptic.performHapticFeedback(HapticFeedbackType.LongPress); vm.dragStart(payload, origin + o) },
                onDragEnd = { vm.dragEnd() }, onDragCancel = { vm.dragCancel() }) { change, amount -> change.consume(); vm.dragMove(amount) }
        }, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().height(60.dp).clip(RoundedCornerShape(10.dp)).background(Pal.raised), Alignment.Center, content = picture)
        Text(label, color = Pal.text, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 3.dp))
    }
}

/** What follows the finger while dragging. */
@Composable
fun DragGhost(vm: EditorViewModel) {
    val d = vm.drag ?: return
    Box(Modifier.offset { IntOffset(vm.dragPos.x.toInt() - 60, vm.dragPos.y.toInt() - 150) }.clip(RoundedCornerShape(12.dp)).background(Pal.accent).padding(horizontal = 12.dp, vertical = 8.dp)) {
        Text(d.label, color = Color.White, fontSize = 12.sp, maxLines = 1)
    }
}
