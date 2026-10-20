package app.lumacut.ui

import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.documentfile.provider.DocumentFile
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumacut.EditorViewModel
import app.lumacut.ai.Workspace
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private class FileRowData(val file: DocumentFile, val depth: Int, val root: Workspace.Root?) { val key: String get() = file.uri.toString() }
enum class FileSort(val label: String) { Name("Name"), Kind("Kind"), Size("Size"), Date("Date modified") }

/** The Files tab: folders from the device as a tree, with filter, sort, multi-select, a preview and import. */
@UnstableApi
@Composable
fun FilesPanel(vm: EditorViewModel) {
    val ctx = LocalContext.current
    val ws = vm.assistant.workspace
    val roots = vm.assistant.roots
    val opener = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> if (uri != null) vm.assistant.addRoot(uri) }
    val expanded = remember { mutableStateListOf<String>() }
    val selected = remember { mutableStateListOf<String>() }
    var filter by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf("All") }
    var sort by remember { mutableStateOf(FileSort.Name) }
    var ascending by remember { mutableStateOf(true) }
    var sortMenu by remember { mutableStateOf(false) }

    fun sorted(list: List<DocumentFile>): List<DocumentFile> {
        val folders = list.filter { it.isDirectory }.sortedBy { it.name?.lowercase() }
        val files = list.filter { !it.isDirectory }.let { l -> when (sort) { FileSort.Name -> l.sortedBy { it.name?.lowercase() }; FileSort.Kind -> l.sortedWith(compareBy({ ws.kind(it) ?: "z" }, { it.name?.lowercase() })); FileSort.Size -> l.sortedBy { it.length() }; FileSort.Date -> l.sortedBy { it.lastModified() } } }
        return folders + if (ascending) files else files.reversed()
    }
    fun shown(f: DocumentFile) = kind == "All" || ws.kind(f) == kind.lowercase().let { if (it == "photos") "image" else if (it == "video") "video" else it }

    val rows by produceState(emptyList<FileRowData>(), roots, expanded.toList(), filter, kind, sort, ascending) {
        value = withContext(Dispatchers.IO) {
            val out = mutableListOf<FileRowData>()
            val needle = filter.trim().lowercase()
            if (needle.isNotEmpty()) { roots.forEach { r -> ws.rootFile(r)?.let { root -> ws.mediaFiles(root, 2000).filter { (it.name ?: "").lowercase().contains(needle) && shown(it) }.forEach { out += FileRowData(it, 0, null) } } } }
            else {
                fun walk(d: DocumentFile, depth: Int) { for (c in sorted(ws.children(d))) { if (c.isDirectory) { out += FileRowData(c, depth, null); if (c.uri.toString() in expanded) walk(c, depth + 1) } else if (shown(c)) out += FileRowData(c, depth, null) } }
                roots.forEach { r -> ws.rootFile(r)?.let { root -> out += FileRowData(root, 0, r); if (root.uri.toString() in expanded) walk(root, 1) } }
            }
            out
        }
    }

    var previewHeight by remember { mutableStateOf(230.dp) }
    PanelHeader("Files") { Button({ opener.launch(null) }) { Icon(Icons.Filled.CreateNewFolder, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Open") } }
    Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(filter, { filter = it }, placeholder = { Text("Filter files…") }, singleLine = true, leadingIcon = { Icon(Icons.Filled.Search, null) }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(12.dp))
        Box { IconBtn(Icons.Filled.SwapVert, "Sort", { sortMenu = true }); DropdownMenu(sortMenu, { sortMenu = false }) {
            FileSort.entries.forEach { s -> DropdownMenuItem(text = { Text(s.label + if (s == sort) " ✓" else "") }, onClick = { sort = s; sortMenu = false }) }
            DropdownMenuItem(text = { Text(if (ascending) "Ascending ✓" else "Ascending") }, onClick = { ascending = true; sortMenu = false })
            DropdownMenuItem(text = { Text(if (ascending) "Descending" else "Descending ✓") }, onClick = { ascending = false; sortMenu = false })
        } }
        IconBtn(Icons.Filled.SelectAll, "Select all files shown", { selected.clear(); selected.addAll(rows.filter { !it.file.isDirectory }.map { it.key }) })
    }
    androidx.compose.foundation.layout.FlowRow(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("All", "Video", "Photos", "Audio").forEach { k -> Pill(k, kind == k) { kind = k } } }

    if (roots.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(Icons.Filled.Folder, null, tint = Pal.dim, modifier = Modifier.size(40.dp)); Text("Open a folder to browse it here.", color = Pal.dim, modifier = Modifier.padding(8.dp))
            Button({ opener.launch(null) }) { Text("Open folder…") }
        }
        return
    }
    LazyColumn(Modifier.heightIn(max = 380.dp).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)) {
        items(rows, key = { it.key }) { row -> FileRow(vm, ws, row, expanded, selected, kind, rows) }
    }
    HorizontalDivider(color = Pal.stroke)
    Box(Modifier.fillMaxWidth().height(24.dp).pointerInput(Unit) { detectTapGestures { } }.draggableHandle { d -> previewHeight = (previewHeight - d.dp).coerceIn(100.dp, 460.dp) }, Alignment.Center) { Box(Modifier.width(40.dp).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Pal.hover)) }
    FilePreview(vm, ws, rows.filter { it.key in selected }, Modifier.fillMaxWidth().height(previewHeight))
}

