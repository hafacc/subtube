package cc.hafa.subtube.core

/**
 * What auto-play plays after [endedId]: the first entry after it in [shown],
 * the list as shown, that isn't in [watched]. Null at the end of the list, or
 * when the ended entry isn't in it.
 */
fun nextUnwatched(shown: List<FeedItem>, endedId: String, watched: Set<String>): FeedItem? {
    val position = shown.indexOfFirst { item -> item.id == endedId }
    return if (position == -1) {
        null
    } else {
        shown.drop(position + 1).firstOrNull { item -> item.id !in watched }
    }
}
