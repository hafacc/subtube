package cc.hafa.subtube.ui

import androidx.annotation.StringRes
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import cc.hafa.subtube.core.FEED_SORT_CHIPS
import cc.hafa.subtube.core.STARTING_WATCHED_MODE
import cc.hafa.subtube.core.sortChipOf
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

/** How long a chip takes to change color. */
private const val CHIP_COLOR_MS = 150

/** The label each feed sort's chip shows. */
@StringRes
private fun sortLabel(sort: FeedSort): Int = when (sort) {
    FeedSort.NEWEST -> R.string.sort_latest
    FeedSort.OLDEST -> R.string.sort_oldest
    FeedSort.SHORTEST -> R.string.sort_shortest
    FeedSort.LONGEST -> R.string.sort_longest
    FeedSort.TITLE -> R.string.sort_title
    FeedSort.TITLE_REVERSED -> R.string.sort_title_reversed
    FeedSort.RANDOM -> R.string.sort_random
}

/** The time spans with their labels, in the order the time chip moves through them. */
internal val TIME_CHIP_OPTIONS: List<Pair<TimeChip, Int>> = listOf(
    TimeChip.NONE to R.string.time_all,
    TimeChip.DAY to R.string.time_day,
    TimeChip.WEEK to R.string.time_week,
    TimeChip.MONTH to R.string.time_month,
)

/** The watched modes the watched chip offers ([WATCHED_CHIP_MODES]) with their labels, in the order it moves through them. */
private val WATCHED_MODE_OPTIONS: List<Pair<WatchedMode, Int>> = listOf(
    WatchedMode.UNWATCHED to R.string.watched_unwatched,
    WatchedMode.WATCHED to R.string.watched_watched,
)

/** The fill, outline and content colors of a chip or round chip, running to the [selected] ones unless animation is off. */
@Composable
private fun chipColors(selected: Boolean): Triple<Color, Color, Color> {
    val spec = if (motionAllowed()) tween<Color>(CHIP_COLOR_MS) else snap()
    val fill by animateColorAsState(if (selected) Sunflower else MaterialTheme.colorScheme.surface, spec, label = "chipFill")
    val outline by animateColorAsState(if (selected) Sunflower else MaterialTheme.colorScheme.outlineVariant, spec, label = "chipOutline")
    val content by animateColorAsState(if (selected) Ink else MaterialTheme.colorScheme.onSurface, spec, label = "chipContent")
    return Triple(fill, outline, content)
}

/**
 * The one box every chip is drawn in, the same size selected or not: Sunflower
 * with ink text when [selected]. The touch area is taller than the box. A
 * screen reader hears [spokenName] in place of the chip's text when it is
 * given, and with [oneOfSet] whether the chip is the selected one.
 */