private fun Modifier.draggableHandle(onDelta: (Float) -> Unit): Modifier = this.pointerInput(Unit) { detectVerticalDragGestures { change, dy -> change.consume(); onDelta(dy / density) } }

@Composable
private fun FileRow(vm: EditorViewModel, ws: Workspace, row: FileRowData, expanded: MutableList<String>, selected: MutableList<String>, kindFilter: String, all: List<FileRowData>) {
    val f = row.file; val key = row.key; val isDir = f.isDirectory; val kind = ws.kind(f)
    var menu by remember { mutableStateOf(false) }
    val sel = key in selected
    val counts by produceState<String?>(null, key, kindFilter) { if (isDir) value = withContext(Dispatchers.IO) { val m = ws.mediaFiles(f, 5000); val items = ws.children(f).size
        when (kindFilter) { "Video" -> "${m.count { ws.kind(it) == "video" }} videos"; "Photos" -> "${m.count { ws.kind(it) == "image" }} photos"; "Audio" -> "${m.count { ws.kind(it) == "audio" }} audio files"; else -> "$items items · ${m.size} media files" } } }
    Box {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(if (sel) Pal.accentSoft else androidx.compose.ui.graphics.Color.Transparent)
            .combinedClickable(onClick = { if (selected.isNotEmpty()) { if (sel) selected.remove(key) else selected.add(key) } else if (isDir) { if (key in expanded) expanded.remove(key) else expanded.add(key) } else { selected.clear(); selected.add(key) } },
                onLongClick = { if (sel) selected.remove(key) else selected.add(key); }, onDoubleClick = { if (!isDir && kind != null) vm.importUris(listOf(f.uri)) })
            .padding(start = (row.depth * 14 + 4).dp, top = 5.dp, bottom = 5.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (isDir) (if (key in expanded) Icons.Filled.FolderOpen else Icons.Filled.Folder) else when (kind) { "video" -> Icons.Filled.Movie; "audio" -> Icons.Filled.MusicNote; "image" -> Icons.Filled.Image; else -> Icons.Filled.InsertDriveFile },
                null, tint = if (isDir) Pal.accent else if (kind == null) Pal.dim.copy(alpha = 0.5f) else Pal.text, modifier = Modifier.size(22.dp))
            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                Text(f.name ?: "?", color = if (kind == null && !isDir) Pal.dim else Pal.text, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (isDir) counts?.let { Text(it, color = Pal.dim, fontSize = 10.5.sp) } else Text(android.text.format.Formatter.formatShortFileSize(LocalContext.current, f.length()), color = Pal.dim, fontSize = 10.5.sp)
            }
            if (!isDir && kind != null) IconBtn(Icons.Filled.AddCircle, "Import", { vm.importUris(listOf(f.uri)) }, tint = Pal.accent, size = 36)
            IconBtn(Icons.Filled.MoreVert, "More", { menu = true }, size = 36)
        }
        DropdownMenu(menu, { menu = false }) {
            val targets = if (sel) all.filter { it.key in selected }.map { it.file } else listOf(f)
            val media = targets.filter { !it.isDirectory && ws.kind(it) != null }
            if (media.isNotEmpty()) DropdownMenuItem(text = { Text("Import ${if (media.size == 1) "this file" else "${media.size} files"}") }, onClick = { menu = false; vm.importUris(media.map { it.uri }) })
            targets.filter { it.isDirectory }.take(1).forEach { d ->
                DropdownMenuItem(text = { Text("Import all media in this folder") }, onClick = { menu = false; vm.importUris(ws.mediaFiles(d).map { it.uri }) })
                DropdownMenuItem(text = { Text("Ask the Assistant what is in here") }, onClick = { menu = false; val path = virtualPath(ws, d); vm.showAssistant = true; vm.assistant.send("Look at the folder $path with browse_folder (two levels deep) and tell me what it contains, what looks usable for a film, and what you would import. Do not import anything yet.") })
            }
            DropdownMenuItem(text = { Text("Mention in Assistant") }, onClick = { menu = false; vm.assistant.mention(targets.joinToString(" ") { "[${if (it.isDirectory) "folder" else "file"} ${virtualPath(ws, it)}]" }); vm.showAssistant = true })
            row.root?.let { r -> DropdownMenuItem(text = { Text("Close folder") }, onClick = { menu = false; vm.assistant.removeRoot(r) }) }
        }
    }
}

