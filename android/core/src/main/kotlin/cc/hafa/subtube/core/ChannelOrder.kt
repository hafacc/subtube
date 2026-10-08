package cc.hafa.subtube.core

/** Channels by name: title ignoring case ([compareIgnoringCase]), then id. Every list of channel names uses it. */
val channelsByName: Comparator<ChannelFilter> = compareBy(ignoringCase, ChannelFilter::title).thenBy(ChannelFilter::channelId)

/** Every order a channel list can be in: a [ChannelSort], or [NEWEST_UNWATCHED], which is not a value of the synced setting. */
enum class ChannelListOrder(override val wire: String) : WireValue {
    /** By each channel's newest fetched entry. */
    NEWEST("newest"),

    /** By name, ignoring case. */
    NAME("name"),

    /** By how many unwatched entries pass each channel's filter. */
    UNWATCHED("unwatched"),

    /** By each channel's newest unwatched entry that passes its filter; the Mac and web sidebars' order. */
    NEWEST_UNWATCHED("newestUnwatched"),
}

/** The orders the synced `channelSort` setting chooses between, each with the [order] its list is in. */
enum class ChannelSort(val order: ChannelListOrder) : WireValue {
    NEWEST(ChannelListOrder.NEWEST),
    NAME(ChannelListOrder.NAME),
    UNWATCHED(ChannelListOrder.UNWATCHED),
    ;

    override val wire: String get() = order.wire
}

/**
 * When each channel's newest fetched entry was published, by channel id.
 * Every entry counts, uploads and playlists alike, whatever the channel's
 * filter and watched marks. Channels with nothing fetched are absent.
 */
fun newestFetched(items: List<FeedItem>): Map<String, String> {
    val newest = HashMap<String, String>()
    for (item in items) {
        val known = newest[item.channelId]
        if (known == null || item.publishedAt > known) {
            newest[item.channelId] = item.publishedAt
        }
    }
    return newest
}

/**
 * How many unwatched fetched entries pass each channel's filter, by channel
 * id: the counts [ChannelSort.UNWATCHED] orders by. The chips don't change them.
 */
fun unwatchedCounts(channels: Collection<ChannelFilter>, items: Collection<FeedItem>, watched: Set<String>): Map<String, Int> =
    channels.associate { channel -> channel.channelId to unwatchedPassing(channel, items, watched).size }

/**
 * The order of every channel list (shared/fixtures/channel-order.json).
 *
 * Channels that are off go last, by name, in every sort. By name means by
 * title ignoring case ([compareIgnoringCase]), then by id. Channels that are
 * on go, for [ChannelSort.NEWEST] (the default), those in [newest] first,
 * newest first, then those with nothing fetched, ties and the latter by name;
 * for [ChannelSort.NAME], by name; for [ChannelSort.UNWATCHED], by their count
 * in [unwatched] (absent reads as 0), most first, ties in the newest order;
 * for [ChannelListOrder.NEWEST_UNWATCHED], those in [newestUnwatched] (when
 * the newest of the entries [unwatched] counts was published) first, newest
 * first, then the rest, ties and the rest in the newest order.
 * See [newestFetched] and [unwatchedCounts] for the first two maps.
 */
fun orderChannels(
    channels: Collection<ChannelFilter>,
    newest: Map<String, String>,
    sort: ChannelListOrder = ChannelListOrder.NEWEST,
    unwatched: Map<String, Int> = emptyMap(),
    newestUnwatched: Map<String, String> = emptyMap(),
): List<ChannelFilter> {
    val byNewestVideo = compareBy<ChannelFilter> { channel -> channel.channelId !in newest }
        .thenByDescending { channel -> newest[channel.channelId].orEmpty() }
        .then(channelsByName)
    val whenOn = when (sort) {
        ChannelListOrder.NEWEST -> byNewestVideo
        ChannelListOrder.NAME -> channelsByName
        ChannelListOrder.UNWATCHED -> compareByDescending<ChannelFilter> { channel -> unwatched[channel.channelId] ?: 0 }.then(byNewestVideo)
        ChannelListOrder.NEWEST_UNWATCHED -> compareBy<ChannelFilter> { channel -> channel.channelId !in newestUnwatched }
            .thenByDescending { channel -> newestUnwatched[channel.channelId].orEmpty() }
            .then(byNewestVideo)
    }
    val (on, off) = channels.partition(ChannelFilter::enabled)
    return on.sortedWith(whenOn) + off.sortedWith(channelsByName)
}

/**
 * The rows a channel list keeps while it is on screen, as channel ids:
 * [held], the rows last taken, without the ids [ordered] no longer has, then
 * the ids of [kept] that [held] lacks, in [ordered]'s order. [kept] is the
 * ids the list's chips keep ([chipKeptChannels]); null keeps every one. So a
 * switch, a count or a filter that changes [ordered] or [kept] neither moves
 * a row nor takes one out; taking [listedOrder] as the new [held] does.
 */
fun heldOrder(held: List<String>, ordered: List<String>, kept: Set<String>? = null): List<String> {
    val present = ordered.toHashSet()
    val staying = held.filter { channelId -> channelId in present }
    val known = staying.toHashSet()
    return staying + listedOrder(ordered, kept).filter { channelId -> channelId !in known }
}

/** The rows a channel list takes when it is put in order: the ids of [ordered] that are in [kept], or all of them when it is null. */
fun listedOrder(ordered: List<String>, kept: Set<String>?): List<String> =
    if (kept == null) ordered else ordered.filter { channelId -> channelId in kept }
