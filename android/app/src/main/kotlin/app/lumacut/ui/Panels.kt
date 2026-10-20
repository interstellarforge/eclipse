package app.lumacut.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.*
import app.lumacut.core.*

enum class ViewMode(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val columns: Int) {
    Small("Small previews", Icons.Filled.GridView, 3), Large("Large previews", Icons.Filled.ViewModule, 2), List("List", Icons.Filled.ViewList, 1), Detail("Details", Icons.Filled.ViewAgenda, 1);
    val row get() = this == List || this == Detail
}

@UnstableApi
@Composable
fun LeftPanel(vm: EditorViewModel, modifier: Modifier = Modifier) {
    Column(modifier.background(Pal.panel)) {
        when (vm.leftTab) {
            LeftTab.Media -> MediaPanel(vm)
            LeftTab.Files -> FilesPanel(vm)
            LeftTab.Titles -> TitlesPanel(vm)
            LeftTab.Overlays -> OverlaysPanel(vm)
            LeftTab.Audio -> AudioPanel(vm)
            LeftTab.Transitions -> TransitionsPanel(vm)
            LeftTab.Effects -> EffectsPanel(vm)
            LeftTab.Color -> ColorPanel(vm)
            LeftTab.Templates -> TemplatesPanel(vm)
            LeftTab.Smart -> SmartPanel(vm)
        }
    }
}

@Composable
fun ViewModeMenu(mode: ViewMode, onChange: (ViewMode) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconBtn(mode.icon, "Change how items are shown", { open = true })
        DropdownMenu(open, { open = false }) { ViewMode.entries.forEach { m -> DropdownMenuItem(text = { Text(m.label) }, leadingIcon = { Icon(m.icon, null) }, onClick = { open = false; onChange(m) }) } }
    }
}

enum class MediaFilter(val label: String) { All("All"), Favorites("Favorites"), Videos("Videos"), Photos("Photos"), Audio("Audio"), Unused("Unused") }

@UnstableApi
@Composable
fun MediaPanel(vm: EditorViewModel) {
    var mode by remember { mutableStateOf(ViewMode.Large) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(MediaFilter.All) }
    val used = vm.project.allClips.mapNotNull { it.assetID }.toSet()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> vm.importUris(uris) }
    val assets = vm.project.assets.filter { a ->
        (query.isBlank() || a.label.contains(query, true)) && when (filter) {
            MediaFilter.All -> true; MediaFilter.Favorites -> a.favorite; MediaFilter.Videos -> a.hasVideo && !a.isStill; MediaFilter.Photos -> a.isStill
            MediaFilter.Audio -> !a.hasVideo; MediaFilter.Unused -> a.id !in used
        }
    }
    PanelHeader("Media", "${vm.project.assets.size} items") {
        ViewModeMenu(mode) { mode = it }
        Button({ picker.launch(arrayOf("video/*", "audio/*", "image/*")) }, contentPadding = PaddingValues(horizontal = 12.dp)) { Icon(Icons.Filled.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Import") }
    }
    OutlinedTextField(query, { query = it }, placeholder = { Text("Search media…") }, singleLine = true, leadingIcon = { Icon(Icons.Filled.Search, null) },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp), shape = RoundedCornerShape(12.dp))
    androidx.compose.foundation.lazy.LazyRow(Modifier.padding(vertical = 8.dp), contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items(MediaFilter.entries) { f -> Pill(f.label, filter == f) { filter = f } }
    }
    ImportBar(vm)
    if (assets.isEmpty()) Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) { Text(if (vm.project.assets.isEmpty()) "Import videos, photos and audio to begin." else "Nothing matches.", color = Pal.dim) }
    else LazyVerticalGrid(GridCells.Fixed(mode.columns), Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(assets, key = { it.id }) { a -> AssetCard(vm, a, mode, a.id in used) }
    }
}

@Composable
fun ImportBar(vm: EditorViewModel) {
    val s = vm.importState
    if (s.total > 0 || s.failures.isNotEmpty()) Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
        Column(Modifier.padding(10.dp)) {
            if (s.total > 0) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Importing ${minOf(s.done + 1, s.total)} of ${s.total}", color = Pal.text, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    TextButton({ vm.cancelImports() }) { Text("Cancel") }
                }
                LinearProgressIndicator({ s.done.toFloat() / maxOf(1, s.total) }, Modifier.fillMaxWidth(), color = Pal.accent)
                Text(s.current, color = Pal.dim, fontSize = 11.sp, maxLines = 1)
            }
            if (s.failures.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text("${s.failures.size} could not be imported", color = Color(0xFFFFA94D), fontSize = 12.sp, modifier = Modifier.weight(1f)); TextButton({ s.failures.clear() }) { Text("Dismiss") } }
                s.failures.take(3).forEach { Text(it, color = Pal.danger, fontSize = 11.sp, maxLines = 2) }
            }
        }
    }
}

