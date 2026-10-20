package app.lumacut.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun formatTime(ms: Long): String { val s = ms / 1000.0; val m = (s / 60).toInt(); return "%d:%04.1f".format(m, s - m * 60) }
fun timecode(ms: Long, fps: Int): String { val total = ms / 1000; val f = ((ms % 1000) * fps / 1000).toInt(); return "%02d:%02d:%02d:%02d".format(total / 3600, (total / 60) % 60, total % 60, f) }

@Composable
fun IconBtn(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, active: Boolean = false, enabled: Boolean = true, tint: Color? = null, size: Int = 40) {
    Box(modifier.size(size.dp).clip(RoundedCornerShape(10.dp)).background(if (active) Pal.accentSoft else Color.Transparent).clickable(enabled = enabled, onClick = onClick), Alignment.Center) {
        Icon(icon, label, tint = tint ?: if (!enabled) Pal.dim.copy(alpha = 0.4f) else if (active) Pal.accent else Pal.text, modifier = Modifier.size((size * 0.55f).dp))
    }
}

@Composable
fun Pill(text: String, selected: Boolean = false, onClick: () -> Unit) {
    Box(Modifier.clip(CircleShape).background(if (selected) Pal.accent else Pal.raised).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp)) {
        Text(text, color = if (selected) Color.White else Pal.dim, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

@Composable
fun Card(modifier: Modifier = Modifier, selected: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(Pal.raised).border(BorderStroke(1.dp, if (selected) Pal.accent else Pal.stroke), RoundedCornerShape(12.dp)), content = content)
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) = Text(text.uppercase(), color = Pal.dim, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, modifier = modifier.padding(top = 10.dp, bottom = 4.dp))

@Composable
fun PanelHeader(title: String, subtitle: String? = null, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Pal.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            if (subtitle != null) Text(subtitle, color = Pal.dim, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        trailing()
    }
}

@Composable
fun LabeledSlider(title: String, value: Float, range: ClosedFloatingPointRange<Float>, format: (Float) -> String = { "%.2f".format(it) }, onChange: (Float) -> Unit = {}, onDone: (Float) -> Unit) {
    var drag by remember(value) { mutableStateOf(value) }
    Column(Modifier.fillMaxWidth()) {
        Row { Text(title, color = Pal.text, fontSize = 13.sp, modifier = Modifier.weight(1f)); Text(format(drag), color = Pal.dim, fontSize = 12.sp) }
        Slider(drag, { drag = it; onChange(it) }, valueRange = range, onValueChangeFinished = { onDone(drag) }, modifier = Modifier.height(28.dp))
    }
}

@Composable
fun InfoIcon(text: String) {
    var show by remember { mutableStateOf(false) }
    Box {
        IconBtn(Icons.Filled.Info, "What this means", { show = !show }, size = 32, tint = if (show) Pal.accent else Pal.dim)
        if (show) Popup(text) { show = false }
    }
}

@Composable
fun Popup(text: String, onDismiss: () -> Unit) {
    androidx.compose.ui.window.Popup(alignment = Alignment.TopEnd, onDismissRequest = onDismiss) {
        Box(Modifier.widthIn(max = 260.dp).clip(RoundedCornerShape(12.dp)).background(Pal.hover).border(1.dp, Pal.stroke, RoundedCornerShape(12.dp)).padding(12.dp)) { Text(text, color = Pal.text, fontSize = 13.sp) }
    }
}
