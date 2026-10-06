package cc.hafa.subtube.ui

import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.ChipTitle
import cc.hafa.subtube.core.FeedSort
import cc.hafa.subtube.core.TimeChip
import cc.hafa.subtube.core.WatchedMode
import cc.hafa.subtube.core.topicLabel

private val ChipShape = RoundedCornerShape(16.dp)

/** How tall every chip's box is. */
private val ChipHeight = 32.dp

/** The feed sorts with their labels, in the order the sort chip moves through them. */
private val FEED_SORT_OPTIONS: List<Pair<FeedSort, Int>> = listOf(
    FeedSort.NEWEST to R.string.sort_latest,
    FeedSort.SHORTEST to R.string.sort_shortest,
    FeedSort.TITLE to R.string.sort_title,
    FeedSort.RANDOM to R.string.sort_random,
)

/** The time spans with their labels, in the order the time chip moves through them. */
internal val TIME_CHIP_OPTIONS: List<Pair<TimeChip, Int>> = listOf(
    TimeChip.NONE to R.string.time_all,
    TimeChip.DAY to R.string.time_day,
    TimeChip.WEEK to R.string.time_week,
    TimeChip.MONTH to R.string.time_month,
)

/** Auto-play off and on with their labels, in the order the auto-play chip moves through them. */
private val AUTOPLAY_OPTIONS: List<Pair<Boolean, Int>> = listOf(
    false to R.string.autoplay_off,
    true to R.string.autoplay,
)

/** The watched modes with their labels, in the order the watched chip moves through them. */
private val WATCHED_MODE_OPTIONS: List<Pair<WatchedMode, Int>> = listOf(
    WatchedMode.UNWATCHED to R.string.watched_unwatched,
    WatchedMode.WATCHED to R.string.watched_watched,
    WatchedMode.ALL to R.string.watched_all,
)

/**
 * The one box every chip is drawn in, the same size selected or not: Sunflower
 * with ink text when [selected]. The touch area is taller than the box. A
 * screen reader hears [spokenName] in place of the chip's text when it is given.
 */
@Composable
private fun ChipBox(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    toggles: Boolean = false,
    spokenName: String? = null,
    content: @Composable RowScope.(textColor: Color) -> Unit,
) {
    val interactions = remember { MutableInteractionSource() }
    val pressable = if (toggles) {
        Modifier.toggleable(value = selected, interactionSource = interactions, indication = null, role = Role.Checkbox) { onClick() }
    } else {
        Modifier.clickable(interactionSource = interactions, indication = null, role = Role.Button, onClick = onClick)
    }
    Box(modifier.heightIn(min = 48.dp).then(pressable), contentAlignment = Alignment.Center) {
        Row(
            Modifier
                .height(ChipHeight)
                .clip(ChipShape)
                .background(if (selected) Sunflower else MaterialTheme.colorScheme.surface)
                .border(1.dp, if (selected) Sunflower else MaterialTheme.colorScheme.outlineVariant, ChipShape)
                .indication(interactions, ripple())
                .padding(horizontal = 12.dp)
                .then(if (spokenName != null) Modifier.clearAndSetSemantics { contentDescription = spokenName } else Modifier),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            content(if (selected) Ink else MaterialTheme.colorScheme.onSurface)
        }
    }
}

/**
 * A chip: a toggle when [selected] is given, otherwise a plain button. With
 * [removes], a × after the label says that pressing it takes it away, and a
 * screen reader hears "Remove" and the label.
 */
