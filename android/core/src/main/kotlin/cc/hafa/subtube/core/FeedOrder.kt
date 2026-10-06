package cc.hafa.subtube.core

import kotlin.random.Random
import kotlin.random.nextUInt

/** The orders the feed can be read in. */
enum class FeedSort(override val wire: String) : WireValue {
    NEWEST("newest"),
    SHORTEST("shortest"),
    TITLE("title"),
    RANDOM("random"),
}

/** Newest first; equal times go by id ascending. Both compare as plain strings. Every other order ends in this one. */
val byNewest: Comparator<FeedItem> = compareByDescending(FeedItem::publishedAt).thenBy(FeedItem::id)

private const val FNV_OFFSET: UInt = 2166136261u
private const val FNV_PRIME: UInt = 16777619u

/**
 * Where the random order puts an item: the 32-bit FNV-1a hash of the UTF-8
 * bytes of [seed] in decimal, a colon, and [id]; smaller first.
 */
fun shuffleKey(seed: UInt, id: String): UInt {
    var hash = FNV_OFFSET
    for (byte in "$seed:$id".toByteArray(Charsets.UTF_8)) {
        hash = (hash xor byte.toUByte().toUInt()) * FNV_PRIME
    }
    return hash
}

/** A seed for the random order, picked anew at each full load and never synced. */
fun newShuffleSeed(): UInt = Random.nextUInt()

/** A video's length in seconds; null for a playlist or a video without one. */
private fun lengthOf(item: FeedItem): Int? = (item as? Video)?.durationSeconds?.takeIf { seconds -> seconds != 0 }

/** Shortest first; items without a length go last, tying with each other. */
private val byShortest: Comparator<FeedItem> = Comparator { left, right ->
    val leftSeconds = lengthOf(left)
    val rightSeconds = lengthOf(right)
    if (leftSeconds == null || rightSeconds == null) {
        (leftSeconds == null).compareTo(rightSeconds == null)
    } else {
        leftSeconds.compareTo(rightSeconds)
    }
}

/**
 * The items in one of the feed's orders (shared/fixtures/feed-order.json).
 *
 * Ties in any order go newest first, then by id ([byNewest]). [FeedSort.TITLE]
 * ignores case as [compareIgnoringCase] does. [seed] fixes [FeedSort.RANDOM],
 * which orders by [shuffleKey]; the other orders don't read it.
 */
fun sortFeed(items: Collection<FeedItem>, sort: FeedSort, seed: UInt = 0u): List<FeedItem> = when (sort) {
    FeedSort.NEWEST -> items.sortedWith(byNewest)
    FeedSort.TITLE -> items.map { item -> foldCase(item.title) to item }
        .sortedWith(compareBy<Pair<String, FeedItem>, String>(::compareCodePoints) { (title, _) -> title }.thenBy(byNewest) { (_, item) -> item })
        .map { (_, item) -> item }
    FeedSort.SHORTEST -> items.sortedWith(byShortest.then(byNewest))
    FeedSort.RANDOM -> items.map { item -> shuffleKey(seed, item.id) to item }
        .sortedWith(compareBy<Pair<UInt, FeedItem>> { (key, _) -> key }.thenBy(byNewest) { (_, item) -> item })
        .map { (_, item) -> item }
}
