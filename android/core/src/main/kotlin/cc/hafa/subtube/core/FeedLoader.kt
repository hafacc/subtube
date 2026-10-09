package cc.hafa.subtube.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** 50 is the most one playlistItems page holds, and still costs 1 quota unit. */
const val UPLOADS_PER_CHANNEL: Int = 50

/** How many channels are fetched at once. */
const val FETCH_CONCURRENCY: Int = 6

/** A channel and the kind of entry fetched for it, the unit that is fetched. */
typealias ChannelKind = Pair<String, ContentMode>

/**
 * Which of the [held] channel kinds stay when a full load brings [loaded].
 * A loaded channel's other kind is dropped, unless it is the kind the channel
 * shows now ([current]): it was switched while the load ran and fetched on its
 * own. A channel no load brings ([lapsed]: off or no longer listed, and not
 * the one whose page is open) keeps nothing, so it is fetched afresh when it
 * is next wanted. Any other channel the load didn't bring keeps everything.
 */
fun keptAfterLoad(
    held: Set<ChannelKind>,
    loaded: Set<ChannelKind>,
    current: Set<ChannelKind>,
    lapsed: Set<String> = emptySet(),
): Set<ChannelKind> {
    val loadedIds = loaded.mapTo(HashSet()) { (channelId, _) -> channelId }
    return held.filterTo(HashSet()) { kind ->
        if (kind.first in loadedIds) kind !in loaded && kind in current else kind.first !in lapsed
    }
}

/** Run [worker] over [items] with at most [limit] running at once, keeping the input order. */
suspend fun <Item, Result> mapWithConcurrency(
    items: List<Item>,
    limit: Int,
    worker: suspend (Item) -> Result,
): List<Result> {
    val permits = Semaphore(limit)
    return coroutineScope {
        items.map { item -> async { permits.withPermit { worker(item) } } }.awaitAll()
    }
}

/** Whether a filter needs to know which videos are Shorts: uploads, with Shorts hidden or the only ones shown. */
fun needsShorts(filter: ChannelFilter): Boolean =
    filter.contentMode != ContentMode.PLAYLISTS && (filter.shortsFilter ?: ShortsFilter.ALL) != ShortsFilter.ALL

/** One channel's fetched entries, with the mode they were fetched in. */
data class ChannelItems(
    /** Whether they are the channel's uploads or its playlists. */
    val mode: ContentMode,
    /** Whether the channel's Shorts list was read for them, so [Video.isShort] is set wherever it can be. */
    val shorts: Boolean,
    /** The entries, newest first. */
    val items: List<FeedItem>,
)

/** Whether [fetched] is what [filter] needs: its mode, with Shorts marks when it filters on them. */
fun covers(fetched: ChannelItems, filter: ChannelFilter): Boolean =
    fetched.mode == (filter.contentMode ?: ContentMode.VIDEOS) && (fetched.shorts || !needsShorts(filter))

/**
 * What [channel]'s filter needs, from what is already fetched for it ([have])
 * where that helps: nothing more, only the Shorts list ([addShorts]), or
 * everything ([fetchAll]).
 */
suspend fun completeItems(
    channel: ChannelFilter,
    have: ChannelItems?,
    fetchAll: suspend (ChannelFilter) -> ChannelItems,
    addShorts: suspend (ChannelFilter, ChannelItems) -> ChannelItems,
): ChannelItems = when {
    have != null && covers(have, channel) -> have
    have != null && covers(have.copy(shorts = true), channel) -> addShorts(channel, have)
    else -> fetchAll(channel)
}

/** What fetching a load's channels came to. */
data class FetchedChannels(
    /** Each fetched channel's entries, with the mode they were fetched in. */
    val fetched: Map<String, ChannelItems>,
    /** Channels that weren't fetched without ending the load; any makes it partial. */
    val failed: Set<String>,
    /** Whether YouTube's daily limit refused a request, after which none was sent. */
    val dailyLimit: Boolean,
)

/** The share of a load's progress that reading the subscription list stands for, so the bar never sits at nothing. */
const val LOAD_PROGRESS_START: Double = 0.05

/**
 * How far a full load has come, from [LOAD_PROGRESS_START] to 1: the start,
 * then the rest by [finished] of the [total] channels to fetch (fetched,
 * failed or skipped alike). A null [total] is a load still reading the
 * subscription list; none to fetch is a load that is through.
 */
fun loadProgress(finished: Int, total: Int?): Double = when {
    total == null -> LOAD_PROGRESS_START
    total <= 0 -> 1.0
    else -> LOAD_PROGRESS_START + (1 - LOAD_PROGRESS_START) * finished.coerceIn(0, total) / total
}

/**
 * Fetch each of [channels] with [fetchOne], [FETCH_CONCURRENCY] at a time. A
 * channel whose fetch fails is in [FetchedChannels.failed]; once one is
 * refused for YouTube's daily limit the rest aren't asked for and are in it
 * too. A refused token or a missing permission ends the whole fetch.
 * [onFinished] gets how many channels are through, fetched, failed or
 * skipped, each time one more is.
 */
