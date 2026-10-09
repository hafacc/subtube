package cc.hafa.subtube.core

/**
 * The entries the channel list's chips look at: of the [channels] that are
 * on, every one of [items] of the kind the channel shows that passes its
 * filter, watched or not, in the order given. [compiled] gives a channel's
 * compiled filter, for a caller that keeps them.
 */
fun passingItems(
    channels: Collection<ChannelFilter>,
    items: Collection<FeedItem>,
    compiled: (ChannelFilter) -> CompiledFilter = ::compileFilter,
): List<FeedItem> {
    val enabled = channels.filter(ChannelFilter::enabled).associate { channel ->
        channel.channelId to ((channel.contentMode == ContentMode.PLAYLISTS) to compiled(channel))
    }
    return items.filter { item ->
        val entry = enabled[item.channelId]
        if (entry == null) {
            false
        } else {
            val (wantsPlaylists, compiled) = entry
            wantsPlaylists == (item is Playlist) && passesFilter(item, compiled)
        }
    }
}

/**
 * The channels the channel list's chips keep, by id
 * (shared/fixtures/channel-chips.json): those with at least one of [items]
 * inside [timeChip]'s span before [now] and, when a topic is among
 * [selected], in one of those. Null when no span and no topic is chosen,
 * which keeps every channel. [items] is [passingItems], and [published] is
 * [chipFiltered]'s.
 */
fun chipKeptChannels(
    items: Collection<FeedItem>,
    timeChip: TimeChip,
    selected: Collection<String>,
    now: Long,
    published: (FeedItem) -> Long? = { item -> publishedMillis(item.publishedAt) },
): Set<String>? =
    if (timeChip == TimeChip.NONE && knownTopics(selected).isEmpty()) {
        null
    } else {
        chipFiltered(items, timeChip, selected, now, published).mapTo(LinkedHashSet(), FeedItem::channelId)
    }