@UnstableApi
@Composable
fun AssetCard(vm: EditorViewModel, asset: Asset, mode: ViewMode, used: Boolean) {
    var menu by remember { mutableStateOf(false) }
    var rename by remember { mutableStateOf(false) }
    LaunchedEffect(asset.id) { vm.ensureAssetMedia(asset) }
    val thumb = vm.thumbs[asset.id]
    val kind = if (asset.isStill) "Photo" else if (asset.hasVideo) "Video" else "Audio"
    @Composable fun picture(mod: Modifier) {
        Box(mod.aspectRatio(16f / 9).clip(RoundedCornerShape(10.dp)).background(Pal.panel), Alignment.Center) {
            if (thumb != null) Image(thumb.asImageBitmap(), null, Modifier.fillMaxSize().alpha(if (used) 0.65f else 1f), contentScale = ContentScale.Crop)
            else Icon(if (asset.hasVideo) Icons.Filled.Movie else Icons.Filled.GraphicEq, null, tint = Pal.dim)
            if (!asset.isStill) Text(formatTime(asset.duration), color = Color.White, fontSize = 10.sp, modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 1.dp))
            Row(Modifier.align(Alignment.TopStart).padding(4.dp)) {
                if (asset.favorite) Icon(Icons.Filled.Star, null, tint = Color(0xFFFFD60A), modifier = Modifier.size(14.dp))
                if (used) Icon(Icons.Filled.CheckCircle, null, tint = Pal.accent, modifier = Modifier.size(14.dp))
            }
        }
    }
    Box {
        val click = Modifier.clickable { vm.addToTimeline(asset) }.let { m -> m }
        if (mode.row) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Pal.raised).clickable { menu = true }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) {
            picture(Modifier.width(if (mode == ViewMode.Detail) 120.dp else 72.dp))
            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                Text(asset.label, color = Pal.text, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
                Text("$kind · ${formatTime(asset.duration)}", color = Pal.dim, fontSize = 11.sp)
                if (mode == ViewMode.Detail) Text(if (used) "Used in the timeline" else "Not used yet", color = if (used) Pal.accent else Pal.dim, fontSize = 11.sp)
            }
            IconBtn(Icons.Filled.AddCircle, "Add to timeline", { vm.addToTimeline(asset) }, tint = Pal.accent)
        } else Column(Modifier.clickable { menu = true }) {
            picture(Modifier.fillMaxWidth())
            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(asset.label, color = Pal.text, fontSize = if (mode == ViewMode.Small) 10.sp else 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Icon(Icons.Filled.AddCircle, "Add to timeline", tint = Pal.accent, modifier = Modifier.size(22.dp).clickable { vm.addToTimeline(asset) })
            }
        }
        DropdownMenu(menu, { menu = false }) {
            @Composable fun item(l: String, f: () -> Unit) = DropdownMenuItem(text = { Text(l) }, onClick = { menu = false; f() })
            item("Add to timeline") { vm.addToTimeline(asset) }
            item("Mention in Assistant") { vm.assistant.mention("[file \"${asset.label}\" asset_id=${asset.id}, ${formatTime(asset.duration)} long]"); vm.showAssistant = true }
            item(if (asset.favorite) "Remove from favorites" else "Add to favorites") { vm.run { apply(Command.SetAssetFavorite(asset.id, !asset.favorite)) } }
            item("Rename…") { rename = true }
            item("Remove from library") { vm.run { apply(Command.RemoveAsset(asset.id)) } }
        }
        if (rename) RenameDialog(asset.label, { rename = false }) { n -> rename = false; vm.run { apply(Command.RenameAsset(asset.id, n)) } }
    }
}

@Composable
fun RenameDialog(current: String, onDismiss: () -> Unit, onOk: (String) -> Unit) {
    var text by remember { mutableStateOf(current) }
    AlertDialog(onDismissRequest = onDismiss, confirmButton = { TextButton({ onOk(text) }) { Text("OK") } }, dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
        title = { Text("Rename") }, text = { OutlinedTextField(text, { text = it }, singleLine = true) })
}