/** Virtual path the assistant uses: /RootName/sub/file. */
private fun virtualPath(ws: Workspace, f: DocumentFile): String {
    for (r in ws.roots) {
        val root = ws.rootFile(r) ?: continue
        if (f.uri == root.uri) return "/${r.name}"
        val names = mutableListOf<String>(); var cur: DocumentFile? = f
        while (cur != null && cur.uri != root.uri) { names += cur.name ?: "?"; cur = cur.parentFile }
        if (cur != null) return "/${r.name}/" + names.reversed().joinToString("/")
    }
    return f.uri.toString()
}

@UnstableApi
@Composable
private fun FilePreview(vm: EditorViewModel, ws: Workspace, selected: List<FileRowData>, modifier: Modifier) {
    val ctx = LocalContext.current
    Column(modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        val files = selected.filter { !it.file.isDirectory }
        when {
            selected.size > 1 -> Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                Icon(Icons.Filled.Layers, null, tint = Pal.accent, modifier = Modifier.size(32.dp)); Text("${selected.size} items selected", color = Pal.text, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
                Button({ vm.importUris(files.filter { ws.kind(it.file) != null }.map { it.file.uri }) }, enabled = files.isNotEmpty()) { Text("Import ${files.size} file${if (files.size == 1) "" else "s"}") }
            }
            files.size == 1 && ws.kind(files[0].file) != null -> {
                val f = files[0].file; val kind = ws.kind(f)!!
                Box(Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(androidx.compose.ui.graphics.Color.Black), Alignment.Center) {
                    if (kind == "image") { val bmp = remember(f.uri) { ctx.contentResolver.openInputStream(f.uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = 4 }) } }; bmp?.let { androidx.compose.foundation.Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) } }
                    else {
                        val player = remember(f.uri) { ExoPlayer.Builder(ctx).build().apply { setMediaItem(MediaItem.fromUri(f.uri)); prepare() } }
                        DisposableEffect(player) { onDispose { player.release() } }
                        AndroidView({ PlayerView(it).apply { this.player = player; useController = true; controllerShowTimeoutMs = 1500 } }, Modifier.fillMaxSize())
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(f.name ?: "", color = Pal.dim, fontSize = 11.sp, maxLines = 1, modifier = Modifier.weight(1f))
                    Button({ vm.importUris(listOf(f.uri)) }, contentPadding = PaddingValues(horizontal = 14.dp)) { Text("Import") }
                }
            }
            selected.size == 1 && selected[0].file.isDirectory -> Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                val d = selected[0].file
                Icon(Icons.Filled.Folder, null, tint = Pal.accent, modifier = Modifier.size(32.dp)); Text(d.name ?: "", color = Pal.text, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
                Button({ vm.importUris(ws.mediaFiles(d).map { it.uri }) }) { Text("Import all media") }
            }
            else -> Box(Modifier.fillMaxSize(), Alignment.Center) { Text("Select a file to preview it. Long-press to select several.", color = Pal.dim, fontSize = 12.sp) }
        }
    }
}