suspend fun fetchChannels(
    channels: List<ChannelFilter>,
    onFinished: (finished: Int) -> Unit = {},
    fetchOne: suspend (ChannelFilter) -> ChannelItems,
): FetchedChannels {
    val lock = Any()
    val fetched = LinkedHashMap<String, ChannelItems>()
    val failed = LinkedHashSet<String>()
    var dailyLimit = false
    mapWithConcurrency(channels, FETCH_CONCURRENCY) { channel ->
        try {
            if (synchronized(lock) { dailyLimit }) {
                synchronized(lock) { failed.add(channel.channelId) }
            } else {
                val items = fetchOne(channel)
                synchronized(lock) { fetched[channel.channelId] = items }
            }
        } catch (caught: CancellationException) {
            throw caught
        } catch (caught: TokenExpiredException) {
            throw caught
        } catch (caught: InsufficientScopeException) {
            throw caught
        } catch (caught: Exception) {
            synchronized(lock) {
                dailyLimit = dailyLimit || caught is DailyLimitException
                failed.add(channel.channelId)
            }
        }
        onFinished(synchronized(lock) { fetched.size + failed.size })
    }
    // in the channels' order, whatever order the fetches ended in
    return FetchedChannels(channels.mapNotNull { channel -> fetched[channel.channelId]?.let { items -> channel.channelId to items } }.toMap(), failed, dailyLimit)
}

/** What one feed load found. */
data class FeedData(
    /** The account's YouTube subscriptions at this load. */
    val subscriptions: List<Subscription>,
    /** The channels with their filters, snapshotted at this load. */
    val channels: Map<String, ChannelFilter>,
    /** Each fetched channel's entries, with the mode they were fetched in. */
    val fetched: Map<String, ChannelItems>,
    /** Channels that weren't fetched without ending the load; any makes the result partial. */
    val failed: Set<String>,
    /** Whether YouTube's daily limit refused a request, after which none was sent. */
    val dailyLimit: Boolean,
) {
    /** Everything the load fetched. */
    val items: List<FeedItem> get() = fetched.values.flatMap(ChannelItems::items)
}

/**
 * Loads the feed: subscriptions and synced filters, then every enabled
 * channel's items. Everything runs on [compute], whatever thread asks.
 */
class FeedLoader(
    private val youtube: YouTubeClient,
    private val store: SyncStore,
    /** Asks `/shorts/{id}` directly, for when a channel's Shorts list isn't served. */
    private val probe: (suspend (String) -> Boolean?)?,
    /** Where answers are read and entries built, so a caller on the main thread isn't held up. */
    private val compute: CoroutineDispatcher = Dispatchers.Default,
) {
    /**
     * A channel's newest entries: uploads or playlists, as its filter says. The
     * Shorts list is read only when the filter [needsShorts]. The videos
     * already [held], by id, are not asked for again ([YouTubeClient.fetchUploads]).
     */
    suspend fun fetchChannel(channel: ChannelFilter, token: String, held: Map<String, Video> = emptyMap()): ChannelItems = withContext(compute) {
        if (channel.contentMode == ContentMode.PLAYLISTS) {
            ChannelItems(ContentMode.PLAYLISTS, shorts = false, youtube.fetchPlaylists(channel.channelId, channel.title, token))
        } else {
            val shorts = needsShorts(channel)
            ChannelItems(
                ContentMode.VIDEOS,
                shorts,
                youtube.fetchUploads(channel.channelId, channel.title, token, UPLOADS_PER_CHANNEL, probe, judgeShorts = shorts, held = held),
            )
        }
    }

    /** Uploads fetched without their channel's Shorts list, now with it: one request, or none when no video could be a Short. */
    suspend fun addShortsMarks(channel: ChannelFilter, fetched: ChannelItems, token: String): ChannelItems = withContext(compute) {
        ChannelItems(
            ContentMode.VIDEOS,
            shorts = true,
            youtube.markShorts(fetched.items.filterIsInstance<Video>(), channel.channelId, token, UPLOADS_PER_CHANNEL, probe),
        )
    }

    /** What [channel]'s filter needs, building on what is already fetched for it ([have]); see [completeItems] and, for [held], [fetchChannel]. */
    suspend fun complete(channel: ChannelFilter, have: ChannelItems?, token: String, held: Map<String, Video> = emptyMap()): ChannelItems = completeItems(
        channel,
        have,
        fetchAll = { wanted -> fetchChannel(wanted, token, held) },
        addShorts = { wanted, fetched -> addShortsMarks(wanted, fetched, token) },
    )

    /**
     * Load everything, calling [onChannels] once the channels are known. An
     * expired token or a missing scope fails the whole load; any other channel
     * failure is recorded in [FeedData.failed], and after YouTube's daily limit
     * refuses a request no more are sent ([fetchChannels]). The load builds on
     * what [prefetched] fetched, or is still fetching, for a channel that is on
     * instead of fetching it again. [onProgress] gets how many of the channels
     * to fetch are through, from none on. [held] is the videos of the last
     * load, by id ([fetchChannel]). [subscribed] is the subscriptions when
     * they and the store have only just been read, as first run does, so
     * neither is read again. [onProgress] and [onChannels] are called
     * on [compute], not on the caller's thread.
     */
    suspend fun load(
        token: String,
        prefetched: Prefetch? = null,
        held: Map<String, Video> = emptyMap(),
        subscribed: List<Subscription>? = null,
        onProgress: (finished: Int, total: Int) -> Unit = { _, _ -> },
        onChannels: (List<Subscription>, Map<String, ChannelFilter>) -> Unit,
    ): FeedData = withContext(compute) {
        val subscriptions = subscribed ?: coroutineScope {
            val fetched = async { youtube.fetchSubscriptions(token) }
            store.load()
            fetched.await()
        }
        val channels = store.channels(subscriptions)
        onChannels(subscriptions, channels)
        val enabled = channels.values.filter(ChannelFilter::enabled)
        onProgress(0, enabled.size)
        val loaded = fetchChannels(enabled, onFinished = { finished -> onProgress(finished, enabled.size) }) { channel ->
            complete(channel, prefetched?.items(channel.channelId), token, held)
        }
        FeedData(subscriptions, channels, loaded.fetched, loaded.failed, loaded.dailyLimit)
    }
}
