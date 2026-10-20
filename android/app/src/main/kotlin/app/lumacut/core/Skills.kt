package app.lumacut.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

data class Skill(val name: String, val summary: String, val body: String, val builtIn: Boolean = true)

/** Where skill texts come from: the app's assets, or a map in tests. */
interface SkillSource {
    fun index(): List<Pair<String, String>>      // name to one-line summary
    fun body(name: String): String?
}

class MapSkillSource(private val skills: Map<String, Pair<String, String>>) : SkillSource {
    override fun index() = skills.map { it.key to it.value.first }
    override fun body(name: String) = skills[name]?.second
}

@Serializable
private data class SkillIndexEntry(val name: String, val summary: String)

/** Reads the skills the app ships (generated from the macOS app) from assets/skills. */
class AssetSkillSource(private val read: (String) -> String?) : SkillSource {
    private val entries: List<SkillIndexEntry> by lazy {
        read("skills/index.json")?.let { Json { ignoreUnknownKeys = true }.decodeFromString<List<SkillIndexEntry>>(it) } ?: emptyList()
    }
    override fun index() = entries.map { it.name to it.summary }
    override fun body(name: String) = read("skills/$name.md")
}

/** Director skills the assistant reads through get_skill; the user's own .md files add to or replace them. */
class Skills(private val source: SkillSource, private val userSkills: () -> List<Skill> = { emptyList() }) {
    fun all(): List<Skill> {
        val list = source.index().map { (n, s) -> Skill(n, s, source.body(n) ?: "") }.toMutableList()
        for (u in userSkills()) { val i = list.indexOfFirst { it.name == u.name }; if (i >= 0) list[i] = u else list += u }
        return list
    }
    fun get(name: String): Skill? = all().firstOrNull { it.name == name }
}
