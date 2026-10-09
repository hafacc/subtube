package cc.hafa.subtube.core

/**
 * The ids of [channel]'s unwatched entries: each of its entries among [shown],
 * of the kind it shows, that passes its filter and isn't in [watched]. In the
 * order of [shown], each id once. [compiled] is the channel's compiled
 * filter, for a caller that keeps it.
 */
fun unwatchedPassing(
    channel: ChannelFilter,
    shown: Collection<FeedItem>,
    watched: Set<String>,
    compiled: CompiledFilter = compileFilter(channel),
): List<String> {
    val wantsPlaylists = channel.contentMode == ContentMode.PLAYLISTS
    return shown
        .filter { item -> item.channelId == channel.channelId && wantsPlaylists == (item is Playlist) && passesFilter(item, compiled) }
        .map(FeedItem::id)
        .distinct()
        .filter { id -> id !in watched }
}
