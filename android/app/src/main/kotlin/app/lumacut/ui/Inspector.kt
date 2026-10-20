package app.lumacut.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.*
import app.lumacut.core.*
import kotlin.math.ln
import kotlin.math.exp

@Composable
private fun Block(title: String, trailing: @Composable RowScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text(title.uppercase(), color = Pal.dim, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, modifier = Modifier.weight(1f)); trailing() }
            content()
        }
    }
}

@UnstableApi
@Composable
fun InspectorPanel(vm: EditorViewModel, tab: RightTab, modifier: Modifier = Modifier) {
    val clip = vm.selectedClip; val tr = vm.selectedTransitionValue
    Column(modifier.verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when {
            tr != null -> TransitionInspector(vm, tr)
            clip == null -> Text(if (tab == RightTab.Inspector) "${vm.project.assets.size} files, ${vm.project.allClips.size} clips, ${formatTime(vm.project.duration)} long, ${vm.project.width}×${vm.project.height} at ${vm.project.fps} fps." else "Select a clip on the timeline to adjust its picture, look, speed, sound or text. Select the orange band between two clips to change the transition.", color = Pal.dim, fontSize = 13.sp)
            tab == RightTab.Effects -> EffectsOfClip(vm, clip)
            tab == RightTab.Inspector -> ClipFacts(vm, clip)
            else -> ClipAdjustments(vm, clip)
        }
    }
}

@Composable
private fun ClipFacts(vm: EditorViewModel, c: Clip) {
    val a = vm.project.asset(c.assetID)
    listOf("Name" to (a?.label ?: c.text ?: c.generator?.title ?: ""), "Starts" to formatTime(c.start), "Length" to formatTime(c.duration), "Source from" to formatTime(c.sourceIn), "Speed" to "${"%.2f".format(c.speed)}×",
        "Volume" to "${(c.volume * 100).toInt()} %", "Effects" to (c.effects.joinToString { it.type.title }.ifEmpty { "none" }), "Resolution" to (a?.takeIf { it.width > 0 }?.let { "${it.width}×${it.height}" } ?: "")).forEach { (k, v) ->
        if (v.isNotEmpty()) Row { Text(k, color = Pal.dim, fontSize = 13.sp, modifier = Modifier.width(110.dp)); Text(v, color = Pal.text, fontSize = 13.sp) }
    }
}

@Composable
private fun TransitionInspector(vm: EditorViewModel, tr: Transition) {
    var menu by remember { mutableStateOf(false) }
    val from = vm.project.clip(tr.fromClip); val to = vm.project.clip(tr.toClip)
    val maxS = (maxOf(200L, minOf(from?.duration ?: 1000, to?.duration ?: 1000) - 100) / 1000f)
    Block("Transition") {
        Box { OutlinedButton({ menu = true }) { Text(tr.type.title) }; DropdownMenu(menu, { menu = false }) { TransitionType.entries.forEach { t -> DropdownMenuItem(text = { Text(t.title) }, onClick = { menu = false; vm.run { apply(Command.SetTransition(tr.id, t, tr.duration)) } }) } } }
        LabeledSlider("Overlap", tr.duration / 1000f, 0.1f..maxOf(0.2f, maxS), { "%.1f s".format(it) }) { v -> vm.run { apply(Command.SetTransition(tr.id, tr.type, (v * 1000).toLong().coerceAtLeast(1))) } }
        Text("The two clips play together for this long. A longer overlap makes the movie shorter by the same amount. On Android the style plays as a ${app.lumacut.media.TransitionCompositor.family(tr.type).name.lowercase()}.", color = Pal.dim, fontSize = 11.sp)
        OutlinedButton({ vm.run { apply(Command.RemoveTransition(tr.id)) } }, colors = ButtonDefaults.outlinedButtonColors(contentColor = Pal.danger)) { Icon(Icons.Filled.Delete, null); Spacer(Modifier.width(6.dp)); Text("Remove transition") }
    }
}

