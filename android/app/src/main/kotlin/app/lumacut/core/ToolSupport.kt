package app.lumacut.core

import kotlinx.serialization.json.*

class ToolError(message: String) : Exception(message)

sealed interface Content {
    data class Text(val text: String) : Content
    data class Image(val mediaType: String, val base64: String) : Content
}

/** Typed access to a tool call's JSON arguments. */
class Args(val d: JsonObject) {
    private fun prim(k: String) = (d[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }
    fun str(k: String): String = optStr(k) ?: throw ToolError("missing string argument '$k'")
    fun ms(k: String): Long = optMs(k) ?: throw ToolError("missing number argument '$k'")
    fun optMs(k: String): Long? = prim(k)?.doubleOrNull?.toLong()
    fun optDouble(k: String): Double? = prim(k)?.doubleOrNull
    fun optStr(k: String): String? = prim(k)?.takeIf { it.isString }?.content
    fun optBool(k: String): Boolean? = prim(k)?.booleanOrNull
    fun optInt(k: String): Int? = optDouble(k)?.toInt()
    fun id(k: String): Id = str(k).takeIf { it.isNotBlank() } ?: throw ToolError("'$k' is not a valid id")
    fun optID(k: String): Id? = optStr(k)?.takeIf { it.isNotBlank() }
    fun list(k: String): List<JsonObject>? = (d[k] as? JsonArray)?.mapNotNull { it as? JsonObject }
    fun strings(k: String): List<String>? = (d[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
    fun obj(k: String): JsonObject? = d[k] as? JsonObject
    fun has(k: String) = d[k] != null && d[k] !is JsonNull

    fun textStyle(base: TextStyle): TextStyle {
        var st = base
        optDouble("size")?.let { st = st.copy(size = it) }; optStr("color")?.let { st = st.copy(colorHex = it) }
        optDouble("x")?.let { st = st.copy(x = it) }; optDouble("y")?.let { st = st.copy(y = it) }
        optBool("bold")?.let { st = st.copy(bold = it) }; optBool("shadow")?.let { st = st.copy(shadow = it) }
        optStr("font")?.let { st = st.copy(fontName = it) }
        optStr("align")?.let { st = st.copy(align = mapOf("left" to 0, "center" to 1, "right" to 2)[it] ?: 1) }
        optBool("outline")?.let { st = st.copy(outline = it) }; optBool("box")?.let { st = st.copy(box = it) }
        optStr("animation")?.let { n -> TextAnimation.entries.firstOrNull { it.name == n }?.let { st = st.copy(animation = it) } }
        optDouble("tracking")?.let { st = st.copy(tracking = it) }; optBool("uppercase")?.let { st = st.copy(uppercase = it) }
        optBool("glow")?.let { st = st.copy(glow = it) }; optMs("animation_ms")?.let { st = st.copy(animationMs = it) }
        return st
    }

    fun keyframe() = Keyframe(time = optMs("time_ms") ?: 0, opacity = optDouble("opacity") ?: 1.0, scale = optDouble("scale") ?: 1.0, offsetX = optDouble("offset_x") ?: 0.0,
        offsetY = optDouble("offset_y") ?: 0.0, rotation = optDouble("rotation") ?: 0.0, smooth = optBool("smooth") ?: true)

    fun look(base: Look): Look {
        var l = base
        optDouble("brightness")?.let { l = l.copy(brightness = it) }; optDouble("contrast")?.let { l = l.copy(contrast = it) }
        optDouble("saturation")?.let { l = l.copy(saturation = it) }; optDouble("sepia")?.let { l = l.copy(sepia = it) }
        optDouble("blur")?.let { l = l.copy(blur = it) }; optDouble("vignette")?.let { l = l.copy(vignette = it) }
        optBool("flip_horizontal")?.let { l = l.copy(flipX = it) }; optBool("flip_vertical")?.let { l = l.copy(flipY = it) }
        optDouble("rotation")?.let { l = l.copy(rotation = it) }
        optDouble("crop_left")?.let { l = l.copy(cropLeft = it) }; optDouble("crop_right")?.let { l = l.copy(cropRight = it) }
        optDouble("crop_top")?.let { l = l.copy(cropTop = it) }; optDouble("crop_bottom")?.let { l = l.copy(cropBottom = it) }
        optDouble("warmth")?.let { l = l.copy(warmth = it) }; optDouble("fade")?.let { l = l.copy(fade = it) }; optDouble("sharpen")?.let { l = l.copy(sharpen = it) }
        optStr("split_shadows")?.let { l = l.copy(splitShadows = it.ifEmpty { null }) }
        optStr("split_highlights")?.let { l = l.copy(splitHighlights = it.ifEmpty { null }) }
        optDouble("split_amount")?.let { l = l.copy(splitAmount = it) }
        return l
    }
}

/** Things only the app can do (media access, dialogs, rendering). Tools call these. */
interface Host {
    fun playheadMs(): Ms
    fun workspaceRoots(): List<String>
    suspend fun importMedia(uriOrPath: String): Asset
    suspend fun ask(question: String, options: List<AskOption>, allowText: Boolean): String
    suspend fun pickRanges(reason: String, assetIds: List<Id>): String
    suspend fun reviewScript(draft: ScriptDraft): String
    suspend fun browseFolder(path: String, depth: Int): String
    /** JPEG contact sheet of evenly spaced frames of one asset (optionally a range). */
    suspend fun contactSheet(asset: Asset, frames: Int, startMs: Ms?, endMs: Ms?): ByteArray?
    /** JPEG of the composited timeline at a time, or a contact sheet of the whole timeline when `frames` > 1. */
    suspend fun timelineFrame(project: Project, atMs: Ms): ByteArray?
    suspend fun timelineSheet(project: Project, frames: Int, startMs: Ms?, endMs: Ms?): ByteArray?
    suspend fun export(project: Project, name: String?): String
    suspend fun assetInfo(asset: Asset): String
}

/** One answer Claude offers in ask_user. `info` explains what the choice means and what Claude will do for the edit. */
data class AskOption(val label: String, val info: String = "")
