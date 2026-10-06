package cc.hafa.subtube.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import cc.hafa.subtube.data.ThemeMode

/** Sunflower, the one brand colour. */
val Sunflower: Color = Color(0xFFFFC20E)

/** Text and icons on a Sunflower fill. */
val Ink: Color = Color(0xFF2A1F00)

/** The dark backdrop behind the video player. */
val PlayerBackdrop: Color = Color(0xFF0E0C08)

/*
 * Material's text buttons, focus rings and progress indicators draw in
 * `primary`, which here is Sunflower: unreadable on the light surfaces. Those
 * take [SubtubeColors.accent] instead (dark gold on light, Sunflower on dark).
 */
private val LightScheme = lightColorScheme(
    primary = Sunflower,
    onPrimary = Ink,
    primaryContainer = Color(0xFFFFE08A),
    onPrimaryContainer = Ink,
    inversePrimary = Color(0xFF8A6100),
    secondary = Color(0xFF6B5D3F),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF2E4C4),
    onSecondaryContainer = Color(0xFF261C05),
    tertiary = Color(0xFF8A6100),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFF4CC),
    onTertiaryContainer = Color(0xFF5C4300),
    background = Color(0xFFFFFAF0),
    onBackground = Color(0xFF1F1B12),
    surface = Color(0xFFFFFAF0),
    onSurface = Color(0xFF1F1B12),
    surfaceVariant = Color(0xFFECE7DA),
    onSurfaceVariant = Color(0xFF4D4639),
    surfaceTint = Color(0xFF8A6100),
    surfaceBright = Color(0xFFFFFAF0),
    surfaceDim = Color(0xFFE6DFCF),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFBF4E8),
    surfaceContainer = Color(0xFFF6EFE0),
    surfaceContainerHigh = Color(0xFFF3EBDB),
    surfaceContainerHighest = Color(0xFFF0E8D6),
    outline = Color(0xFF7D7462),
    outlineVariant = Color(0xFFE7E1D3),
    inverseSurface = Color(0xFF353026),
    inverseOnSurface = Color(0xFFF8F0E2),
)

private val DarkScheme = darkColorScheme(
    primary = Sunflower,
    onPrimary = Ink,
    primaryContainer = Color(0xFF5C4300),
    onPrimaryContainer = Color(0xFFFFE08A),
    inversePrimary = Color(0xFF8A6100),
    secondary = Color(0xFFD6C6A4),
    onSecondary = Color(0xFF3A2F19),
    secondaryContainer = Color(0xFF4F4532),
    onSecondaryContainer = Color(0xFFF2E4C4),
    tertiary = Sunflower,
    onTertiary = Ink,
    tertiaryContainer = Color(0xFF5C4300),
    onTertiaryContainer = Color(0xFFFFF4CC),
    background = Color(0xFF16130B),
    onBackground = Color(0xFFEAE1D0),
    surface = Color(0xFF16130B),
    onSurface = Color(0xFFEAE1D0),
    surfaceVariant = Color(0xFF2E2A21),
    onSurfaceVariant = Color(0xFFD0C5B2),
    surfaceTint = Sunflower,
    surfaceBright = Color(0xFF3D382E),
    surfaceDim = Color(0xFF16130B),
    surfaceContainerLowest = Color(0xFF110E07),
    surfaceContainerLow = Color(0xFF1F1B12),
    surfaceContainer = Color(0xFF231F16),
    surfaceContainerHigh = Color(0xFF2E2A20),
    surfaceContainerHighest = Color(0xFF39342A),
    outline = Color(0xFF998F7C),
    outlineVariant = Color(0xFF4D4639),
    inverseSurface = Color(0xFFEAE1D0),
    inverseOnSurface = Color(0xFF353026),
)

/** Brand colours Material's scheme has no slot for. */
@Immutable
data class SubtubeColors(
    /** Text-coloured accents: links, text buttons, focus rings, icons. */
    val accent: Color,
    /** A thumbnail before its image loads. */
    val placeholder: Color,
    /** Whether this is the dark theme, for what has its own dark colours outside the scheme (Google's sign-in button). */
    val dark: Boolean,
)

private val LightBrand = SubtubeColors(
    accent = Color(0xFF8A6100),
    placeholder = Color(0xFFECE7DA),
    dark = false,
)

private val DarkBrand = SubtubeColors(
    accent = Sunflower,
    placeholder = Color(0xFF2E2A21),
    dark = true,
)

private val LocalSubtubeColors = staticCompositionLocalOf { LightBrand }

/** The brand colours of the current theme. */
val MaterialTheme.brand: SubtubeColors
    @Composable get() = LocalSubtubeColors.current

/** Whether [mode] resolves to dark right now. */
@Composable
fun ThemeMode.isDark(): Boolean = when (this) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

/** The light or dark Material scheme. */
fun subtubeColorScheme(dark: Boolean): ColorScheme = if (dark) DarkScheme else LightScheme

/** subtube's Material 3 theme: always Sunflower, never the wallpaper's colours. */
@Composable
fun SubtubeTheme(dark: Boolean, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalSubtubeColors provides if (dark) DarkBrand else LightBrand) {
        MaterialTheme(colorScheme = subtubeColorScheme(dark), content = content)
    }
}
