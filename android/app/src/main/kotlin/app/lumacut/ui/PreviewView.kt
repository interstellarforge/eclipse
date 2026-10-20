package app.lumacut.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import app.lumacut.EditorViewModel

@UnstableApi
@Composable
fun Preview(vm: EditorViewModel, modifier: Modifier = Modifier) {
    val p = vm.project
    Column(modifier) {
        Box(Modifier.weight(1f, fill = false).fillMaxWidth().aspectRatio(p.width.toFloat() / p.height).clip(RoundedCornerShape(12.dp)).background(Color.Black), Alignment.Center) {
            AndroidView(factory = { c -> PlayerView(c).apply { useController = false; setShutterBackgroundColor(android.graphics.Color.BLACK); player = vm.player; vm.playerView = this } },
                update = { it.player = vm.player; vm.playerView = it }, onRelease = { if (vm.playerView === it) vm.playerView = null }, modifier = Modifier.fillMaxSize())
            if (p.allClips.none { it.assetID != null }) Text("Import clips to begin", color = Pal.dim, fontSize = 14.sp)
            vm.bakingNote?.let { Text(it, color = Color.White, fontSize = 11.sp, modifier = Modifier.align(Alignment.TopStart).padding(8.dp).clip(RoundedCornerShape(6.dp)).background(Color(0x99000000)).padding(horizontal = 8.dp, vertical = 3.dp)) }
            vm.previewNote?.let { Text(it, color = Color(0xFFFFA94D), fontSize = 12.sp, modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color(0xCC000000)).padding(8.dp)) }
        }
        Transport(vm)
    }
}

@Composable
fun Transport(vm: EditorViewModel) {
    val mono = androidx.compose.ui.text.font.FontFamily.Monospace
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(timecode(vm.playheadMs, vm.project.fps), color = Pal.text, fontSize = 15.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Medium, fontFamily = mono)
            Text("  /  " + timecode(vm.project.duration, vm.project.fps), color = Pal.dim, fontSize = 12.sp, fontFamily = mono)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
            IconBtn(Icons.Filled.SkipPrevious, "Previous cut", { vm.jumpToEdit(false) })
            IconBtn(Icons.Filled.FastRewind, "Back one frame", { vm.step(-1) })
            Box(Modifier.size(52.dp).clip(androidx.compose.foundation.shape.CircleShape).background(Pal.accent), Alignment.Center) {
                IconBtn(if (vm.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (vm.isPlaying) "Pause" else "Play", { vm.togglePlay() }, tint = Color.White, size = 52)
            }
            IconBtn(Icons.Filled.FastForward, "Forward one frame", { vm.step(1) })
            IconBtn(Icons.Filled.SkipNext, "Next cut", { vm.jumpToEdit(true) })
        }
    }
}
