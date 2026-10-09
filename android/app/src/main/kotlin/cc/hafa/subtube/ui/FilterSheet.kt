package cc.hafa.subtube.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.ContentMode
import cc.hafa.subtube.core.FilterMode
import cc.hafa.subtube.core.FilterScope
import cc.hafa.subtube.core.LiveFilter
import cc.hafa.subtube.core.ShortsFilter
import cc.hafa.subtube.core.compileFilter
import cc.hafa.subtube.core.editorTopics
import cc.hafa.subtube.core.patternToPhrases
import cc.hafa.subtube.core.phrasesToPattern
import cc.hafa.subtube.core.topicLabel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What ends a typed phrase, besides the keyboard's Done. */
private const val PHRASE_END = ','

/** How long typing in the minimum length pauses before the list is filtered by it. */
private const val MINIMUM_PAUSE_MS = 400L

/** Kept at the start of the phrase field so a Backspace in an empty field has something to delete, which is how it is noticed. */
private const val SENTINEL = "\u200B"

/**
 * One channel's filters in a bottom sheet over its page. Every change applies
 * and syncs at once, and the page behind follows. The filter's pattern is
 * edited as the phrases it looks for; a saved pattern that is not phrases
 * shows as none.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun FilterSheet(viewModel: SubtubeViewModel, channel: ChannelFilter, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val update: (ChannelFilter) -> Unit = viewModel::updateFilter
    val compiled = compileFilter(channel)
    var minimum by remember(channel.channelId) { mutableStateOf(channel.minDurationSeconds?.takeIf { seconds -> seconds > 0 }?.toString().orEmpty()) }
    val scope = rememberCoroutineScope()
    val currentChannel by rememberUpdatedState(channel)
    // typing re-filters once it pauses, and when the sheet closes, not at every digit
    fun saveMinimum() {
        val edited = currentChannel
        // more digits than an Int holds is still a minimum: the largest
        val seconds = (minimum.toIntOrNull() ?: Int.MAX_VALUE.takeIf { minimum.isNotEmpty() })?.takeIf { it > 0 }
        if (seconds != edited.minDurationSeconds?.takeIf { it > 0 }) {
            update(edited.copy(minDurationSeconds = seconds))
        }
    }
    LaunchedEffect(minimum) {
        delay(MINIMUM_PAUSE_MS)
        saveMinimum()
    }
    DisposableEffect(channel.channelId) {
        onDispose { saveMinimum() }
    }
    CoversPlayer(viewModel)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(channel.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            AccentTextButton(stringResource(R.string.done), onClick = { scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() } })
        }
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.show_in_feed), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                BrandSwitch(
                    checked = channel.enabled,
                    onCheckedChange = { enabled -> update(channel.copy(enabled = enabled)) },
                    contentDescription = stringResource(R.string.show_in_feed_named, channel.title),
                )
            }
            SectionLabel(stringResource(R.string.show))
            val mode = channel.contentMode ?: ContentMode.VIDEOS
            Segmented(
                options = listOf(ContentMode.VIDEOS to R.string.uploads, ContentMode.PLAYLISTS to R.string.playlists),
                selected = mode,
                onSelect = { choice -> update(channel.copy(contentMode = choice.takeIf { it == ContentMode.PLAYLISTS })) },
            )
            // playlists have no Shorts, broadcasts or length to filter on
            if (mode != ContentMode.PLAYLISTS) {
                SectionLabel(stringResource(R.string.shorts))
                ShortsChoice(
                    selected = channel.shortsFilter ?: ShortsFilter.ALL,
                    onSelect = { choice -> update(channel.copy(shortsFilter = choice.takeUnless { it == ShortsFilter.ALL })) },
                )
                SectionLabel(stringResource(R.string.live))
                Segmented(
                    options = listOf(LiveFilter.ALL to R.string.choice_show, LiveFilter.NORMAL to R.string.choice_hide, LiveFilter.VOD to R.string.choice_only),
                    selected = channel.liveFilter ?: LiveFilter.ALL,
                    onSelect = { choice -> update(channel.copy(liveFilter = choice.takeUnless { it == LiveFilter.ALL })) },
                )
                OutlinedTextField(
                    value = minimum,
                    onValueChange = { text -> minimum = text.filter(Char::isDigit) },
                    label = { Text(stringResource(R.string.hide_videos_under)) },
                    placeholder = { Text("0") },
                    suffix = { Text(stringResource(R.string.seconds)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    colors = brandTextFieldColors(),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            PatternControls(
                phrases = patternToPhrases(channel.regex).orEmpty(),
                mode = channel.mode,
                scope = channel.searchScope ?: FilterScope.TITLE,
                onPhrases = { phrases -> update(channel.copy(regex = phrasesToPattern(phrases))) },
                onMode = { choice -> update(channel.copy(mode = choice)) },
                onScope = { choice -> update(channel.copy(searchScope = choice.takeUnless { it == FilterScope.TITLE })) },
            )
            SectionLabel(stringResource(R.string.letter_case))
            Segmented(
                options = listOf(false to R.string.case_ignore, true to R.string.case_match),
                selected = channel.caseSensitive == true,
                onSelect = { matchCase -> update(channel.copy(caseSensitive = matchCase.takeIf { it })) },
            )
            if (mode != ContentMode.PLAYLISTS) {
                SectionLabel(stringResource(R.string.topics))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (categoryId in editorTopics(viewModel.channelFetched(channel.channelId))) {
                        val selected = categoryId in compiled.topics
                        Chip(
                            topicLabel(categoryId).orEmpty(),
                            onClick = { update(channel.copy(topics = (if (selected) compiled.topics - categoryId else compiled.topics + categoryId).toList())) },
                            selected = selected,
                        )
                    }
                }
                HelpText(stringResource(R.string.topics_help))
            }
        }
    }
}

/** A line under a group of controls saying what they do. */
@Composable
private fun HelpText(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * The phrases a filter looks for, each a chip that is removed when pressed,
 * then the field a new one is typed in: Done or a comma makes the typed phrase
 * a chip, and Backspace in the empty field removes the last one.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PhraseField(phrases: List<String>, onPhrases: (List<String>) -> Unit) {
    // the phrase being typed, not yet a chip
    var draft by remember { mutableStateOf("") }
    var field by remember { mutableStateOf(TextFieldValue(SENTINEL, TextRange(SENTINEL.length))) }
    fun show(text: String) {
        draft = text
        field = TextFieldValue(SENTINEL + text, TextRange(SENTINEL.length + text.length))
    }
    val accent = MaterialTheme.brand.accent
    FlowRow(
        Modifier
            .fillMaxWidth()
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(4.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        for (phrase in phrases) {
            Chip(phrase, onClick = { onPhrases(phrases - phrase) }, removes = true)
        }
        BasicTextField(
            value = field,
            onValueChange = { changed ->
                if (!changed.text.startsWith(SENTINEL)) {
                    // the sentinel went: Backspace at the very start
                    if (draft.isEmpty()) {
                        onPhrases(phrases.dropLast(1))
                    }
                    show(changed.text.replace(SENTINEL, ""))
                } else {
                    val parts = changed.text.removePrefix(SENTINEL).split(PHRASE_END)
                    if (parts.size > 1) {
                        onPhrases(phrases + parts.dropLast(1))
                        show(parts.last())
                    } else {
                        draft = parts.last()
                        field = changed.copy(selection = TextRange(maxOf(SENTINEL.length, changed.selection.start), maxOf(SENTINEL.length, changed.selection.end)))
                    }
                }
            },
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(accent),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(
                onDone = {
                    if (draft.isNotBlank()) {
                        onPhrases(phrases + draft)
                    }
                    show("")
                },
            ),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (draft.isEmpty()) {
                        Text(stringResource(R.string.add_phrase), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    inner()
                }
            },
            modifier = Modifier.weight(1f).widthIn(min = 120.dp).heightIn(min = 48.dp).wrapContentHeight(),
        )
    }
}

/**
 * The phrase field, labelled by what the phrases are matched in, the Matches
 * choice and the choice of what they are matched in: the filter editor's
 * pattern group. [onPhrases] gets the whole new list when one is added or
 * removed.
 */
@Composable
fun PatternControls(
    phrases: List<String>,
    mode: FilterMode,
    scope: FilterScope,
    onPhrases: (List<String>) -> Unit,
    onMode: (FilterMode) -> Unit,
    onScope: (FilterScope) -> Unit,
) {
    SectionLabel(stringResource(patternLabel(scope)))
    PhraseField(phrases, onPhrases)
    HelpText(stringResource(R.string.phrases_help))
    SectionLabel(stringResource(R.string.matches))
    Segmented(
        options = listOf(FilterMode.EXCLUDE to R.string.choice_hide, FilterMode.INCLUDE to R.string.choice_show),
        selected = mode,
        onSelect = onMode,
    )
    SectionLabel(stringResource(R.string.match_in))
    Segmented(
        options = listOf(FilterScope.TITLE to R.string.scope_title, FilterScope.BOTH to R.string.scope_both, FilterScope.DESCRIPTION to R.string.scope_description),
        selected = scope,
        onSelect = onScope,
    )
}

/** The phrase field's label for what the phrases are matched in. */
@StringRes
private fun patternLabel(scope: FilterScope): Int = when (scope) {
    FilterScope.TITLE -> R.string.title_pattern
    FilterScope.DESCRIPTION -> R.string.description_pattern
    FilterScope.BOTH -> R.string.text_pattern
}

/** A small heading over a group of filter controls. */
@Composable
fun SectionLabel(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 4.dp))
}

/** The Shorts choice: show, hide, or only Shorts; it goes under a "Shorts" heading. */
@Composable
fun ShortsChoice(selected: ShortsFilter, onSelect: (ShortsFilter) -> Unit) {
    Segmented(
        options = listOf(ShortsFilter.ALL to R.string.choice_show, ShortsFilter.NORMAL to R.string.choice_hide, ShortsFilter.SHORTS to R.string.choice_only),
        selected = selected,
        onSelect = onSelect,
    )
}
