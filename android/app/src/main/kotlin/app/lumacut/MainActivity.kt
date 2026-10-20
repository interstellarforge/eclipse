package app.lumacut

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.*
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.util.UnstableApi
import app.lumacut.ui.*

@UnstableApi
class MainActivity : ComponentActivity() {
    private val vm: EditorViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), navigationBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        setContent { EclipseTheme { App(vm) } }
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 && intent.hasExtra("demo")) { vm.debugLiveTransitions = intent.hasExtra("live"); vm.loadDemo(intent.getIntExtra("demo", 9)) }
    }

    override fun onStop() { super.onStop(); vm.pausePlayback() }
}

private val NAV_ICONS = mapOf(LeftTab.Media to Icons.Filled.PhotoLibrary, LeftTab.Files to Icons.Filled.Folder, LeftTab.Titles to Icons.Filled.TextFields, LeftTab.Overlays to Icons.Filled.AutoAwesome,
    LeftTab.Audio to Icons.Filled.GraphicEq, LeftTab.Transitions to Icons.Filled.CallMerge, LeftTab.Effects to Icons.Filled.AutoFixHigh, LeftTab.Color to Icons.Filled.Palette,
    LeftTab.Templates to Icons.Filled.GridView, LeftTab.Smart to Icons.Filled.Psychology)

@OptIn(ExperimentalMaterial3Api::class)
@UnstableApi
@Composable
fun App(vm: EditorViewModel) {
    val wide = LocalConfiguration.current.screenWidthDp >= 840
    val snack = remember { SnackbarHostState() }
    LaunchedEffect(vm.status) { if (vm.status.isNotEmpty()) { snack.showSnackbar(vm.status); vm.status = "" } }
    var showExport by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<(() -> Unit)?>(null) }

    fun guard(proceed: () -> Unit) { if (vm.hasUnsavedWork) confirm = proceed else proceed() }

    Box(Modifier.fillMaxSize().background(Pal.background)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            TopBar(vm, onExport = { showExport = true }, guard = ::guard)
            if (wide) WideLayout(vm) else NarrowLayout(vm)
        }
        SnackbarHost(snack, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 70.dp))
        DragGhost(vm)
    }

    if (!wide && vm.showPanel) ModalBottomSheet({ vm.showPanel = false }, containerColor = Pal.panel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        LeftPanel(vm, Modifier.fillMaxWidth().fillMaxHeight(0.92f))
    }
    if (!wide && vm.showInspector) ModalBottomSheet({ vm.showInspector = false }, containerColor = Pal.panel) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.7f)) { RightTabs(vm, listOf(RightTab.Adjust, RightTab.Effects, RightTab.Inspector)); InspectorPanel(vm, vm.rightTab, Modifier.weight(1f)) }
    }
    if (!wide && vm.showAssistant) Dialog({ vm.showAssistant = false }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Pal.panel).statusBarsPadding().navigationBarsPadding().imePadding()) {
            AssistantScreen(vm, Modifier.fillMaxSize(), onClose = { vm.showAssistant = false })
        }
    }
    if (showExport) ExportDialog(vm) { showExport = false }
    vm.update?.let { u ->
        AlertDialog({ if (vm.updateProgress == null) vm.update = null }, title = { Text("Update available: ${u.name}") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (u.notes.isNotBlank()) Text(u.notes)
                vm.updateProgress?.let { LinearProgressIndicator(progress = { it }, Modifier.fillMaxWidth()) }
            } },
            confirmButton = { TextButton({ vm.installUpdate() }, enabled = vm.updateProgress == null) { Text(if (vm.updateProgress == null) "Update" else "Downloading…") } },
            dismissButton = { TextButton({ vm.update = null }, enabled = vm.updateProgress == null) { Text("Later") } })
    }
    confirm?.let { proceed ->
        AlertDialog({ confirm = null }, title = { Text("Save changes to “${vm.projectName}”?") }, text = { Text("Your edits will be lost if you don't save them.") },
            confirmButton = { TextButton({ vm.save(); confirm = null; proceed() }) { Text("Save") } },
            dismissButton = { Row { TextButton({ confirm = null }) { Text("Cancel") }; TextButton({ confirm = null; proceed() }) { Text("Don't save") } } })
    }
}

