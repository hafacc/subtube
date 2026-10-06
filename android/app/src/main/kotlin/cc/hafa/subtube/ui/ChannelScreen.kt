package cc.hafa.subtube.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import cc.hafa.subtube.R

/**
 * One channel's page: the feed's chips, then its entries that pass its filter
 * and the chips, as the feed's cards with the feed's watched behaviour, whether
 * or not the channel is in the feed. The filter button beside the title opens
 * the channel's filter sheet over the page.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelScreen(viewModel: SubtubeViewModel, channelId: String) {
    val channel = viewModel.channels[channelId]
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()
    var filtersOpen by rememberSaveable { mutableStateOf(false) }
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = { Text(channel?.title.orEmpty(), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = viewModel::pop) {
                        Icon(SubtubeIcons.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    ChipTitleActions(viewModel.channelPageTitle, onClear = viewModel::clearTopicChips)
                    IconButton(onClick = { filtersOpen = true }, enabled = channel != null) {
                        Icon(SubtubeIcons.Filters, contentDescription = stringResource(R.string.filters))
                    }
                },
                scrollBehavior = scrollBehavior,
            )
        },
        bottomBar = {
            // the page belongs to the tab it was opened from
            MainNavigationBar(if (Screen.Channels in viewModel.backStack) Screen.Channels else Screen.Feed, viewModel::selectTab)
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize()) {
                FeedChipRow(viewModel, viewModel.channelFeed.topics)
                FeedList(
                    viewModel = viewModel,
                    items = viewModel.channelFeed.items,
                    page = channelId,
                    refreshing = viewModel.loading || (channel != null && viewModel.isFetching(channel)),
                    onChannel = null,
                    modifier = Modifier.weight(1f),
                )
            }
            // a full load only: the channel's own fetch has no steps to show
            LoadProgressBar(viewModel.loadFraction)
        }
    }
    if (filtersOpen && channel != null) {
        FilterSheet(viewModel, channel) { filtersOpen = false }
    }
}
