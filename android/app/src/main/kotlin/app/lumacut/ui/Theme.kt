package app.lumacut.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object Pal {
    val background = Color(0xFF080A18)
    val panel = Color(0xFF0D1024)
    val raised = Color(0xFF141934)
    val hover = Color(0xFF1D2347)
    val stroke = Color(0xFF252C55)
    val text = Color(0xFFECECF1)
    val dim = Color(0xFF9A9BA8)
    val accent = Color(0xFF7B3DFF)
    val accentSoft = Color(0x337B3DFF)
    val video = Color(0xFF3B6BC4)
    val audio = Color(0xFF6A45E0)
    val title = Color(0xFF8A2FB8)
    val overlay = Color(0xFF2E7F8C)
    val transition = Color(0xFFF08A24)
    val danger = Color(0xFFE5484D)
}

private val scheme = darkColorScheme(
    primary = Pal.accent, onPrimary = Color.White, secondary = Pal.accent, background = Pal.background, onBackground = Pal.text,
    surface = Pal.panel, onSurface = Pal.text, surfaceVariant = Pal.raised, onSurfaceVariant = Pal.dim, outline = Pal.stroke,
    surfaceContainer = Pal.panel, surfaceContainerHigh = Pal.raised, surfaceContainerHighest = Pal.hover, error = Pal.danger,
)

@Composable
fun EclipseTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = scheme, content = content)