@UnstableApi
@Composable
private fun ClipAdjustments(vm: EditorViewModel, c: Clip) {
    val a = vm.project.asset(c.assetID); val track = vm.project.trackOf(c.id)
    val isVideo = track?.kind == TrackKind.video && c.text == null && c.generator == null
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(a?.label ?: c.text ?: c.generator?.title ?: "Clip", color = Pal.text, fontWeight = FontWeight.SemiBold, maxLines = 1); Text("${formatTime(c.start)} · ${formatTime(c.duration)}", color = Pal.dim, fontSize = 12.sp) }
        OutlinedButton({ vm.resetSelection() }) { Icon(Icons.Filled.RestartAlt, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Reset clip") }
    }
    if (c.text != null) TextBlock(vm, c)
    if (c.generator != null) Block("Overlay") {
        var menu by remember { mutableStateOf(false) }
        Box { OutlinedButton({ menu = true }) { Text(c.generator!!.title) }; DropdownMenu(menu, { menu = false }) { GeneratorKind.entries.forEach { k -> DropdownMenuItem(text = { Text(k.title) }, onClick = { menu = false; vm.run { apply(Command.SetGenerator(c.id, k, c.generatorAmount)) } }) } } }
        LabeledSlider("Amount", c.generatorAmount.toFloat(), 0f..1f) { v -> vm.run { apply(Command.SetGenerator(c.id, c.generator!!, v.toDouble())) } }
    }
    if (isVideo || a?.isStill == true) {
        Block("Picture", { TextButton({ vm.run { apply(Command.SetTransform(c.id, 1.0, 1.0, 0.0, 0.0)); apply(Command.SetKeyframes(c.id, emptyList())) } }) { Text("Reset") } }) {
            LabeledSlider("Opacity", c.opacity.toFloat(), 0f..1f) { v -> vm.run { apply(Command.SetTransform(c.id, v.toDouble(), c.scale, c.offsetX, c.offsetY)) } }
            LabeledSlider("Size", c.scale.toFloat(), 0.1f..4f) { v -> vm.run { apply(Command.SetTransform(c.id, c.opacity, v.toDouble(), c.offsetX, c.offsetY)) } }
            LabeledSlider("Horizontal", c.offsetX.toFloat(), -1f..1f) { v -> vm.run { apply(Command.SetTransform(c.id, c.opacity, c.scale, v.toDouble(), c.offsetY)) } }
            LabeledSlider("Vertical", c.offsetY.toFloat(), -1f..1f) { v -> vm.run { apply(Command.SetTransform(c.id, c.opacity, c.scale, c.offsetX, v.toDouble())) } }
            Text("Shrink a clip and move it on a layer above another clip for picture-in-picture.", color = Pal.dim, fontSize = 11.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton({
                    val t = (vm.playheadMs - c.start).coerceIn(0, c.duration)
                    val frames = c.keyframes.filter { it.time != t } + Keyframe(t, c.opacity, c.scale, c.offsetX, c.offsetY)
                    vm.run { apply(Command.SetKeyframes(c.id, frames)) }
                }) { Text("Set keyframe here") }
                if (c.keyframes.isNotEmpty()) TextButton({ vm.run { apply(Command.SetKeyframes(c.id, emptyList())) } }) { Text("Clear ${c.keyframes.size}") }
            }
            Text("Move the playhead, set the values above, then press Set keyframe. Values glide between keyframes.", color = Pal.dim, fontSize = 11.sp)
        }
        LookBlock(vm, c)
    }
    if (c.text == null && c.generator == null) {
        Block("Speed", { TextButton({ vm.run { apply(Command.SetSpeed(c.id, 1.0)) } }) { Text("Normal") } }) {
            LabeledSlider("Speed", ln(c.speed.coerceIn(0.1, 8.0)).toFloat(), ln(0.1).toFloat()..ln(8.0).toFloat(), { "%.2f×".format(exp(it.toDouble())) }) { v -> vm.run { apply(Command.SetSpeed(c.id, exp(v.toDouble()).coerceIn(0.1, 8.0))) } }
            androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf(0.25, 0.5, 1.0, 2.0, 4.0).forEach { s -> Pill("${s}×", c.speed == s) { vm.run { apply(Command.SetSpeed(c.id, s)) } } } }
        }
    }
    if (a?.hasAudio == true || c.text != null || c.generator != null) Block(if (c.text != null || c.generator != null) "Fades" else "Audio") {
        if (c.text == null && c.generator == null) LabeledSlider("Volume", c.volume.toFloat(), 0f..2f, { "${(it * 100).toInt()} %" }) { v -> vm.run { apply(Command.SetVolume(c.id, v.toDouble(), c.fadeIn, c.fadeOut)) } }
        val maxFade = (c.duration / 2000f).coerceAtLeast(0.1f)
        LabeledSlider("Fade in", c.fadeIn / 1000f, 0f..maxFade, { "%.1f s".format(it) }) { v -> vm.run { apply(Command.SetVolume(c.id, c.volume, (v * 1000).toLong(), c.fadeOut)) } }
        LabeledSlider("Fade out", c.fadeOut / 1000f, 0f..maxFade, { "%.1f s".format(it) }) { v -> vm.run { apply(Command.SetVolume(c.id, c.volume, c.fadeIn, (v * 1000).toLong())) } }
        if (track?.kind == TrackKind.audio) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text("Duck under other sound", color = Pal.text, fontSize = 13.sp, modifier = Modifier.weight(1f)); Switch(track.duck, { v -> vm.run { apply(Command.SetTrackDuck(track.id, v)) } }) }
            if (track.duck) LabeledSlider("Dips to", track.duckLevel.toFloat(), 0.05f..0.95f, { "${(it * 100).toInt()} %" }) { v -> vm.run { apply(Command.SetTrackDuckLevel(track.id, v.toDouble())) } }
        }
    }
}