@UnstableApi
@Composable
private fun TopBar(vm: EditorViewModel, onExport: () -> Unit, guard: (() -> Unit) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var openList by remember { mutableStateOf(false) }
    var saveAs by remember { mutableStateOf(false) }
    var diag by remember { mutableStateOf<String?>(null) }
    val copyOut = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/octet-stream")) { it?.let(vm::exportProjectTo) }
    val openFile = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.OpenDocument()) { it?.let(vm::openProjectFrom) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(R.drawable.logo_tile), "Eclipse", Modifier.size(30.dp))
        Box {
            Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable { menu = true }.padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(vm.projectName + if (vm.hasUnsavedWork) " •" else "", color = Pal.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp); Icon(Icons.Filled.ArrowDropDown, null, tint = Pal.dim)
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(text = { Text("New project") }, onClick = { menu = false; guard { vm.newProject() } })
                DropdownMenuItem(text = { Text("Open…") }, onClick = { menu = false; guard { openList = true } })
                DropdownMenuItem(text = { Text("Save") }, onClick = { menu = false; if (vm.projectName == "Untitled") saveAs = true else vm.save() })
                DropdownMenuItem(text = { Text("Save as…") }, onClick = { menu = false; saveAs = true })
                DropdownMenuItem(text = { Text("Save a copy to…") }, onClick = { menu = false; copyOut.launch(vm.projectName + ".moviemaker") })
                DropdownMenuItem(text = { Text("Open from file…") }, onClick = { menu = false; guard { openFile.launch(arrayOf("*/*")) } })
                DropdownMenuItem(text = { Text(if (vm.simplePreview) "Preview transitions: off (tap to try)" else "Preview transitions: on") }, onClick = { menu = false; vm.usePreviewCuts(!vm.simplePreview) })
                DropdownMenuItem(text = { Text("Diagnostics") }, onClick = { menu = false; diag = vm.diagnostics() })
                DropdownMenuItem(text = { Text("Check for updates") }, onClick = { menu = false; vm.checkForUpdate(manual = true) })
                HorizontalDivider()
                Text("Canvas", color = Pal.dim, fontSize = 11.sp, modifier = Modifier.padding(horizontal = 12.dp))
                listOf("16:9 (1920×1080)" to (1920 to 1080), "9:16 vertical (1080×1920)" to (1080 to 1920), "1:1 square (1080×1080)" to (1080 to 1080), "4:5 portrait (1080×1350)" to (1080 to 1350)).forEach { (n, s) ->
                    DropdownMenuItem(text = { Text(n) }, onClick = { menu = false; vm.run { apply(app.lumacut.core.Command.SetFormat(s.first, s.second, project.fps)) } })
                }
            }
        }
        Spacer(Modifier.weight(1f))
        IconBtn(Icons.Filled.Undo, "Undo", { vm.undo() }, enabled = vm.canUndo)
        IconBtn(Icons.Filled.Redo, "Redo", { vm.redo() }, enabled = vm.canRedo)
        IconBtn(Icons.Filled.AutoAwesome, "Assistant", { vm.showAssistant = !vm.showAssistant; vm.rightTab = RightTab.Assistant }, active = vm.showAssistant)
        Button(onExport, enabled = vm.project.duration > 0, contentPadding = PaddingValues(horizontal = 14.dp)) { Icon(Icons.Filled.IosShare, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Export") }
    }
    if (openList) OpenDialog(vm) { openList = false }
    diag?.let { text ->
        val ctx = androidx.compose.ui.platform.LocalContext.current
        AlertDialog({ diag = null }, title = { Text("Diagnostics") },
            text = { Text(text, fontSize = 10.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, lineHeight = 13.sp, modifier = Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton({ ctx.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, text), "Share diagnostics")); diag = null }) { Text("Share") } },
            dismissButton = { TextButton({ diag = null }) { Text("Close") } })
    }
    if (saveAs) {
        var n by remember { mutableStateOf(if (vm.projectName == "Untitled") "" else vm.projectName) }
        val exists = n.isNotBlank() && n != vm.projectName && vm.savedExists(n)
        AlertDialog({ saveAs = false }, title = { Text("Save project as") }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(n, { n = it }, singleLine = true, label = { Text("Name") })
                Text("Saved inside the app: ${vm.projectsPath()}", color = Pal.dim, fontSize = 11.sp)
                if (exists) Text("A project with this name exists and will be replaced.", color = Pal.danger, fontSize = 12.sp)
                Text("Use “Save a copy to…” to put a file in Downloads, Drive or on an SD card.", color = Pal.dim, fontSize = 11.sp)
            }
        }, confirmButton = { TextButton({ vm.save(n); saveAs = false }, enabled = n.isNotBlank()) { Text(if (exists) "Replace" else "Save") } }, dismissButton = { TextButton({ saveAs = false }) { Text("Cancel") } })
    }
}

