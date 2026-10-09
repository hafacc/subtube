package cc.hafa.subtube.ui

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import cc.hafa.subtube.R
import cc.hafa.subtube.core.matchesSearch
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.ChannelSort
import cc.hafa.subtube.core.ContentMode
import cc.hafa.subtube.core.FilterMode
import cc.hafa.subtube.core.FilterScope
import cc.hafa.subtube.core.LiveFilter
import cc.hafa.subtube.core.ShortsFilter
import cc.hafa.subtube.core.ignoringCase
import cc.hafa.subtube.core.knownTopics
import cc.hafa.subtube.core.patternToPhrases
import cc.hafa.subtube.core.topicLabel

/**
 * One line saying what a channel's filter does, as the channel list shows it:
 * its parts in the editor's order, the chosen topics last by name.
 */
fun filterSummary(context: Context, filter: ChannelFilter): String =
    if (filter.enabled) enabledSummary(context, filter) else context.getString(R.string.summary_off)

private fun enabledSummary(context: Context, filter: ChannelFilter): String {
    val parts = ArrayList<String>()
    if (filter.followed == true) {
        parts.add(context.getString(R.string.summary_followed))
    }
    val rules = ArrayList<String>()
    if (filter.contentMode == ContentMode.PLAYLISTS) {
        rules.add(context.getString(R.string.playlists))
    }
    val phrases = patternToPhrases(filter.regex).orEmpty()
    if (phrases.isNotEmpty()) {
        val scope = filter.searchScope ?: FilterScope.TITLE
        val template = if (filter.mode == FilterMode.EXCLUDE) {
            when (scope) {
                FilterScope.TITLE -> R.string.summary_hides_titles_matching
                FilterScope.BOTH -> R.string.summary_hides_both_matching
                FilterScope.DESCRIPTION -> R.string.summary_hides_descriptions_matching
            }
        } else {
            when (scope) {
                FilterScope.TITLE -> R.string.summary_only_titles_matching
                FilterScope.BOTH -> R.string.summary_only_both_matching
                FilterScope.DESCRIPTION -> R.string.summary_only_descriptions_matching
            }
        }
        rules.add(context.getString(template, phrases.joinToString(context.getString(R.string.summary_list_separator))))
    }
    if (filter.contentMode != ContentMode.PLAYLISTS) {
        when (filter.shortsFilter) {
            ShortsFilter.NORMAL -> rules.add(context.getString(R.string.summary_no_shorts))
            ShortsFilter.SHORTS -> rules.add(context.getString(R.string.summary_shorts_only))
            else -> Unit
        }
        when (filter.liveFilter) {
            LiveFilter.NORMAL -> rules.add(context.getString(R.string.summary_no_live))
            LiveFilter.VOD -> rules.add(context.getString(R.string.summary_live_only))
            else -> Unit
        }
        val minimum = filter.minDurationSeconds ?: 0
        if (minimum > 0) {
            rules.add(context.resources.getQuantityString(R.plurals.summary_min_duration, minimum, minimum))
        }
        val topics = knownTopics(filter.topics.orEmpty()).mapNotNull(::topicLabel).sortedWith(ignoringCase)
        if (topics.isNotEmpty()) {
            rules.add(context.getString(R.string.summary_only_topics, topics.joinToString(context.getString(R.string.summary_list_separator))))
        }
    }
    if (rules.isEmpty()) {
        rules.add(context.getString(R.string.summary_all_videos))
    }
    return (parts + rules).joinToString(context.getString(R.string.summary_separator))
}

/** How opaque a channel that is off is drawn, in every list of channels. */
private const val OFF_CHANNEL_ALPHA = 0.45f

/** The channel orders with their labels, in the order the sort chip moves through them. */
private val CHANNEL_SORT_OPTIONS: List<Pair<ChannelSort, Int>> = listOf(
    ChannelSort.NEWEST to R.string.sort_latest,
    ChannelSort.NAME to R.string.sort_name,
    ChannelSort.UNWATCHED to R.string.sort_unwatched,
)

/**
 * The chips under the channels tab's title: the sort and time chips, the
 * group chips once a load has been shown, then the topic chips counted over
 * every on channel's entries that pass its filter.
 */
@Composable
private fun ChannelChipRow(viewModel: SubtubeViewModel, onNewGroup: () -> Unit, modifier: Modifier = Modifier) {
    val settings = viewModel.settings
    val groups = if (viewModel.loadShown) {
        GroupChips(viewModel.groups, settings.channelGroupChips, viewModel::toggleChannelGroupChip, onNewGroup)
    } else {
        null
    }
    ChipRow(viewModel.channelTopics, settings.channelTopicChips, viewModel::toggleChannelTopicChip, modifier, groups) {
        CycleChip(R.string.chip_sort, CHANNEL_SORT_OPTIONS, settings.channelSort, viewModel::setChannelSort)
        CycleChip(R.string.chip_time, TIME_CHIP_OPTIONS, settings.channelTimeChip, viewModel::setChannelTimeChip)
    }
}