@Composable
private fun ChipBox(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    toggles: Boolean = false,
    spokenName: String? = null,
    oneOfSet: Boolean = false,
    content: @Composable RowScope.(textColor: Color) -> Unit,
) {
    val interactions = remember { MutableInteractionSource() }
    val pressable = if (toggles) {
        Modifier.toggleable(value = selected, interactionSource = interactions, indication = null, role = Role.Checkbox) { onClick() }
    } else {
        Modifier
            .clickable(interactionSource = interactions, indication = null, role = Role.Button, onClick = onClick)
            .then(if (oneOfSet) Modifier.semantics { this.selected = selected } else Modifier)
    }
    val (fill, outline, textColor) = chipColors(selected)
    Box(modifier.heightIn(min = 48.dp).then(pressable), contentAlignment = Alignment.Center) {
        Row(
            Modifier
                .height(ChipHeight)
                .clip(ChipShape)
                .background(fill)
                .border(1.dp, outline, ChipShape)
                .indication(interactions, ripple())
                .padding(horizontal = 12.dp)
                .then(if (spokenName != null) Modifier.clearAndSetSemantics { contentDescription = spokenName } else Modifier),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            content(textColor)
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
 * pressed. It is as wide as its widest label, and drawn selected only with
 * [selected]. A screen reader hears [setting], what the chip sets, before the
 * current choice.
 */
@Composable
fun <Choice> CycleChip(
    @StringRes setting: Int,
    options: List<Pair<Choice, Int>>,
    value: Choice,
    onChange: (Choice) -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    val current = options.indexOfFirst { (option, _) -> option == value }
    LabelsChip(
        setting = setting,
        labels = options.map { (_, label) -> label },
        current = current,
        selected = selected,
        onClick = { onChange(options[(current + 1) % options.size].first) },
        modifier = modifier,
    )
}

/**
 * A chip holding every one of [labels] in one cell, so it never resizes, and
 * showing the one at [current]. With [oneOfSet] a screen reader also hears
 * whether it is the selected one.
 */
@Composable
private fun LabelsChip(
    @StringRes setting: Int,
    labels: List<Int>,
    current: Int,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    oneOfSet: Boolean = false,
) {
    val choice = labels.getOrNull(current)?.let { label -> stringResource(label) }.orEmpty()
    val spokenName = stringResource(R.string.chip_setting, stringResource(setting), choice)
    ChipBox(selected = selected, onClick = onClick, modifier = modifier, spokenName = spokenName, oneOfSet = oneOfSet) { textColor ->
        Box(contentAlignment = Alignment.Center) {
            labels.forEachIndexed { index, label ->
                CycleLabel(label, shown = index == current, color = textColor)
            }
        }
    }
}

@Composable
private fun CycleLabel(@StringRes label: Int, shown: Boolean, color: Color) {
    val opacity by animateFloatAsState(
        if (shown) 1f else 0f,
        if (motionAllowed()) tween(CHIP_COLOR_MS) else snap(),
        label = "cycleLabel",
    )
    Text(
        stringResource(label),
        style = MaterialTheme.typography.labelLarge,
        color = color,
        maxLines = 1,
        modifier = Modifier.alpha(opacity).then(if (shown) Modifier else Modifier.clearAndSetSemantics { }),
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

/** A round chip that is only [icon], named [name] for a screen reader; Sunflower with an ink icon when [selected]. */
@Composable
private fun RoundChip(icon: ImageVector, name: String, onClick: () -> Unit, modifier: Modifier = Modifier, selected: Boolean = false) {
    val interactions = remember { MutableInteractionSource() }
    val (fill, outline, tint) = chipColors(selected)
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
                .background(fill)
                .border(1.dp, outline, CircleShape)
                .indication(interactions, ripple()),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = name, tint = tint, modifier = Modifier.size(16.dp))
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
 * A row of chips under a list's title, scrolling sideways, [startPadding]
 * from its start: [leading]; with
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
    startPadding: Dp = 16.dp,
    leading: @Composable RowScope.() -> Unit = {},
) {
    val scroll = rememberScrollState()
    Row(
        modifier.fillMaxWidth().fadingScrollEdges(scroll).horizontalScroll(scroll).padding(start = startPadding, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        leading()
        if (groups != null) {
            ChipDivider()
            RoundChip(SubtubeIcons.Add, stringResource(R.string.new_group), groups.onNew)
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

private val MenuShape = RoundedCornerShape(12.dp)

/**
 * The feed's "Sort and filter" menu: a round chip, drawn selected while the
 * time or watched chip is off where it starts, and the drop-down it opens.
 *
 * The drop-down stays open while its chips are pressed and closes on a press
 * outside it or Back. Its first row is "Auto-play", a toggle, and the time
 * and watched chips, which cycle and are drawn selected off where they start.
 * Under a line, a chip for each of [FEED_SORT_CHIPS], one of them selected:
 * a press on another selects it in the direction it last showed, and a press
 * on the selected one turns it round, or shuffles again for Random
 * ([SubtubeViewModel.pressSortChip]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterMenu(viewModel: SubtubeViewModel, modifier: Modifier = Modifier) {
    var open by rememberSaveable { mutableStateOf(false) }
    val settings = viewModel.settings
    val name = stringResource(R.string.sort_and_filter)
    Box(modifier) {
        TooltipBox(
            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Below),
            tooltip = { PlainTooltip { Text(name) } },
            state = rememberTooltipState(),
        ) {
            RoundChip(SubtubeIcons.Sliders, name, onClick = { open = !open }, selected = viewModel.menuNarrows)
        }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            // the chip's touch area reaches 8dp below what is drawn of it
            offset = DpOffset(0.dp, (-4).dp),
            shape = MenuShape,
            containerColor = MaterialTheme.colorScheme.surface,
            tonalElevation = 0.dp,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        ) {
            FlowRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(stringResource(R.string.autoplay), onClick = { viewModel.setAutoplay(!settings.autoplay) }, selected = settings.autoplay)
                CycleChip(
                    R.string.chip_time,
                    TIME_CHIP_OPTIONS,
                    settings.timeChip,
                    viewModel::setTimeChip,
                    selected = settings.timeChip != TimeChip.NONE,
                )
                CycleChip(
                    R.string.chip_show,
                    WATCHED_MODE_OPTIONS,
                    viewModel.watchedMode,
                    viewModel::chooseWatchedMode,
                    selected = viewModel.watchedMode != STARTING_WATCHED_MODE,
                )
            }
            HorizontalDivider(Modifier.padding(horizontal = 12.dp), color = MaterialTheme.colorScheme.outlineVariant)
            FlowRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val active = sortChipOf(settings.feedSort)
                viewModel.sortChips.forEachIndexed { index, shown ->
                    val options = FEED_SORT_CHIPS[index]
                    LabelsChip(
                        setting = R.string.chip_sort,
                        labels = options.map(::sortLabel),
                        current = options.indexOf(shown),
                        selected = index == active,
                        onClick = { viewModel.pressSortChip(index) },
                        oneOfSet = true,
                    )
                }
            }
        }
    }
}

/**
 * The chips under the feed's title and a channel page's: the "Sort and
 * filter" menu's chip, which stays put, then, scrolling, the group chips
 * when [onNewGroup] is given (the feed, once a load has been shown) and the
 * topic chips for [topics] (category ids, in row order).
 */
@Composable
fun FeedChipRow(viewModel: SubtubeViewModel, topics: List<String>, modifier: Modifier = Modifier, onNewGroup: (() -> Unit)? = null) {
    val settings = viewModel.settings
    val groups = onNewGroup?.takeIf { viewModel.loadShown }?.let { open ->
        GroupChips(viewModel.groups, settings.groupChips, viewModel::toggleGroupChip, open)
    }
    Row(modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        FilterMenu(viewModel)
        ChipRow(topics, settings.topicChips, viewModel::toggleTopicChip, Modifier.weight(1f), groups, startPadding = 8.dp)
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
