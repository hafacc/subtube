package cc.hafa.subtube.core

import kotlin.random.Random
import kotlin.random.nextUInt

/** The orders the feed can be read in. */
enum class FeedSort(override val wire: String) : WireValue {
    NEWEST("newest"),
    OLDEST("oldest"),
    SHORTEST("shortest"),
    LONGEST("longest"),
    TITLE("title"),
    TITLE_REVERSED("titleReversed"),
    RANDOM("random"),
}

/** The sort chips, in row order: each holds an order and, after it, its reverse. Random has none. */
val FEED_SORT_CHIPS: List<List<FeedSort>> = listOf(
    listOf(FeedSort.NEWEST, FeedSort.OLDEST),
    listOf(FeedSort.SHORTEST, FeedSort.LONGEST),
    listOf(FeedSort.TITLE, FeedSort.TITLE_REVERSED),
    listOf(FeedSort.RANDOM),
)

/** Which of [FEED_SORT_CHIPS] holds [sort]. */
fun sortChipOf(sort: FeedSort): Int = FEED_SORT_CHIPS.indexOfFirst { options -> sort in options }

/**
 * The order each sort chip shows: [sort] on its own chip, and on the others
 * the one they showed last ([lastShown], by the chip's place in the row), or
 * their first.
 */
fun shownSorts(sort: FeedSort, lastShown: Map<Int, FeedSort>): List<FeedSort> =
    FEED_SORT_CHIPS.mapIndexed { index, options -> if (sort in options) sort else lastShown[index] ?: options.first() }

/**
 * The order a press on the sort chip at [index] chooses: the one it shows
 * when another chip is selected, and the next of its orders when it is the
 * selected one, which for Random is [sort] again.
 */
fun sortAfterPress(index: Int, sort: FeedSort, lastShown: Map<Int, FeedSort>): FeedSort {
    val options = FEED_SORT_CHIPS[index]
    return if (sort in options) {
        options[(options.indexOf(sort) + 1) % options.size]
    } else {
        shownSorts(sort, lastShown)[index]
    }
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

/** A seed for the random order, picked anew at each full load and each asked-for shuffle, and never synced. */
fun newShuffleSeed(): UInt = Random.nextUInt()

/** A video's length in seconds; null for a playlist or a video without one. */
private fun lengthOf(item: FeedItem): Int? = (item as? Video)?.durationSeconds?.takeIf { seconds -> seconds != 0 }

/**
 * By length, shortest first or, with [longestFirst], longest first; items
 * without a length go last either way, tying with each other.
 */
private fun byLength(longestFirst: Boolean): Comparator<FeedItem> = Comparator { left, right ->
    val leftSeconds = lengthOf(left)
    val rightSeconds = lengthOf(right)
    if (leftSeconds == null || rightSeconds == null) {
        (leftSeconds == null).compareTo(rightSeconds == null)
    } else if (longestFirst) {
        rightSeconds.compareTo(leftSeconds)
    } else {
        leftSeconds.compareTo(rightSeconds)
    }
}

private fun byTitle(items: Collection<FeedItem>, reversed: Boolean): List<FeedItem> {
    val forward = Comparator<Pair<String, FeedItem>> { (left, _), (right, _) -> compareCodePoints(left, right) }
    return items.map { item -> foldCase(item.title) to item }
        .sortedWith((if (reversed) forward.reversed() else forward).thenBy(byNewest) { (_, item) -> item })
        .map { (_, item) -> item }
}

/**
 * The items in one of the feed's orders (shared/fixtures/feed-order.json).
 *
 * A reversed order turns its first key round and nothing else: ties in every
 * order go newest first, then by id ([byNewest]), and items without a length
 * stay last. The title orders ignore case as [compareIgnoringCase] does.
 * [seed] fixes [FeedSort.RANDOM], which orders by [shuffleKey]; the other
 * orders don't read it.
 */
fun sortFeed(items: Collection<FeedItem>, sort: FeedSort, seed: UInt = 0u): List<FeedItem> = when (sort) {
    FeedSort.NEWEST -> items.sortedWith(byNewest)
    FeedSort.OLDEST -> items.sortedWith(compareBy(FeedItem::publishedAt).thenBy(FeedItem::id))
    FeedSort.SHORTEST -> items.sortedWith(byLength(longestFirst = false).then(byNewest))
    FeedSort.LONGEST -> items.sortedWith(byLength(longestFirst = true).then(byNewest))
    FeedSort.TITLE -> byTitle(items, reversed = false)
    FeedSort.TITLE_REVERSED -> byTitle(items, reversed = true)
    FeedSort.RANDOM -> items.map { item -> shuffleKey(seed, item.id) to item }
        .sortedWith(compareBy<Pair<UInt, FeedItem>> { (key, _) -> key }.thenBy(byNewest) { (_, item) -> item })
        .map { (_, item) -> item }
}