@UnstableApi
@Composable
private fun OpenDialog(vm: EditorViewModel, onClose: () -> Unit) {
    val files = remember { mutableStateListOf(*vm.savedProjects().toTypedArray()) }
    var query by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf<java.io.File?>(null) }
    val shown = files.filter { it.nameWithoutExtension.contains(query, ignoreCase = true) }
    val fmt = remember { java.text.SimpleDateFormat("d MMM yyyy, HH:mm", java.util.Locale.getDefault()) }
    AlertDialog(onClose, title = { Text("Open project (${files.size})") }, confirmButton = { TextButton(onClose) { Text("Close") } }, text = {
        if (files.isEmpty()) Text("No saved projects yet. Saved projects live inside the app; use “Open from file…” for files elsewhere.") else Column {
            if (files.size > 5) OutlinedTextField(query, { query = it }, singleLine = true, placeholder = { Text("Search") }, modifier = Modifier.fillMaxWidth())
            LazyColumn(Modifier.heightIn(max = 380.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(shown, key = { it.name }) { f ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable { vm.open(f); onClose() }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) { Text(f.nameWithoutExtension, maxLines = 1); Text(fmt.format(java.util.Date(f.lastModified())) + " · " + f.length() / 1024 + " KB", color = Pal.dim, fontSize = 11.sp) }
                        IconBtn(Icons.Filled.Delete, "Delete", { deleting = f }, size = 32)
                    }
                }
            }
        }
    })
    deleting?.let { f -> AlertDialog({ deleting = null }, title = { Text("Delete “${f.nameWithoutExtension}”?") }, text = { Text("This can't be undone.") },
        confirmButton = { TextButton({ vm.deleteSaved(f); files.remove(f); deleting = null }) { Text("Delete") } }, dismissButton = { TextButton({ deleting = null }) { Text("Cancel") } }) }
}

@UnstableApi
@Composable
private fun NavRow(vm: EditorViewModel) {
    Row(Modifier.fillMaxWidth().background(Pal.panel).horizontalScroll(rememberScrollState()).padding(vertical = 4.dp)) {
        NavItem(Icons.Filled.Tune, "Adjust", selected = vm.showInspector, enabled = vm.selection != null || vm.selectedTransition != null) { vm.rightTab = RightTab.Adjust; vm.showInspector = true }
        LeftTab.entries.forEach { t ->
            if (t in TRAY_TABS) NavItem(NAV_ICONS[t]!!, t.label, vm.trayTab == t) { vm.trayTab = if (vm.trayTab == t) null else t }
            else NavItem(NAV_ICONS[t]!!, t.label, vm.showPanel && vm.leftTab == t) { vm.leftTab = t; vm.showPanel = true }
        }
    }
}

@Composable
private fun NavItem(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, selected: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Column(Modifier.width(72.dp).clip(RoundedCornerShape(10.dp)).clickable(enabled = enabled, onClick = onClick).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, label, tint = if (!enabled) Pal.dim.copy(alpha = 0.4f) else if (selected) Pal.accent else Pal.dim, modifier = Modifier.size(22.dp))
        Text(label, color = if (selected) Pal.accent else Pal.dim, fontSize = 10.sp, maxLines = 1)
    }
}

@UnstableApi
@Composable
private fun NarrowLayout(vm: EditorViewModel) {
    Column(Modifier.fillMaxSize()) {
        Preview(vm, Modifier.fillMaxWidth().padding(horizontal = 12.dp).weight(0.46f, fill = true))
        Timeline(vm, Modifier.fillMaxWidth().weight(0.54f))
        vm.trayTab?.takeIf { it in TRAY_TABS }?.let { Tray(vm, it) }
        NavRow(vm)
    }
}

@UnstableApi
@Composable
private fun RightTabs(vm: EditorViewModel, tabs: List<RightTab>) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { tabs.forEach { t -> Pill(t.label, vm.rightTab == t) { vm.rightTab = t } } }
}

@UnstableApi
@Composable
private fun WideLayout(vm: EditorViewModel) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.weight(1f).fillMaxWidth()) {
            Column(Modifier.width(76.dp).fillMaxHeight().background(Pal.panel).verticalScroll(rememberScrollState())) { LeftTab.entries.forEach { t -> NavItem(NAV_ICONS[t]!!, t.label, vm.leftTab == t) { vm.leftTab = t } } }
            LeftPanel(vm, Modifier.width(330.dp).fillMaxHeight())
            Preview(vm, Modifier.weight(1f).fillMaxHeight().padding(12.dp))
            Column(Modifier.width(380.dp).fillMaxHeight().background(Pal.panel)) {
                RightTabs(vm, RightTab.entries)
                if (vm.rightTab == RightTab.Assistant) AssistantScreen(vm, Modifier.weight(1f)) else InspectorPanel(vm, vm.rightTab, Modifier.weight(1f))
            }
        }
        Timeline(vm, Modifier.fillMaxWidth().height(250.dp))
    }
}
