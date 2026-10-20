package app.lumacut.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import app.lumacut.*
import app.lumacut.core.*
import kotlinx.coroutines.delay
import kotlin.math.sin

@UnstableApi
@Composable
fun AssistantScreen(vm: EditorViewModel, modifier: Modifier = Modifier, onClose: (() -> Unit)? = null) {
    val a = vm.assistant
    var showSettings by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    LaunchedEffect(a.messages.size, a.messages.lastOrNull()?.text?.length, a.question) { if (a.messages.isNotEmpty()) list.animateScrollToItem(a.messages.size + 1) }
    Column(modifier.background(Pal.panel)) {
        AssistantHeader(vm, onClose, onSettings = { showSettings = true })
        if (a.offline) Row(Modifier.fillMaxWidth().background(Pal.accentSoft).padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Lock, null, tint = Pal.accent, modifier = Modifier.size(14.dp)); Text("Offline: Claude can't see your videos", color = Pal.text, fontSize = 12.sp, modifier = Modifier.padding(start = 6.dp).weight(1f))
            TextButton({ a.openSelectionManually() }, enabled = !a.running) { Text("Select parts…") }
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (a.messages.isEmpty()) item { Welcome(vm) }
            items(grouped(a.messages)) { (m, n) -> MessageRow(m, n) }
            a.question?.let { q -> item { QuestionCard(vm, q) } }
            if (a.running && a.messages.lastOrNull()?.role != UiMessage.Role.Assistant) item { TypingDots() }
            item { Spacer(Modifier.height(4.dp)) }
        }
        Composer(vm)
    }
    if (showSettings) SettingsDialog(vm) { showSettings = false }
    a.selectionRequest?.let { SelectionDialog(vm, it) }
    a.scriptReview?.let { ScriptDialog(vm, it) }
}

private fun grouped(msgs: List<UiMessage>): List<Pair<UiMessage, Int>> {
    val out = mutableListOf<Pair<UiMessage, Int>>()
    for (m in msgs) {
        val last = out.lastOrNull()
        if (m.role == UiMessage.Role.Tool && last != null && last.first.role == UiMessage.Role.Tool && last.first.text == m.text && !m.failed && !last.first.failed) out[out.lastIndex] = last.first to last.second + 1
        else out += m to 1
    }
    return out
}

@UnstableApi
@Composable
private fun AssistantHeader(vm: EditorViewModel, onClose: (() -> Unit)?, onSettings: () -> Unit) {
    val a = vm.assistant
    var scriptMenu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onClose != null) IconBtn(Icons.Filled.KeyboardArrowDown, "Close", onClose, size = 36)
        Icon(Icons.Filled.AutoAwesome, null, tint = Pal.accent)
        Text("AI Assistant", color = Pal.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp).weight(1f))
        IconBtn(if (a.offline) Icons.Filled.Lock else Icons.Filled.LockOpen, if (a.offline) "Offline is ON" else "Offline mode: keep your videos private", { a.updateOffline(!a.offline) }, active = a.offline)
        Box {
            IconBtn(Icons.Filled.MenuBook, "Script mode: ${a.scriptLevel.label}", { scriptMenu = true }, active = a.scriptLevel != ScriptLevel.off)
            if (scriptMenu) androidx.compose.ui.window.Popup(alignment = Alignment.TopEnd, onDismissRequest = { scriptMenu = false }) {
                Column(Modifier.width(300.dp).clip(RoundedCornerShape(14.dp)).background(Pal.hover).border(1.dp, Pal.stroke, RoundedCornerShape(14.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Script mode", color = Pal.text, fontWeight = FontWeight.SemiBold); Text("How much the Assistant plans before it builds.", color = Pal.dim, fontSize = 12.sp)
                    ScriptLevel.entries.forEach { l ->
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (l == a.scriptLevel) Pal.accentSoft else Pal.raised).clickable { a.updateScriptLevel(l); scriptMenu = false }.padding(10.dp)) {
                            Icon(if (l == a.scriptLevel) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (l == a.scriptLevel) Pal.accent else Pal.dim, modifier = Modifier.size(20.dp))
                            Column(Modifier.padding(start = 8.dp)) { Text(l.label, color = Pal.text, fontWeight = FontWeight.SemiBold, fontSize = 13.sp); Text(l.summary, color = Pal.dim, fontSize = 12.sp) }
                        }
                    }
                }
            }
        }
        IconBtn(Icons.Filled.Add, "New chat", { a.newChat() }, enabled = a.messages.isNotEmpty())
        IconBtn(Icons.Filled.Settings, "Settings", onSettings)
    }
}

