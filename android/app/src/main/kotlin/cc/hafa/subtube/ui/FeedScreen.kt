package cc.hafa.subtube.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import android.content.Context
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.hafa.subtube.R
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.Playlist
import cc.hafa.subtube.core.SWIPE_MARK_SHARE
import cc.hafa.subtube.core.Video
import cc.hafa.subtube.core.swipeMarks
import kotlinx.coroutines.launch

/** The shape of a card, and of the strip a swipe uncovers behind it. */
private val CardShape = RoundedCornerShape(12.dp)

/** The margin at each side of a list of cards. */
private val ListSideMargin = 16.dp

/** How opaque the previous feed is while a load runs. */
private const val LOADING_ALPHA = 0.4f

/** How thick the progress bar along a thumbnail's bottom edge is. */
private val ProgressBarHeight = 4.dp

/** How far the strip that takes a press on the progress bar reaches up over the thumbnail. */
private val BarTargetAbove = 32.dp

/** How far that strip reaches down over the text, short of the title's first line. */
private val BarTargetBelow = 16.dp

/** How long the progress bar takes to fill or empty when an entry is marked. */
private const val BAR_FILL_MS = 200

/** The feed tab: the chips, then every entry that passes the filters and the chips, greyed out while a load runs. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedScreen(viewModel: SubtubeViewModel) {
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()
    val groupEditor = remember { GroupEditorState() }
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = { ChipTitleText(viewModel.feedTitle.names, stringResource(R.string.tab_feed)) },
                actions = { ChipTitleActions(viewModel.feedTitle, onClear = viewModel::clearFeedChips, onEdit = groupEditor::openFor) },
                scrollBehavior = scrollBehavior,
            )
        },
        bottomBar = { MainNavigationBar(Screen.Feed, viewModel::selectTab) },
    ) { padding ->
        val listState = rememberLazyListState()
        LaunchedEffect(viewModel) {
            viewModel.feedTopRequests.collect { listState.animateScrollToItem(0) }
        }
        Box(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.fillMaxSize()) {
                FeedChipRow(viewModel, viewModel.feed.topics, onNewGroup = groupEditor::openNew)
                FeedList(
                    viewModel = viewModel,
                    items = viewModel.feed.items,
                    page = null,
                    listState = listState,
                    refreshing = viewModel.loading,
                    onChannel = viewModel::showChannel,
                    modifier = Modifier.weight(1f),
                )
            }
            LoadProgressBar(viewModel.loadFraction)
        }
    }
    groupEditor.Sheet(viewModel)
}

/**
 * A column of cards under the error and notice banners, pulled down to refresh: the feed,
 * or one channel's page. A null [onChannel] leaves the channel names untappable. While
 * [refreshing], skeleton cards stand in for an empty list and the shimmer runs over a full one.
 * [page] is the page the list is: a channel's id, or null for the feed. The card the view
 * model says holds the player leaves its thumbnail's box empty for it, and the list brings
 * a card the view model asks for into view.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FeedList(
    viewModel: SubtubeViewModel,
    items: List<FeedItem>,
    page: String?,
    refreshing: Boolean,
    onChannel: ((String) -> Unit)?,
    modifier: Modifier = Modifier,
    listState: LazyListState = rememberLazyListState(),
) {
    val pullState = rememberPullToRefreshState()
    // nothing to show yet: skeletons say it is loading, so the spinner stays away
    val skeletons = refreshing && items.isEmpty()
    // the shimmer over the greyed cards says a reload is running; the spinner stays only where the shimmer is off
    val spinning = refreshing && !skeletons && !motionAllowed()
    val scope = rememberCoroutineScope()
    // an error says why there is nothing; "caught up" beside it would contradict it
    val empty = items.isEmpty() && !refreshing && viewModel.error == null
    val thumbnailInset = with(LocalDensity.current) { (ListSideMargin * 2).roundToPx() }
    // the list's rows above the first card
    val rowsAbove by rememberUpdatedState(listOf(viewModel.error != null, viewModel.notice != null, skeletons, empty).count { shown -> shown })
    val currentItems by rememberUpdatedState(items)
    val request = viewModel.cardRequest?.takeIf { asked -> asked.page == page }
    LaunchedEffect(request, listState) {
        if (request != null) {
            try {
                val position = currentItems.indexOfFirst { item -> item.id == request.id }
                if (position >= 0) {
                    val index = rowsAbove + position
                    val layout = listState.layoutInfo
                    val row = layout.visibleItemsInfo.firstOrNull { visible -> visible.index == index }
                    // the thumbnail is the top of its row, 16:9 across the list less its margins; the player needs half of it showing
                    val thumbnailHeight = (layout.viewportSize.width - thumbnailInset) * 9 / 16
                    val showing = if (row == null) {
                        0
                    } else {
                        minOf(row.offset + thumbnailHeight, layout.viewportEndOffset) - maxOf(row.offset, layout.viewportStartOffset)
                    }
                    if (showing < thumbnailHeight / 2) {
                        listState.animateScrollToItem(index)
                    }
                }
            } finally {
                // a touch or another scroll cancels this one: the request is over all the same
                viewModel.cardShown(request)
            }
        }
    }
    PullToRefreshBox(
        isRefreshing = spinning,
        onRefresh = {
            viewModel.refresh()
            // the indicator waits at the pull threshold for a refresh to end; with no spinner, send it back now
            scope.launch { pullState.animateToHidden() }
        },
        state = pullState,
        modifier = modifier,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = pullState,
                isRefreshing = spinning,
                color = MaterialTheme.brand.accent,
                modifier = Modifier.align(Alignment.TopCenter),
            )
        },
    ) {
        LazyColumn(
            contentPadding = PaddingValues(start = ListSideMargin, top = 4.dp, end = ListSideMargin, bottom = 96.dp + minimizedPlayerRoom(viewModel)),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            state = listState,
            userScrollEnabled = !skeletons,
            modifier = Modifier
                .fillMaxSize()
                .onGloballyPositioned { coordinates -> viewModel.playerViewMoved(page, coordinates.boundsInRoot()) }
                .shimmer(active = refreshing && !skeletons, overCards = true),
        ) {
            viewModel.error?.let { message ->
                item(key = "error") {
                    ErrorBanner(
                        message = message.resolve(LocalContext.current),
                        offersSignIn = message.offersSignIn,
                        signingIn = viewModel.signingIn,
                        onReconnect = viewModel::signIn,
                    )
                }
            }
            viewModel.notice?.let { message ->
                item(key = "notice") {
                    NoticeBanner(message.resolve(LocalContext.current), onDismiss = viewModel::dismissNotice)
                }
            }
            if (skeletons) {
                item(key = "skeletons") { SkeletonCards() }
            }
            if (empty) {
                item(key = "empty") {
                    Text(
                        stringResource(if (viewModel.emptiedBySelection) R.string.feed_empty_filtered else R.string.feed_empty),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
                    )
                }
            }
            items(items, key = FeedItem::id) { item ->
                val holdsPlayer = viewModel.playsInCard(item.id, page)
                // the player's next save of its position would undo a mark
                val isPlaying = viewModel.playing?.item?.id == item.id
                FeedCard(
                    item = item,
                    watched = item.id in viewModel.watched,
                    progress = viewModel.bars[item.id],
                    enabled = !viewModel.loading,
                    onOpen = { viewModel.play(item) },
                    onChannel = onChannel?.let { open -> { open(item.channelId) } },
                    onMark = if (isPlaying) null else { marked -> viewModel.setWatched(item.id, marked) },
                    // the player can't follow a card that slides to a new place, so its card jumps there
                    modifier = (if (holdsPlayer) Modifier else Modifier.animateItem()).alpha(if (viewModel.loading) LOADING_ALPHA else 1f),
                    player = if (holdsPlayer) {
                        { PlayerCardSlot(viewModel, item.id) }
                    } else {
                        null
                    },
                )
            }
            if (!skeletons) {
                item(key = "attribution") { YouTubeAttribution() }
            }
        }
    }
}

/** A notice that stays until it is dismissed. */
@Composable
private fun NoticeBanner(message: String, onDismiss: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(message, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
            AccentTextButton(stringResource(R.string.dismiss), onClick = onDismiss)
        }
    }
}