@Composable
private fun LookBlock(vm: EditorViewModel, c: Clip) {
    val l = c.look
    fun set(f: (Look) -> Look) = vm.run { apply(Command.SetLook(c.id, f(l))) }
    Block("Look & colour", { TextButton({ vm.run { apply(Command.SetLook(c.id, Look())) } }) { Text("Reset look") } }) {
        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { items(LookPresets.names.size) { i -> val n = LookPresets.names[i]; Pill(n) { vm.applyLook(n) } } }
        LabeledSlider("Brightness", l.brightness.toFloat(), -1f..1f) { v -> set { it.copy(brightness = v.toDouble()) } }
        LabeledSlider("Contrast", l.contrast.toFloat(), 0f..2f) { v -> set { it.copy(contrast = v.toDouble()) } }
        LabeledSlider("Saturation", l.saturation.toFloat(), 0f..3f) { v -> set { it.copy(saturation = v.toDouble()) } }
        LabeledSlider("Warmth", l.warmth.toFloat(), -1f..1f) { v -> set { it.copy(warmth = v.toDouble()) } }
        LabeledSlider("Matte fade", l.fade.toFloat(), 0f..1f) { v -> set { it.copy(fade = v.toDouble()) } }
        LabeledSlider("Vignette", l.vignette.toFloat(), 0f..1f) { v -> set { it.copy(vignette = v.toDouble()) } }
        LabeledSlider("Sepia", l.sepia.toFloat(), 0f..1f) { v -> set { it.copy(sepia = v.toDouble()) } }
        LabeledSlider("Blur", l.blur.toFloat(), 0f..1f) { v -> set { it.copy(blur = v.toDouble()) } }
        LabeledSlider("Sharpen", l.sharpen.toFloat(), 0f..1f) { v -> set { it.copy(sharpen = v.toDouble()) } }
        LabeledSlider("Tone strength", l.splitAmount.toFloat(), 0f..1f) { v -> set { it.copy(splitAmount = v.toDouble(), splitShadows = it.splitShadows ?: "0B6E7F", splitHighlights = it.splitHighlights ?: "FF9A3C") } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(l.flipX, { set { it.copy(flipX = !it.flipX) } }, { Text("Flip ↔") })
            FilterChip(l.flipY, { set { it.copy(flipY = !it.flipY) } }, { Text("Flip ↕") })
        }
        LabeledSlider("Rotate", l.rotation.toFloat(), -180f..180f, { "${it.toInt()}°" }) { v -> set { it.copy(rotation = v.toDouble()) } }
        listOf("Crop left" to { x: Look -> x.cropLeft } , "Crop right" to { x: Look -> x.cropRight }, "Crop top" to { x: Look -> x.cropTop }, "Crop bottom" to { x: Look -> x.cropBottom }).forEachIndexed { i, (name, get) ->
            LabeledSlider(name, get(l).toFloat(), 0f..0.6f) { v -> set { when (i) { 0 -> it.copy(cropLeft = v.toDouble()); 1 -> it.copy(cropRight = v.toDouble()); 2 -> it.copy(cropTop = v.toDouble()); else -> it.copy(cropBottom = v.toDouble()) } } }
        }
    }
}