@Composable
private fun MessageRow(m: UiMessage, count: Int) {
    when (m.role) {
        UiMessage.Role.User -> Box(Modifier.fillMaxWidth(), Alignment.CenterEnd) { Text(m.text, color = Color.White, fontSize = 14.sp, modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(Pal.accent).padding(10.dp)) }
        UiMessage.Role.Assistant -> Text(markdown(m.text), color = Pal.text, fontSize = 14.sp, lineHeight = 20.sp)
        UiMessage.Role.Tool -> Row(verticalAlignment = Alignment.CenterVertically) {
            if (!m.done) CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 2.dp, color = Pal.dim) else Icon(if (m.failed) Icons.Filled.Cancel else Icons.Filled.CheckCircle, null, tint = if (m.failed) Pal.danger else Color(0xFF30D158), modifier = Modifier.size(13.dp))
            Text(if (count > 1) "${m.text} ×$count" else m.text, color = Pal.dim, fontSize = 12.sp, modifier = Modifier.padding(start = 6.dp), maxLines = 1)
        }
        UiMessage.Role.Notice -> Text(m.text, color = if (m.failed) Pal.danger else Pal.dim, fontSize = 13.sp)
    }
}

private fun markdown(s: String): AnnotatedString = buildAnnotatedString {
    var i = 0
    while (i < s.length) {
        if (s.startsWith("**", i)) { val e = s.indexOf("**", i + 2); if (e > 0) { withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(s.substring(i + 2, e)) }; i = e + 2; continue } }
        if (s[i] == '`') { val e = s.indexOf('`', i + 1); if (e > 0) { withStyle(SpanStyle(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, background = Pal.raised)) { append(s.substring(i + 1, e)) }; i = e + 1; continue } }
        append(s[i]); i++
    }
}

@Composable
private fun TypingDots() {
    var t by remember { mutableStateOf(0.0) }
    LaunchedEffect(Unit) { while (true) { delay(60); t += 0.3 } }
    Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Pal.raised).padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        for (i in 0 until 3) { val phase = ((sin(t * 3 - i * 0.9) + 1) / 2).toFloat(); Box(Modifier.offset(y = (-3 * phase).dp).size(7.dp).clip(CircleShape).background(Pal.dim.copy(alpha = 0.35f + 0.65f * phase))) }
    }
}

@Composable
private fun Welcome(vm: EditorViewModel) {
    var cat by remember { mutableStateOf(PromptData.categories.first()) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Turn your ideas into a great edit.", color = Pal.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text("The Assistant looks at your clips, plans the film like a director and edits the timeline for you. Everything can be undone.", color = Pal.dim, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button({ vm.assistant.send("[GUIDED EDIT] Guide me step by step through making a film from my clips. Use the guided-edit skill and ask me one question at a time.", "Guided edit: ask me step by step") }) { Text("Guided edit") }
            OutlinedButton({ vm.assistant.updateScriptLevel(ScriptLevel.medium) }) { Text("Script mode") }
        }
        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { items(PromptData.categories) { c -> Pill(c, cat == c) { cat = c } } }
        PromptData.all.filter { it.category == cat }.forEach { p ->
            Card(Modifier.fillMaxWidth().clickable { vm.assistant.draft = p.prompt }) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(p.emoji, fontSize = 24.sp); Column(Modifier.padding(start = 10.dp).weight(1f)) { Text(p.title, color = Pal.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp); Text(p.subtitle, color = Pal.dim, fontSize = 12.sp) }
                    IconBtn(Icons.Filled.Send, "Send now", { vm.assistant.send(p.prompt, p.title) }, tint = Pal.accent)
                }
            }
        }
    }
}