/** Why a load failed, with "Sign in" only when signing in is what fixes it ([offersSignIn]). */
@Composable
private fun ErrorBanner(message: String, offersSignIn: Boolean, signingIn: Boolean, onReconnect: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.errorContainer, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
        Row(
            Modifier.heightIn(min = 64.dp).padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(message, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            if (offersSignIn && signingIn) {
                Spinner(Modifier.padding(12.dp), size = 20.dp)
            } else if (offersSignIn) {
                TextButton(onClick = onReconnect) {
                    Text(stringResource(R.string.sign_in), color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }
    }
}

/**
 * One entry as a card: thumbnail, title, then the channel's name and the date
 * on one line. A bar along the thumbnail's bottom edge is [progress] of its
 * width (null or 0 for none). When [onMark] is given (it is not for the entry
 * the player has, in its card or in the corner), pressing the bar or swiping
 * the card sideways ([SwipeToMark]) marks the entry watched or unwatched,
 * calling [onMark] with the new state, and never plays it. [player], when given,
 * stands in place of the thumbnail, bar and all. A null action leaves that part untappable.
 */
@Composable
internal fun FeedCard(
    item: FeedItem,
    watched: Boolean,
    progress: Double?,
    enabled: Boolean,
    onOpen: (() -> Unit)?,
    onChannel: (() -> Unit)?,
    modifier: Modifier = Modifier,
    onMark: ((Boolean) -> Unit)? = null,
    player: (@Composable () -> Unit)? = null,
) {
    val markLabel = stringResource(if (watched) R.string.mark_unwatched else R.string.mark_watched)
    SwipeToMark(watched = watched, onMark = onMark.takeIf { enabled && player == null }, modifier = modifier.fillMaxWidth()) { held ->
        Card(
            shape = CardShape,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
            modifier = held.fillMaxWidth(),
        ) {
            if (player != null) {
                player()
            } else {
                val playLabel = stringResource(R.string.play_item, item.title)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                        .clickable(enabled = enabled && onOpen != null, onClickLabel = playLabel) { onOpen?.invoke() }
                        .semantics {
                            if (enabled && onMark != null) {
                                customActions = listOf(
                                    CustomAccessibilityAction(markLabel) {
                                        onMark(!watched)
                                        true
                                    },
                                )
                            }
                        },
                ) {
                    Thumbnail(item.thumbnail, Modifier.fillMaxSize())
                    if (item is Video && item.isShort == true) {
                        ThumbnailBadge(stringResource(R.string.badge_short), Modifier.align(Alignment.TopStart).padding(8.dp))
                    }
                    if (watched) {
                        ThumbnailBadge(stringResource(R.string.badge_watched), Modifier.align(Alignment.BottomStart).padding(8.dp))
                    }
                    cornerLabel(item)?.let { label ->
                        ThumbnailBadge(
                            label,
                            Modifier.align(Alignment.BottomEnd).padding(8.dp),
                            icon = if (item is Playlist) SubtubeIcons.PlaylistPlay else null,
                        )
                    }
                    WatchedBar(progress ?: 0.0, modifier = Modifier.align(Alignment.BottomStart))
                }
                if (onMark != null) {
                    WatchedBarTarget(watched, markLabel, enabled, onMark)
                }
            }
            Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    item.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    // a press plays, as on the thumbnail, which is the one place a screen reader finds that action
                    modifier = Modifier.fillMaxWidth().pointerInput(enabled, onOpen) {
                        detectTapGestures(onTap = { if (enabled) onOpen?.invoke() })
                    },
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f)) {
                        Text(
                            item.channelTitle,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .touchHeight(48.dp)
                                .clickable(enabled = enabled && onChannel != null, role = Role.Button) { onChannel?.invoke() }
                                .wrapContentHeight(),
                        )
                    }
                    Text(
                        shortDate(item.publishedAt),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/**
 * Lets [card] be swiped sideways, either way, to mark its entry: it follows
 * the finger over a strip that says what letting go would do, and always
 * slides back to its place. Let go at [swipeMarks] or further, it calls
 * [onMark] with the opposite of [watched]; a tick is felt on getting that
 * far. A null [onMark] leaves the card unswipeable. With animation off the
 * card stays put under the finger and only the mark changes. [card] takes
 * the modifier that holds it there.
 */
// vetoing every change (the deprecated part) is the only way this box settles back rather than slide its content away
@Suppress("DEPRECATION")
@Composable
private fun SwipeToMark(
    watched: Boolean,
    onMark: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    card: @Composable (Modifier) -> Unit,
) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { false },
        positionalThreshold = { distance -> distance * SWIPE_MARK_SHARE },
    )
    val moves = motionAllowed()
    val haptics = LocalHapticFeedback.current
    val currentWatched by rememberUpdatedState(watched)
    val currentOnMark by rememberUpdatedState(onMark)
    var width by remember { mutableIntStateOf(0) }
    val resting = state.dismissDirection == SwipeToDismissBoxValue.Settled
    val offset = { if (state.dismissDirection == SwipeToDismissBoxValue.Settled) 0f else state.requireOffset() }
    // the mark changes on letting go, but the strip says the same thing until the card is back
    var stripWatched by remember { mutableStateOf(watched) }
    LaunchedEffect(resting, watched) {
        if (resting) {
            stripWatched = watched
        }
    }
    LaunchedEffect(state, haptics) {
        snapshotFlow { swipeMarks(offset(), width.toFloat()) }.collect { farEnough ->
            if (farEnough) {
                haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
            }
        }
    }
    SwipeToDismissBox(
        state = state,
        gesturesEnabled = onMark != null,
        modifier = modifier
            .onSizeChanged { size -> width = size.width }
            // the box never says the finger was lifted, so this watches for it, ahead of the box, taking nothing
            .pointerInput(state) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                    } while (event.changes.any { change -> change.pressed })
                    if (swipeMarks(offset(), size.width.toFloat())) {
                        currentOnMark?.invoke(!currentWatched)
                    }
                }
            },
        backgroundContent = {
            if (moves && !resting) {
                MarkStrip(stripWatched, atStart = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd)
            }
        },
    ) {
        card(if (moves) Modifier else Modifier.absoluteOffset { IntOffset(-offset().roundToInt(), 0) })
    }
}

