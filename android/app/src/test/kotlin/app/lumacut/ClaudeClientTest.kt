package app.lumacut

import app.lumacut.ai.ChatEvent
import app.lumacut.ai.ClaudeClient
import app.lumacut.core.*
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ClaudeClientTest {
    private lateinit var server: MockWebServer
    private fun requests() = generateSequence { server.takeRequest(100, java.util.concurrent.TimeUnit.MILLISECONDS) }.toList()

    @Before fun start() { server = MockWebServer(); server.start() }
    @After fun stop() = server.shutdown()

    private fun respond(body: String) = server.enqueue(MockResponse().setHeader("content-type", "text/event-stream").setBody(body))

    private fun sse(vararg events: Pair<String, String>) = events.joinToString("") { "event: ${it.first}\ndata: ${it.second}\n\n" }

    @Test fun toolLoopRunsToolsAndStreamsText() = runBlocking {
        respond(sse(
            "message_start" to """{"type":"message_start","message":{"usage":{"input_tokens":10}}}""",
            "content_block_start" to """{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}""",
            "content_block_delta" to """{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me look. "}}""",
            "content_block_start" to """{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_1","name":"get_project","input":{}}}""",
            "content_block_delta" to """{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}""",
            "message_delta" to """{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":7}}"""))
        respond(sse(
            "content_block_start" to """{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}""",
            "content_block_delta" to """{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done."}}""",
            "message_delta" to """{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"""))
        val editor = Editor(); val host = FakeHost()
        val registry = ToolRegistry({ editor }, host, Skills(MapSkillSource(emptyMap())), java.io.File("src/main/assets/tools.json").readText())
        val history = mutableListOf(buildJsonObject { put("role", "user"); put("content", "hi") })
        val events = mutableListOf<ChatEvent>()
        ClaudeClient({ "sk-test" }, { "claude-sonnet-5-5" }, server.url("/").toString().trimEnd('/')).run(history, { "system text" }, { registry.definitions() }, { n, a -> registry.call(n, a) }) { events += it }

        assertTrue(events.any { it is ChatEvent.TextDelta && it.text == "Let me look. " })
        assertTrue(events.any { it is ChatEvent.ToolUse && it.name == "get_project" })
        assertTrue(events.any { it is ChatEvent.ToolResult && it.name == "get_project" && !it.isError })
        assertTrue(events.last() is ChatEvent.Finished)
        val reqs = requests(); assertEquals(2, reqs.size)
        assertEquals("sk-test", reqs[0].getHeader("x-api-key")); assertEquals("2023-06-01", reqs[0].getHeader("anthropic-version"))
        val first = Json.parseToJsonElement(reqs[0].body.readUtf8()).jsonObject
        assertEquals("claude-sonnet-5-5", first["model"]!!.jsonPrimitive.content)
        assertTrue(first["tools"]!!.jsonArray.size > 30)
        // The second request carries the assistant's tool_use and our tool_result
        val second = Json.parseToJsonElement(reqs[1].body.readUtf8()).jsonObject["messages"]!!.jsonArray
        assertEquals(3, second.size)
        assertEquals("tool_result", second[2].jsonObject["content"]!!.jsonArray[0].jsonObject["type"]!!.jsonPrimitive.content)
        assertEquals(4, history.size)
    }

    @Test fun apiErrorsBecomeFailedEvents() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(401).setBody("""{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"""))
        val events = mutableListOf<ChatEvent>()
        val registry = ToolRegistry({ Editor() }, FakeHost(), Skills(MapSkillSource(emptyMap())), "[]")
        ClaudeClient({ "bad" }, { "m" }, server.url("/").toString().trimEnd('/')).run(mutableListOf(buildJsonObject { put("role", "user"); put("content", "hi") }), { "" }, { emptyList() }, { n, a -> registry.call(n, a) }) { events += it }
        assertEquals(listOf<ChatEvent>(ChatEvent.Failed("invalid x-api-key")), events)
    }
}
