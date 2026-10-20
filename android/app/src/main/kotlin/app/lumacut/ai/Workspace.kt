package app.lumacut.ai

import android.content.Context
import android.net.Uri
import android.media.MediaMetadataRetriever
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Folders the user opened in the Files tab. The assistant sees them as virtual paths: /RootName/sub/folder. */
class Workspace(private val ctx: Context) {
    data class Root(val name: String, val uri: String)

    private val prefs = ctx.getSharedPreferences("lumacut", Context.MODE_PRIVATE)
    var roots: List<Root> = load(); private set

    private fun load(): List<Root> = (prefs.getString("roots", "") ?: "").split("\n").filter { it.contains("|") }.map { Root(it.substringBefore("|"), it.substringAfter("|")) }
    private fun save() = prefs.edit().putString("roots", roots.joinToString("\n") { "${it.name}|${it.uri}" }).apply()

    fun add(tree: Uri) {
        try { ctx.contentResolver.takePersistableUriPermission(tree, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
        if (roots.any { it.uri == tree.toString() }) return
        var name = DocumentFile.fromTreeUri(ctx, tree)?.name ?: "Folder"
        val taken = roots.map { it.name }.toSet(); var n = 2; val base = name
        while (name in taken) name = "$base ($n)".also { n++ }
        roots = roots + Root(name, tree.toString()); save()
    }
    fun remove(root: Root) { roots = roots - root; save() }

    fun rootFile(root: Root): DocumentFile? = DocumentFile.fromTreeUri(ctx, Uri.parse(root.uri))

    fun virtualPaths(): List<String> = roots.map { "/${it.name}" }

    fun resolve(path: String): DocumentFile? {
        val parts = path.trim('/').split("/").filter { it.isNotEmpty() }
        val root = roots.firstOrNull { it.name == parts.firstOrNull() } ?: return null
        var f = rootFile(root) ?: return null
        for (p in parts.drop(1)) f = f.findFile(p) ?: return null
        return f
    }

    fun isInside(path: String) = roots.any { path == "/${it.name}" || path.startsWith("/${it.name}/") }

    fun kind(f: DocumentFile): String? {
        val mime = f.type ?: ""
        return when {
            mime.startsWith("video/") -> "video"; mime.startsWith("audio/") -> "audio"; mime.startsWith("image/") -> "image"
            else -> when (f.name?.substringAfterLast('.', "")?.lowercase()) {
                in setOf("mp4", "mov", "m4v", "mkv", "webm", "3gp", "avi") -> "video"; in setOf("mp3", "m4a", "wav", "aac", "flac", "ogg") -> "audio"; in setOf("jpg", "jpeg", "png", "heic", "webp", "gif") -> "image"; else -> null
            }
        }
    }

    fun children(dir: DocumentFile): List<DocumentFile> = dir.listFiles().sortedWith(compareBy({ !it.isDirectory }, { it.name?.lowercase() }))

    fun mediaFiles(dir: DocumentFile, limit: Int = 500): List<DocumentFile> {
        val out = mutableListOf<DocumentFile>()
        fun walk(d: DocumentFile) { for (c in children(d)) { if (out.size >= limit) return; if (c.isDirectory) walk(c) else if (kind(c) != null) out += c } }
        walk(dir); return out
    }

    private fun clock(s: Double): String { val t = s.toInt(); return "%d:%02d".format(t / 60, t % 60) }

    /** Names, kinds, sizes and, for media, the length and resolution read from the file's headers only: nothing is decoded or viewed. */
    suspend fun describe(path: String, depth: Int, maxLines: Int = 150): String = withContext(Dispatchers.IO) {
        val folder = resolve(path) ?: return@withContext "Folder not found: $path"
        val lines = mutableListOf<String>(); val counts = mutableMapOf("video" to 0, "audio" to 0, "image" to 0, "other" to 0)
        var videoSeconds = 0.0; var bytes = 0L; var truncated = false
        fun walk(dir: DocumentFile, level: Int) {
            val indent = "  ".repeat(level + 1)
            for (f in children(dir)) {
                if (f.isDirectory) {
                    val n = mediaFiles(f, 2000).size
                    if (lines.size < maxLines) lines += "$indent[folder] ${f.name}/  ($n media file${if (n == 1) "" else "s"})" else truncated = true
                    if (level + 1 < depth) walk(f, level + 1)
                } else {
                    val k = kind(f); bytes += f.length()
                    if (k == null) { counts["other"] = counts["other"]!! + 1; continue }
                    counts[k] = counts[k]!! + 1
                    var detail = android.text.format.Formatter.formatShortFileSize(ctx, f.length())
                    if (k != "image") {
                        val r = MediaMetadataRetriever()
                        try {
                            r.setDataSource(ctx, f.uri)
                            val d = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull()?.div(1000)
                            if (d != null) { detail = "${clock(d)} · $detail"; if (k == "video") videoSeconds += d }
                            if (k == "video") { val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH); val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT); if (w != null && h != null) detail += " · ${w}x$h" }
                        } catch (_: Exception) {} finally { r.release() }
                    }
                    if (lines.size < maxLines) lines += "$indent[$k] ${f.name}  $detail" else truncated = true
                }
            }
        }
        walk(folder, 0)
        val tail = "Summary (shown levels): ${counts["video"]} video (${clock(videoSeconds)} total), ${counts["audio"]} audio, ${counts["image"]} images, ${counts["other"]} other files, " +
            android.text.format.Formatter.formatShortFileSize(ctx, bytes) + "." + if (truncated) " Listing cut at $maxLines lines: browse a subfolder for more." else ""
        (listOf("Folder $path") + lines + tail).joinToString("\n")
    }
}