/** The strip a swiped card uncovers: an icon and what letting go would do, at the side being uncovered ([atStart] for the start). */
@Composable
private fun MarkStrip(watched: Boolean, atStart: Boolean) {
    Row(
        Modifier
            .fillMaxSize()
            .clip(CardShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = 16.dp)
            // the card's own bar and action already say this to a screen reader
            .clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(8.dp, if (atStart) Alignment.Start else Alignment.End),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (watched) SubtubeIcons.EyeOff else SubtubeIcons.Eye, contentDescription = null, modifier = Modifier.size(24.dp))
        Text(
            stringResource(if (watched) R.string.mark_unwatched else R.string.mark_watched),
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
        )
    }
}

/**
 * The bar along a thumbnail's bottom edge, [fraction] of its width filled
 * with Sunflower and nothing drawn along the rest. A change of [fraction]
 * runs along the bar unless the system has animation off.
 */
@Composable
private fun WatchedBar(fraction: Double, modifier: Modifier = Modifier) {
    val shown by animateFloatAsState(
        targetValue = fraction.toFloat().coerceIn(0f, 1f),
        animationSpec = if (motionAllowed()) tween(BAR_FILL_MS) else snap(),
        label = "watched bar",
    )
    Box(modifier.fillMaxWidth().height(ProgressBarHeight)) {
        Box(Modifier.fillMaxWidth(shown).fillMaxHeight().background(Sunflower))
    }
}

