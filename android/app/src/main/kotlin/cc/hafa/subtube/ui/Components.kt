package cc.hafa.subtube.ui

import android.text.format.DateFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldColors
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.Playlist
import cc.hafa.subtube.core.Video
import cc.hafa.subtube.core.formatDuration
import coil3.compose.AsyncImage
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/** The bottom navigation bar shared by the three tabs; the current tab's icon and label sit on one highlight. */
@Composable
fun MainNavigationBar(current: Screen, onSelect: (Screen) -> Unit) {
    val tabs = listOf(
        Triple(Screen.Feed, SubtubeIcons.Feed, R.string.tab_feed),
        Triple(Screen.Channels, SubtubeIcons.Channels, R.string.channels),
        Triple(Screen.Settings, SubtubeIcons.Settings, R.string.settings),
    )
    val dock = LocalPlayerDock.current
    NavigationBar(
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        // the minimized player sits above the bar
        modifier = Modifier.onGloballyPositioned { coordinates -> dock.barTop = coordinates.boundsInRoot().top },
    ) {
        for ((screen, icon, label) in tabs) {
            val selected = screen == current
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Column(
                    Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
                        .selectable(selected = selected, role = Role.Tab, onClick = { onSelect(screen) })
                        .widthIn(min = 88.dp)
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    val tint = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
                    Icon(icon, contentDescription = null, tint = tint)
                    Text(stringResource(label), style = MaterialTheme.typography.labelMedium, color = tint, maxLines = 1)
                }
            }
        }
    }
}

/** The hull's share of the square logo drawing's height; it is centred in it, the tower above. */
private const val LOGO_HULL_HEIGHT = 0.518f

/** The hull's share of the square logo drawing's width. */
private const val LOGO_HULL_WIDTH = 0.74f

/** The name's line height as a multiple of its font size. */
private const val WORDMARK_LINE_HEIGHT = 1.2f

/**
 * The logo beside the name. The logo's hull is as tall as the name's line and
 * centred on it; only the hull takes up room, so the tower rises above the
 * line without making the row taller.
 */
@Composable
fun Wordmark(modifier: Modifier = Modifier, fontSize: Int = 22) {
    val lineHeight = (fontSize * WORDMARK_LINE_HEIGHT).sp
    val hull = with(LocalDensity.current) { lineHeight.toDp() }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(hull * 0.3f)) {
        Box(Modifier.size(width = hull * (LOGO_HULL_WIDTH / LOGO_HULL_HEIGHT), height = hull), contentAlignment = Alignment.Center) {
            Image(painterResource(R.drawable.logo), contentDescription = null, modifier = Modifier.requiredSize(hull / LOGO_HULL_HEIGHT))
        }
        Text(stringResource(R.string.app_name), fontSize = fontSize.sp, lineHeight = lineHeight, fontWeight = FontWeight.Bold)
    }
}

/** A channel's avatar, or its initial on a Sunflower tint while there is none. */
@Composable
fun ChannelAvatar(title: String, thumbnail: String, modifier: Modifier = Modifier, size: Dp = 40.dp) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title.trim().take(1).uppercase(),
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            style = MaterialTheme.typography.titleMedium,
        )
        if (thumbnail.isNotEmpty()) {
            AsyncImage(model = thumbnail, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

/** A thumbnail filling its box, over a flat placeholder. */
@Composable
fun Thumbnail(url: String, modifier: Modifier = Modifier) {
    Box(modifier.background(MaterialTheme.brand.placeholder)) {
        if (url.isNotEmpty()) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

/** A small label over a thumbnail: duration, Short, watched, playlist size. */
@Composable
fun ThumbnailBadge(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    Row(
        modifier
            .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
        }
        Text(text, color = Color.White, style = MaterialTheme.typography.labelMedium)
    }
}

/** A switch in the brand style: Sunflower track, ink thumb with a check. */
@Composable
fun BrandSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit, contentDescription: String?, modifier: Modifier = Modifier) {
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        thumbContent = if (checked) {
            { Icon(SubtubeIcons.Check, contentDescription = null, modifier = Modifier.size(SwitchDefaults.IconSize)) }
        } else {
            null
        },
        colors = SwitchDefaults.colors(checkedIconColor = MaterialTheme.colorScheme.primary),
        modifier = modifier.then(
            if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier,
        ),
    )
}

/** A text button in the accent colour, never Sunflower text on a light surface. */
@Composable
fun AccentTextButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.brand.accent),
    ) {
        Text(text)
    }
}