@Composable
private fun QuestionCard(vm: EditorViewModel, q: PendingQuestion) {
    var typed by remember(q) { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Pal.accentSoft).border(1.dp, Pal.accent.copy(alpha = 0.4f), RoundedCornerShape(14.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.QuestionAnswer, null, tint = Pal.accent, modifier = Modifier.size(16.dp)); Text("Claude asks", color = Pal.dim, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp).weight(1f))
            IconBtn(Icons.Filled.Close, "Dismiss and stop", { vm.assistant.stop() }, size = 32)
        }
        Text(q.question, color = Pal.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        q.options.forEach { o ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Pal.hover).clickable { vm.assistant.answerQuestion(o.label) }.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(o.label, color = Pal.text, fontSize = 14.sp, modifier = Modifier.weight(1f).padding(vertical = 12.dp))
                if (o.info.isNotEmpty()) InfoIcon(o.info)
            }
        }
        if (q.allowText) Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(typed, { typed = it }, placeholder = { Text("Or type your own answer…") }, singleLine = true, modifier = Modifier.weight(1f))
            TextButton({ if (typed.isNotBlank()) vm.assistant.answerQuestion(typed.trim()) }, enabled = typed.isNotBlank()) { Text("Send") }
        }
    }
}

@Composable
private fun Composer(vm: EditorViewModel) {
    val a = vm.assistant
    Column(Modifier.fillMaxWidth().padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        a.queue.forEachIndexed { i, text ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Pal.raised).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Schedule, null, tint = Pal.dim, modifier = Modifier.size(14.dp)); Text(text, color = Pal.text, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 8.dp).weight(1f))
                TextButton({ a.sendNow(i) }, contentPadding = PaddingValues(horizontal = 6.dp)) { Text("Send now", fontSize = 12.sp) }
                IconBtn(Icons.Filled.Close, "Remove from queue", { a.removeQueued(i) }, size = 30)
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedTextField(a.draft, { a.draft = it }, placeholder = { Text("Describe what you'd like to create…") }, modifier = Modifier.weight(1f), maxLines = 5, shape = RoundedCornerShape(14.dp))
            if (a.running) {
                if (a.draft.isNotBlank()) FilledIconButton({ a.send() }, colors = IconButtonDefaults.filledIconButtonColors(containerColor = Pal.accent.copy(alpha = 0.75f))) { Icon(Icons.Filled.PlaylistAdd, "Add to the queue") }
                FilledIconButton({ a.stop() }, colors = IconButtonDefaults.filledIconButtonColors(containerColor = Pal.accent)) { Icon(Icons.Filled.Stop, "Stop") }
            } else FilledIconButton({ a.send() }, enabled = a.draft.isNotBlank(), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Pal.accent)) { Icon(Icons.Filled.ArrowUpward, "Send") }
        }
    }
}

@UnstableApi
@Composable
private fun SettingsDialog(vm: EditorViewModel, onDismiss: () -> Unit) {
    val a = vm.assistant
    var key by remember { mutableStateOf(a.apiKey) }
    AlertDialog(onDismissRequest = onDismiss, confirmButton = { TextButton({ a.updateApiKey(key); onDismiss() }) { Text("Save") } }, dismissButton = { TextButton(onDismiss) { Text("Cancel") } }, title = { Text("Assistant settings") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("The Assistant uses your own Claude API key. It is stored only on this device and sent only to Anthropic.", color = Pal.dim, fontSize = 12.sp)
            OutlinedTextField(key, { key = it }, label = { Text("Claude API key") }, singleLine = true, visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation())
            Text("Model", color = Pal.text, fontSize = 13.sp)
            MODELS.forEach { (id, name) -> Row(Modifier.fillMaxWidth().clickable { a.updateModel(id) }, verticalAlignment = Alignment.CenterVertically) { RadioButton(a.model == id, { a.updateModel(id) }); Text(name) } }
            Text("Offline mode never sends pictures, sound or speech from your clips. It still sends your messages, file names and the parts you mark.", color = Pal.dim, fontSize = 12.sp)
        }
    })
}