@Composable
fun Chip(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, selected: Boolean? = null, removes: Boolean = false) {
    val spokenName = if (removes) stringResource(R.string.remove_phrase, label) else null
    ChipBox(selected = selected == true, onClick = onClick, modifier = modifier, toggles = selected != null, spokenName = spokenName) { textColor ->
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = textColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            // a weight has no width to share in a row that scrolls sideways
            modifier = if (removes) Modifier.weight(1f, fill = false) else Modifier,
        )
        if (removes) {
            Text("×", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * A chip that shows the current one of [options] and moves to the next when
 * pressed. It is never drawn selected and is as wide as its widest label. A
 * screen reader hears [setting], what the chip sets, before the current choice.
 */
@Composable
fun <Choice> CycleChip(
    @StringRes setting: Int,
    options: List<Pair<Choice, Int>>,
    value: Choice,
    onChange: (Choice) -> Unit,
    modifier: Modifier = Modifier,
) {
    val current = options.indexOfFirst { (option, _) -> option == value }
    val choice = options.getOrNull(current)?.let { (_, label) -> stringResource(label) }.orEmpty()
    val spokenName = stringResource(R.string.chip_setting, stringResource(setting), choice)
    ChipBox(
        selected = false,
        onClick = { onChange(options[(current + 1) % options.size].first) },
        modifier = modifier,
        spokenName = spokenName,
    ) { textColor ->
        // every label lies in the one cell, so the chip never resizes
        Box(contentAlignment = Alignment.Center) {
            options.forEachIndexed { index, (_, label) ->
                CycleLabel(label, shown = index == current, color = textColor)
            }
        }
    }
}

@Composable
private fun CycleLabel(@StringRes label: Int, shown: Boolean, color: Color) {
    Text(
        stringResource(label),
        style = MaterialTheme.typography.labelLarge,
        color = color,
        maxLines = 1,
        modifier = if (shown) Modifier else Modifier.alpha(0f).clearAndSetSemantics { },
    )
}

/** How far from an edge of the chip row the chips fade out when more lie beyond it. */
private val ChipRowFade = 40.dp

/** Fades the content out towards each side [scroll] can still move to, as the hint that more is there. */
private fun Modifier.fadingScrollEdges(scroll: ScrollState): Modifier =
    // offscreen, so the fade takes away only this row's drawing and not what lies under it
    graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
        drawContent()
        val fade = ChipRowFade.toPx()
        if (scroll.canScrollBackward) {
            drawRect(
                brush = Brush.horizontalGradient(listOf(Color.Transparent, Color.Black), startX = 0f, endX = fade),
                size = Size(fade, size.height),
                blendMode = BlendMode.DstIn,
            )
        }
        if (scroll.canScrollForward) {
            drawRect(
                brush = Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = size.width - fade, endX = size.width),
                topLeft = Offset(size.width - fade, 0f),
                size = Size(fade, size.height),
                blendMode = BlendMode.DstIn,
            )
        }
    }

/** The auto-play chip, the first of the chip row: "Play one" or "Auto-play", switched by a press. */
@Composable
private fun AutoplayChip(viewModel: SubtubeViewModel, modifier: Modifier = Modifier) {
    CycleChip(R.string.chip_playback, AUTOPLAY_OPTIONS, viewModel.settings.autoplay, viewModel::setAutoplay, modifier)
}

/** The round + chip after a chip row's first divider: a press opens the editor for a new group. */
@Composable
private fun NewGroupChip(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val interactions = remember { MutableInteractionSource() }
    Box(
        modifier
            .heightIn(min = 48.dp)
            .clickable(interactionSource = interactions, indication = null, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(ChipHeight)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surface)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape)
                .indication(interactions, ripple()),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                SubtubeIcons.Add,
                contentDescription = stringResource(R.string.new_group),
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** The line between two kinds of chips in a row. */
@Composable
private fun ChipDivider() {
    Box(Modifier.width(1.dp).height(20.dp).background(MaterialTheme.colorScheme.outlineVariant))
}

/** A chip row's group chips. */
internal class GroupChips(
    /** The groups' names, in row order. */
    val names: List<String>,
    /** The selected names. */
    val selected: List<String>,
    /** What a press on a group's chip does. */
    val onToggle: (String) -> Unit,
    /** What a press on the "New group" chip does. */
    val onNew: () -> Unit,
)

/**
 * A row of chips under a list's title, scrolling sideways: [leading]; with
 * [groups], a divider, the "New group" chip and a toggle for each group;
 * then, when there are [topics] (category ids, in row order), a divider and
 * a toggle for each, on when it is in [selected]. A channel's page passes no
 * [groups]. The row fades out at a side with chips beyond it.
 */
@Composable
internal fun ChipRow(
    topics: List<String>,
    selected: List<String>,
    onTopic: (String) -> Unit,
    modifier: Modifier = Modifier,
    groups: GroupChips? = null,
    leading: @Composable RowScope.() -> Unit,
) {
    val scroll = rememberScrollState()
    Row(
        modifier.fillMaxWidth().fadingScrollEdges(scroll).horizontalScroll(scroll).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        leading()
        if (groups != null) {
            ChipDivider()
            NewGroupChip(groups.onNew)
            for (name in groups.names) {
                key(name) {
                    Chip(name, onClick = { groups.onToggle(name) }, selected = name in groups.selected)
                }
            }
        }
        if (topics.isNotEmpty()) {
            ChipDivider()
        }
        for (categoryId in topics) {
            Chip(topicLabel(categoryId).orEmpty(), onClick = { onTopic(categoryId) }, selected = categoryId in selected)
        }
    }
}

/**
 * The chips under the feed's title and a channel page's: the auto-play, sort,
 * time and watched chips, the group chips when [onNewGroup] is given (the
 * feed, once a load has been shown), then the topic chips for [topics]
 * (category ids, in row order).
 */
@Composable
fun FeedChipRow(viewModel: SubtubeViewModel, topics: List<String>, modifier: Modifier = Modifier, onNewGroup: (() -> Unit)? = null) {
    val settings = viewModel.settings
    val groups = onNewGroup?.takeIf { viewModel.loadShown }?.let { open ->
        GroupChips(viewModel.groups, settings.groupChips, viewModel::toggleGroupChip, open)
    }
    ChipRow(topics, settings.topicChips, viewModel::toggleTopicChip, modifier, groups) {
        AutoplayChip(viewModel)
        CycleChip(R.string.chip_sort, FEED_SORT_OPTIONS, settings.feedSort, viewModel::setFeedSort)
        CycleChip(R.string.chip_time, TIME_CHIP_OPTIONS, settings.timeChip, viewModel::setTimeChip)
        CycleChip(R.string.chip_show, WATCHED_MODE_OPTIONS, viewModel.watchedMode, viewModel::chooseWatchedMode)
    }
}

/**
 * A top bar's title while its chip row has something selected: [names]
 * joined on one line, cut with an ellipsis; [usual] with none.
 */
@Composable
internal fun ChipTitleText(names: List<String>, usual: String) {
    Text(if (names.isEmpty()) usual else names.joinToString(", "), maxLines = 1, overflow = TextOverflow.Ellipsis)
}

/** How long a top bar action takes to come or go. */
private const val ACTION_FADE_MS = 150

/** A top bar action that fades and widens in while [visible] and out after, at once where animation is off. */
@Composable
private fun TitleAction(visible: Boolean, content: @Composable () -> Unit) {
    val moves = motionAllowed()
    AnimatedVisibility(
        visible = visible,
        enter = if (moves) fadeIn(tween(ACTION_FADE_MS)) + expandHorizontally(tween(ACTION_FADE_MS)) else EnterTransition.None,
        exit = if (moves) fadeOut(tween(ACTION_FADE_MS)) + shrinkHorizontally(tween(ACTION_FADE_MS)) else ExitTransition.None,
    ) {
        content()
    }
}

/**
 * The top bar actions that go with a chip row's title: "Edit group" when
 * [title] has exactly one group selected and [onEdit] is given, and "Clear"
 * while it has any name. Each fades in and out.
 */
@Composable
internal fun ChipTitleActions(title: ChipTitle, onClear: () -> Unit, onEdit: ((String) -> Unit)? = null) {
    TitleAction(visible = title.edit != null && onEdit != null) {
        IconButton(onClick = { title.edit?.let { group -> onEdit?.invoke(group) } }) {
            Icon(SubtubeIcons.Edit, contentDescription = stringResource(R.string.edit_group))
        }
    }
    TitleAction(visible = title.names.isNotEmpty()) {
        IconButton(onClick = onClear) {
            Icon(SubtubeIcons.Close, contentDescription = stringResource(R.string.clear))
        }
    }
}
