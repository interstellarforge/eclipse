package app.lumacut

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Self-update from GitHub Releases: tags `android-v<versionCode>` carrying one .apk asset (see scripts/publish-android.sh). */
object Updater {
    private const val REPO = "interstellarforge/eclipse"
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable private data class Asset(val name: String, val browser_download_url: String, val digest: String? = null)
    @Serializable private data class Release(val tag_name: String, val name: String? = null, val body: String? = null, val draft: Boolean = false, val prerelease: Boolean = false, val assets: List<Asset> = emptyList())

    data class Update(val versionCode: Long, val name: String, val notes: String, val url: String, val sha256: String?)

    fun installedCode(ctx: Context): Long = ctx.packageManager.getPackageInfo(ctx.packageName, 0).longVersionCode

    /** The newest Android release if it is newer than the installed build, else null. Throws on network errors. */
    suspend fun check(ctx: Context): Update? = withContext(Dispatchers.IO) {
        val text = open("https://api.github.com/repos/$REPO/releases?per_page=20").inputStream.bufferedReader().use { it.readText() }
        val best = json.decodeFromString<List<Release>>(text).asSequence()
            .filter { !it.draft && !it.prerelease && it.tag_name.startsWith("android-v") }
            .mapNotNull { r -> r.tag_name.removePrefix("android-v").toLongOrNull()?.let { it to r } }
            .maxByOrNull { it.first } ?: return@withContext null
        val (code, r) = best
        val apk = r.assets.firstOrNull { it.name.endsWith(".apk") } ?: return@withContext null
        if (code <= installedCode(ctx)) null else Update(code, r.name ?: r.tag_name, r.body.orEmpty(), apk.browser_download_url, apk.digest?.removePrefix("sha256:"))
    }

    suspend fun download(ctx: Context, u: Update, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(ctx.cacheDir, "updates").also { it.deleteRecursively(); it.mkdirs() }
        val out = File(dir, "Eclipse-${u.versionCode}.apk")
        val conn = open(u.url); val total = conn.contentLengthLong; var done = 0L
        val md = MessageDigest.getInstance("SHA-256")
        conn.inputStream.use { input -> out.outputStream().use { o ->
            val buf = ByteArray(64 * 1024)
            while (true) { val n = input.read(buf); if (n < 0) break; o.write(buf, 0, n); md.update(buf, 0, n); done += n; if (total > 0) onProgress(done.toFloat() / total) }
        } }
        val got = md.digest().joinToString("") { "%02x".format(it) }
        if (u.sha256 != null && !got.equals(u.sha256, ignoreCase = true)) { out.delete(); error("Download is corrupt (checksum mismatch)") }
        out
    }

    /** Opens Android's installer. Returns false when the user first has to allow installs from Eclipse (settings opened). */
    fun install(ctx: Context, apk: File): Boolean {
        if (!ctx.packageManager.canRequestPackageInstalls()) {
            ctx.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return false
        }
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", apk)
        ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    private fun open(url: String) = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 15_000; readTimeout = 30_000; setRequestProperty("Accept", "application/vnd.github+json"); instanceFollowRedirects = true
    }.also { if (it.responseCode !in 200..299) error("GitHub answered ${it.responseCode}") }
}