@Composable
private fun TextBlock(vm: EditorViewModel, c: Clip) {
    var text by remember(c.id) { mutableStateOf(c.text ?: "") }
    val st = c.style
    Block("Text") {
        OutlinedTextField(text, { text = it; vm.run(quiet = true) { apply(Command.SetText(c.id, it)) } }, modifier = Modifier.fillMaxWidth(), minLines = 1, maxLines = 4)
        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { items(TitlePreset.entries.size) { i -> val p = TitlePreset.entries[i]; Pill(p.label) { vm.run { apply(Command.SetTextStyle(c.id, p.style.copy(x = st.x, y = st.y))) } } } }
        LabeledSlider("Size", st.size.toFloat(), 0.02f..0.4f) { v -> vm.run { apply(Command.SetTextStyle(c.id, st.copy(size = v.toDouble()))) } }
        LabeledSlider("Horizontal position", st.x.toFloat(), 0f..1f) { v -> vm.run { apply(Command.SetTextStyle(c.id, st.copy(x = v.toDouble()))) } }
        LabeledSlider("Vertical position", st.y.toFloat(), 0f..1f) { v -> vm.run { apply(Command.SetTextStyle(c.id, st.copy(y = v.toDouble()))) } }
        LabeledSlider("Letter spacing", st.tracking.toFloat(), 0f..0.6f) { v -> vm.run { apply(Command.SetTextStyle(c.id, st.copy(tracking = v.toDouble()))) } }
        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(listOf("FFFFFF", "FFD60A", "FF453A", "30D158", "0A84FF", "BF5AF2", "FF9F0A", "35F0FF", "000000")) { hex ->
                Box(Modifier.size(30.dp).clip(androidx.compose.foundation.shape.CircleShape).background(Color(android.graphics.Color.parseColor("#$hex")))
                    .then(if (st.colorHex.equals(hex, true)) Modifier.border(2.dp, Color.White, androidx.compose.foundation.shape.CircleShape) else Modifier).clickable { vm.run { apply(Command.SetTextStyle(c.id, st.copy(colorHex = hex))) } })
            }
        }
        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(st.bold, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(bold = !st.bold))) } }, { Text("Bold") })
            FilterChip(st.shadow, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(shadow = !st.shadow))) } }, { Text("Shadow") })
            FilterChip(st.outline, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(outline = !st.outline))) } }, { Text("Outline") })
            FilterChip(st.box, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(box = !st.box))) } }, { Text("Box") })
            FilterChip(st.glow, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(glow = !st.glow))) } }, { Text("Glow") })
            FilterChip(st.uppercase, { vm.run { apply(Command.SetTextStyle(c.id, st.copy(uppercase = !st.uppercase))) } }, { Text("CAPS") })
        }
        var menu by remember { mutableStateOf(false) }
        Box { OutlinedButton({ menu = true }) { Text("Animation: ${st.animation.title}") }; DropdownMenu(menu, { menu = false }) { TextAnimation.entries.forEach { a -> DropdownMenuItem(text = { Text(a.title) }, onClick = { menu = false; vm.run { apply(Command.SetTextStyle(c.id, st.copy(animation = a))) } }) } } }
    }
}

@UnstableApi
@Composable
private fun EffectsOfClip(vm: EditorViewModel, c: Clip) {
    var menu by remember { mutableStateOf(false) }
    Block("Effects on this clip", { Box { TextButton({ menu = true }) { Icon(Icons.Filled.Add, null, Modifier.size(16.dp)); Text("Add") }; DropdownMenu(menu, { menu = false }) { EffectType.entries.filter { it != EffectType.chromaKey && it != EffectType.removeBackground }.forEach { t -> DropdownMenuItem(text = { Text(t.title) }, onClick = { menu = false; vm.addEffect(t) }) } } } }) {
        if (c.effects.isEmpty()) Text("None yet. Add one, or tap one in the Effects tab.", color = Pal.dim, fontSize = 12.sp)
        c.effects.forEach { e ->
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(e.type.title, color = Pal.text, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f)); IconBtn(Icons.Filled.Close, "Remove", { vm.run { apply(Command.RemoveEffect(c.id, e.id)) } }, size = 32) }
                LabeledSlider("Strength", e.amount.toFloat(), 0f..1f) { v -> vm.run { apply(Command.AddEffect(c.id, e.copy(amount = v.toDouble()))) } }
                Text(e.type.summary, color = Pal.dim, fontSize = 11.sp)
            }
        }
    }
}