/**
 * What a press on the bar hits: a strip reaching [BarTargetAbove] up over the
 * thumbnail from its bottom edge and [BarTargetBelow] down over the text under
 * it, above both and taking no room between them. A press calls [onMark] with
 * the opposite of [watched]; [label] says which that is.
 */
@Composable
private fun WatchedBarTarget(watched: Boolean, label: String, enabled: Boolean, onMark: (Boolean) -> Unit) {
    Box(Modifier.fillMaxWidth().height(0.dp).zIndex(1f)) {
        Box(
            Modifier
                .fillMaxWidth()
                .requiredHeight(BarTargetAbove + BarTargetBelow)
                // a required height is centred on the edge: this moves it up to its uneven reach
                .offset(y = (BarTargetBelow - BarTargetAbove) / 2)
                .clickable(
                    interactionSource = null,
                    indication = null,
                    enabled = enabled,
                    role = Role.Button,
                    onClick = { onMark(!watched) },
                )
                .semantics { contentDescription = label },
        )
    }
}

/**
 * Gives a control at least [height] to press without it taking more room:
 * what it lacks reaches equally above and below its own box.
 */
private fun Modifier.touchHeight(height: Dp): Modifier = layout { measurable, constraints ->
    val room = measurable.minIntrinsicHeight(constraints.maxWidth)
    val pressable = maxOf(room, height.roundToPx())
    val placeable = measurable.measure(constraints.copy(minHeight = pressable, maxHeight = maxOf(pressable, constraints.maxHeight)))
    layout(placeable.width, room) { placeable.place(0, (room - placeable.height) / 2) }
}

/** The message's text. */
fun UiMessage.resolve(context: Context): String = context.getString(resId)
