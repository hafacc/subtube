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
val Ink: Color = Color(0xFF1B1E24)

/** The dark backdrop behind the video player. */
val PlayerBackdrop: Color = Color(0xFF0B0C0F)

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
    secondary = Color(0xFF575C66),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE8EAEE),
    onSecondaryContainer = Color(0xFF1A1C20),
    tertiary = Color(0xFF8A6100),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFF4CC),
    onTertiaryContainer = Color(0xFF23262C),
    background = Color(0xFFFFFFFF),
    onBackground = Color(0xFF1A1C20),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1A1C20),
    surfaceVariant = Color(0xFFE6E8EC),
    onSurfaceVariant = Color(0xFF575C66),
    surfaceTint = Color(0xFF8A6100),
    surfaceBright = Color(0xFFFFFFFF),
    surfaceDim = Color(0xFFDCDFE4),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF9FAFB),
    surfaceContainer = Color(0xFFF5F6F8),
    surfaceContainerHigh = Color(0xFFEFF1F4),
    surfaceContainerHighest = Color(0xFFEAECF0),
    outline = Color(0xFF737882),
    outlineVariant = Color(0xFFE1E4E8),
    inverseSurface = Color(0xFF2F3238),
    inverseOnSurface = Color(0xFFF1F3F5),
)

private val DarkScheme = darkColorScheme(
    primary = Sunflower,
    onPrimary = Ink,
    primaryContainer = Color(0xFF2B2E35),
    onPrimaryContainer = Color(0xFFFFD75A),
    inversePrimary = Color(0xFF8A6100),
    secondary = Color(0xFFC3C7CE),
    onSecondary = Color(0xFF2B2E35),
    secondaryContainer = Color(0xFF3D4148),
    onSecondaryContainer = Color(0xFFE1E4E8),
    tertiary = Sunflower,
    onTertiary = Ink,
    tertiaryContainer = Color(0xFF2B2E35),
    onTertiaryContainer = Color(0xFFFFD75A),
    background = Color(0xFF121418),
    onBackground = Color(0xFFEEF0F3),
    surface = Color(0xFF121418),
    onSurface = Color(0xFFEEF0F3),
    surfaceVariant = Color(0xFF282B31),
    onSurfaceVariant = Color(0xFFABB0B9),
    surfaceTint = Sunflower,
    surfaceBright = Color(0xFF383B42),
    surfaceDim = Color(0xFF121418),
    surfaceContainerLowest = Color(0xFF0D0F12),
    surfaceContainerLow = Color(0xFF1A1C21),
    surfaceContainer = Color(0xFF1E2126),
    surfaceContainerHigh = Color(0xFF282B31),
    surfaceContainerHighest = Color(0xFF33363D),
    outline = Color(0xFF8D929B),
    outlineVariant = Color(0xFF44474F),
    inverseSurface = Color(0xFFE8EAEE),
    inverseOnSurface = Color(0xFF2F3238),
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
    placeholder = Color(0xFFE6E8EC),
    dark = false,
)

private val DarkBrand = SubtubeColors(
    accent = Sunflower,
    placeholder = Color(0xFF282B31),
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
