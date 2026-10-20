package app.lumacut.core

import kotlinx.serialization.json.Json

/** Project files are plain JSON with the same field names as the macOS app. Missing fields fall back to their defaults. */
object ProjectIO {
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = true; isLenient = true }
    fun encode(p: Project): String = json.encodeToString(Project.serializer(), p)
    fun decode(text: String): Project = json.decodeFromString(Project.serializer(), text)
}
