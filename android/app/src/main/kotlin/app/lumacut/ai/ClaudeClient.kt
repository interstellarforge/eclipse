package app.lumacut.ai

import app.lumacut.core.Content
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

sealed interface ChatEvent {
    data class TextDelta(val text: String) : ChatEvent
    data class ToolUse(val id: String, val name: String, val input: JsonObject) : ChatEvent
    data class ToolResult(val id: String, val name: String, val isError: Boolean) : ChatEvent
    data class Finished(val inputTokens: Int, val outputTokens: Int) : ChatEvent
    data class Failed(val message: String) : ChatEvent
}

/** Talks to the Claude Messages API (streaming) and runs the tool loop until the assistant is done. */
class ClaudeClient(private val apiKey: () -> String, private val model: () -> String, private val baseUrl: String = "https://api.anthropic.com") {
    private val json = Json { ignoreUnknownKeys = true }

    private class Block(val type: String, val id: String = "", val name: String = "") { val text = StringBuilder(); val input = StringBuilder() }

    /**
     * One user turn. `history` holds the conversation as API messages and is extended in place (assistant turns and tool results included).
     * `runTool` executes a tool call. `emit` reports what happens (text, tool use, results).
     */
    suspend fun run(
        history: MutableList<JsonObject>, system: () -> String, tools: () -> List<JsonObject>,
        runTool: suspend (String, JsonObject) -> Pair<List<Content>, Boolean>, emit: suspend (ChatEvent) -> Unit,
    ) {
        var inTokens = 0; var outTokens = 0
        repeat(80) {
            currentCoroutineContext().ensureActive()
            val result = try { stream(history, system(), tools(), emit) } catch (e: java.io.IOException) { emit(ChatEvent.Failed(e.message ?: "network error")); return }
            inTokens += result.inputTokens; outTokens += result.outputTokens
            if (result.error != null) { emit(ChatEvent.Failed(result.error)); return }
            history += buildJsonObject { put("role", "assistant"); put("content", JsonArray(result.blocks)) }
            if (result.stopReason != "tool_use") { emit(ChatEvent.Finished(inTokens, outTokens)); return }
            val results = mutableListOf<JsonElement>()
            for (b in result.blocks) {
                val o = b.jsonObject
                if (o["type"]?.jsonPrimitive?.content != "tool_use") continue
                val id = o["id"]!!.jsonPrimitive.content; val name = o["name"]!!.jsonPrimitive.content
                val (content, isError) = runTool(name, o["input"]?.jsonObject ?: JsonObject(emptyMap()))
                emit(ChatEvent.ToolResult(id, name, isError))
                results += buildJsonObject {
                    put("type", "tool_result"); put("tool_use_id", id); if (isError) put("is_error", true)
                    put("content", JsonArray(content.map { c ->
                        when (c) {
                            is Content.Text -> buildJsonObject { put("type", "text"); put("text", c.text) }
                            is Content.Image -> buildJsonObject { put("type", "image"); put("source", buildJsonObject { put("type", "base64"); put("media_type", c.mediaType); put("data", c.base64) }) }
                        }
                    }))
                }
            }
            history += buildJsonObject { put("role", "user"); put("content", JsonArray(results)) }
        }
        emit(ChatEvent.Failed("Stopped after 80 steps."))
    }

    private class StreamResult(val blocks: List<JsonElement>, val stopReason: String?, val inputTokens: Int, val outputTokens: Int, val error: String?)

    private suspend fun stream(history: List<JsonObject>, system: String, tools: List<JsonObject>, emit: suspend (ChatEvent) -> Unit): StreamResult = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("model", model()); put("max_tokens", 8192); put("stream", true)
            put("system", JsonArray(listOf(buildJsonObject { put("type", "text"); put("text", system); put("cache_control", buildJsonObject { put("type", "ephemeral") }) })))
            put("tools", JsonArray(tools.mapIndexed { i, t -> if (i == tools.lastIndex) JsonObject(t + ("cache_control" to buildJsonObject { put("type", "ephemeral") })) else t }))
            put("messages", JsonArray(history))
        }
        val conn = (URL("$baseUrl/v1/messages").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"; doOutput = true; connectTimeout = 20_000; readTimeout = 180_000
            setRequestProperty("x-api-key", apiKey()); setRequestProperty("anthropic-version", "2023-06-01"); setRequestProperty("content-type", "application/json")
        }
        try {
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            if (conn.responseCode !in 200..299) {
                val err = (conn.errorStream ?: conn.inputStream).bufferedReader().readText()
                val msg = runCatching { json.parseToJsonElement(err).jsonObject["error"]?.jsonObject?.get("message")?.jsonPrimitive?.content }.getOrNull()
                return@withContext StreamResult(emptyList(), null, 0, 0, msg ?: "HTTP ${conn.responseCode}")
            }
            val blocks = sortedMapOf<Int, Block>(); var stop: String? = null; var inT = 0; var outT = 0; var error: String? = null
            val reader: BufferedReader = conn.inputStream.bufferedReader()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                currentCoroutineContext().ensureActive()
                val l = line!!
                if (!l.startsWith("data:")) continue
                val data = runCatching { json.parseToJsonElement(l.removePrefix("data:").trim()).jsonObject }.getOrNull() ?: continue
                when (data["type"]?.jsonPrimitive?.content) {
                    "message_start" -> inT += data["message"]?.jsonObject?.get("usage")?.jsonObject?.get("input_tokens")?.jsonPrimitive?.intOrNull ?: 0
                    "content_block_start" -> {
                        val idx = data["index"]!!.jsonPrimitive.int; val cb = data["content_block"]!!.jsonObject
                        blocks[idx] = Block(cb["type"]!!.jsonPrimitive.content, cb["id"]?.jsonPrimitive?.contentOrNull ?: "", cb["name"]?.jsonPrimitive?.contentOrNull ?: "")
                    }
                    "content_block_delta" -> {
                        val b = blocks[data["index"]!!.jsonPrimitive.int] ?: continue; val d = data["delta"]!!.jsonObject
                        when (d["type"]?.jsonPrimitive?.content) {
                            "text_delta" -> { val t = d["text"]!!.jsonPrimitive.content; b.text.append(t); emit(ChatEvent.TextDelta(t)) }
                            "input_json_delta" -> b.input.append(d["partial_json"]!!.jsonPrimitive.content)
                        }
                    }
                    "message_delta" -> { stop = data["delta"]?.jsonObject?.get("stop_reason")?.jsonPrimitive?.contentOrNull ?: stop; outT = data["usage"]?.jsonObject?.get("output_tokens")?.jsonPrimitive?.intOrNull ?: outT }
                    "error" -> error = data["error"]?.jsonObject?.get("message")?.jsonPrimitive?.contentOrNull ?: "error"
                }
            }
            val out = blocks.values.map { b ->
                when (b.type) {
                    "tool_use" -> {
                        val input = if (b.input.isBlank()) JsonObject(emptyMap()) else runCatching { json.parseToJsonElement(b.input.toString()).jsonObject }.getOrDefault(JsonObject(emptyMap()))
                        emit(ChatEvent.ToolUse(b.id, b.name, input))
                        buildJsonObject { put("type", "tool_use"); put("id", b.id); put("name", b.name); put("input", input) }
                    }
                    else -> buildJsonObject { put("type", "text"); put("text", b.text.toString()) }
                }
            }.filter { it.jsonObject["type"]?.jsonPrimitive?.content != "text" || it.jsonObject["text"]?.jsonPrimitive?.content?.isNotEmpty() == true }
            StreamResult(out, stop, inT, outT, error)
        } finally { conn.disconnect() }
    }
}