/** The full-width Sunflower call to action at the foot of a first-run step. */
@Composable
fun BigButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: ButtonColors = ButtonDefaults.buttonColors(),
    content: @Composable () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        colors = colors,
        contentPadding = PaddingValues(horizontal = 24.dp),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        content()
    }
}

/**
 * Google's standard "Sign in with Google" button: its four-colour mark on a
 * neutral fill, white on light and near-black on dark, as its branding
 * guidelines set out. Every place the app offers Google sign-in uses it.
 * While [busy] it shows a spinner and can't be pressed.
 */
@Composable
fun GoogleSignInButton(onClick: () -> Unit, busy: Boolean, modifier: Modifier = Modifier) {
    val dark = MaterialTheme.brand.dark
    val text = if (dark) Color(0xFFE3E3E3) else Color(0xFF1F1F1F)
    val fill = if (dark) Color(0xFF131314) else Color.White
    Button(
        onClick = onClick,
        enabled = !busy,
        colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = text, disabledContainerColor = fill, disabledContentColor = text),
        border = BorderStroke(1.dp, if (dark) Color(0xFF8E918F) else Color(0xFF747775)),
        contentPadding = PaddingValues(horizontal = 12.dp),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(color = text, modifier = Modifier.size(24.dp), strokeWidth = 3.dp)
        } else {
            Image(painterResource(R.drawable.google_g), contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(12.dp))
            Text(stringResource(R.string.sign_in_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Medium)
        }
    }
}

/**
 * The "Search channels" field over or above a list of channel rows; every
 * list of channels searches with it and with `matchesSearch`.
 */
@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.search_channels)
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(label) },
        leadingIcon = { Icon(SubtubeIcons.Search, contentDescription = null) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        shape = RoundedCornerShape(28.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            cursorColor = MaterialTheme.brand.accent,
        ),
        modifier = modifier.semantics { contentDescription = label },
    )
}

/**
 * One choice of [options], each a value and its label's string resource, as a
 * full-width row of joined buttons: every single-choice control in the app.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <Option> Segmented(options: List<Pair<Option, Int>>, selected: Option, onSelect: (Option) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (option, label) ->
            SegmentedButton(
                selected = option == selected,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                icon = { if (option == selected) Icon(SubtubeIcons.Check, null, Modifier.size(18.dp)) },
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                Text(stringResource(label), maxLines = 1)
            }
        }
    }
}

/** A progress spinner in the accent colour. */
@Composable
fun Spinner(modifier: Modifier = Modifier, size: Dp = 32.dp) {
    CircularProgressIndicator(color = MaterialTheme.brand.accent, modifier = modifier.size(size), strokeWidth = 3.dp)
}

/** Outlined text field colours with the accent in place of Sunflower. */
@Composable
fun brandTextFieldColors(): TextFieldColors {
    val accent = MaterialTheme.brand.accent
    return OutlinedTextFieldDefaults.colors(
        focusedBorderColor = accent,
        focusedLabelColor = accent,
        cursorColor = accent,
        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
    )
}

/** An entry's publish date in short form ("Sep 24"), with the year when it isn't this one. */
@Composable
fun shortDate(publishedAt: String): String {
    val locale = LocalConfiguration.current.locales[0]
    return remember(publishedAt, locale) {
        try {
            val date = Instant.parse(publishedAt).atZone(ZoneId.systemDefault()).toLocalDate()
            val skeleton = if (date.year == LocalDate.now().year) "MMMd" else "MMMdy"
            date.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
        } catch (_: DateTimeParseException) {
            ""
        }
    }
}

/** A video's length, a playlist's video count, or null when there's nothing to show. */
fun cornerLabel(item: FeedItem): String? = when (item) {
    is Video -> item.durationSeconds?.takeIf { seconds -> seconds > 0 }?.let(::formatDuration)
    is Playlist -> item.itemCount.toString()
}