/**
 * The channels tab: under its chips, the subscribed and followed channels the
 * group, time and topic chips keep, in the order the sort chip chooses, each with
 * its unwatched count, its switch, and its page on tap. The rows keep their
 * places while the tab is on screen: they are taken again only on entering
 * it, after a full load, and when a chip or the search text changes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelsScreen(viewModel: SubtubeViewModel) {
    val context = LocalContext.current
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()
    var searching by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    val groupEditor = remember { GroupEditorState() }
    val closeSearch = {
        searching = false
        if (query.isNotEmpty()) {
            query = ""
            viewModel.reorderChannels()
        }
    }
    val channels = viewModel.orderedChannels
        .filter { channel -> matchesSearch(channel.title, query) }
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = {
                    if (searching) {
                        val focus = remember { FocusRequester() }
                        LaunchedEffect(Unit) { focus.requestFocus() }
                        SearchField(
                            query,
                            { text ->
                                query = text
                                viewModel.reorderChannels()
                            },
                            Modifier.fillMaxWidth().padding(end = 12.dp).focusRequester(focus),
                        )
                    } else {
                        ChipTitleText(viewModel.channelsTitle.names, stringResource(R.string.channels))
                    }
                },
                navigationIcon = {
                    if (searching) {
                        IconButton(onClick = closeSearch) {
                            Icon(SubtubeIcons.ArrowBack, contentDescription = stringResource(R.string.back))
                        }
                    }
                },
                actions = {
                    if (!searching) {
                        ChipTitleActions(viewModel.channelsTitle, onClear = viewModel::clearChannelChips, onEdit = groupEditor::openFor)
                        IconButton(onClick = { searching = true }) {
                            Icon(SubtubeIcons.Search, contentDescription = stringResource(R.string.search_channels))
                        }
                    }
                },
                scrollBehavior = scrollBehavior,
            )
        },
        bottomBar = { MainNavigationBar(Screen.Channels, viewModel::selectTab) },
    ) { padding ->
        if (searching) {
            BackHandler(onBack = closeSearch)
        }
        Column(Modifier.fillMaxSize().padding(padding)) {
            ChannelChipRow(viewModel, onNewGroup = groupEditor::openNew)
            LazyColumn(Modifier.fillMaxWidth().weight(1f), contentPadding = PaddingValues(bottom = minimizedPlayerRoom(viewModel))) {
                if (channels.isEmpty() && viewModel.channelChipsChosen) {
                    item(key = "empty") {
                        Text(
                            stringResource(R.string.channels_empty_filtered),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.animateItem().fillMaxWidth().padding(horizontal = 16.dp, vertical = 32.dp),
                        )
                    }
                }
                items(channels, key = ChannelFilter::channelId) { channel ->
                    ChannelRow(
                        channel = channel,
                        summary = filterSummary(context, channel),
                        unwatched = viewModel.unwatchedByChannel[channel.channelId],
                        onOpen = { viewModel.showChannel(channel.channelId) },
                        onToggle = { enabled -> viewModel.updateFilter(channel.copy(enabled = enabled)) },
                        modifier = Modifier.animateItem(),
                    )
                }
                item(key = "attribution") { YouTubeAttribution(Modifier.animateItem()) }
            }
        }
    }
    groupEditor.Sheet(viewModel)
}

/**
 * A channel in a list: avatar, name, [summary], its [unwatched] count when it
 * has one, and its switch. A null [onOpen] leaves the row untappable;
 * [edgePadding] is false where the list already sits inside a screen's margins.
 * The switch shows [checked], whether the channel is on unless told otherwise,
 * and is named [switchLabel]; the row is dimmed only when the channel is off.
 */
@Composable
internal fun ChannelRow(
    channel: ChannelFilter,
    summary: String,
    onOpen: (() -> Unit)?,
    onToggle: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    edgePadding: Boolean = true,
    unwatched: Int? = null,
    checked: Boolean = channel.enabled,
    switchLabel: String = stringResource(R.string.show_in_feed_named, channel.title),
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 72.dp).padding(end = if (edgePadding) 12.dp else 0.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(
            Modifier
                .weight(1f)
                .heightIn(min = 72.dp)
                .clickable(enabled = onOpen != null) { onOpen?.invoke() }
                .padding(start = if (edgePadding) 16.dp else 0.dp, end = 8.dp)
                .alpha(if (channel.enabled) 1f else OFF_CHANNEL_ALPHA),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ChannelAvatar(channel.title, channel.thumbnail)
            Column {
                Text(channel.title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    summary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (unwatched != null) {
            val spoken = stringResource(R.string.unwatched_count, unwatched)
            Text(
                unwatched.toString(),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 8.dp).semantics { contentDescription = spoken },
            )
        }
        BrandSwitch(
            checked = checked,
            onCheckedChange = onToggle,
            contentDescription = switchLabel,
        )
    }
}
