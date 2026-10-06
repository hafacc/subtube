package cc.hafa.subtube.core

import java.time.Instant
import java.time.format.DateTimeParseException

/** The topics: YouTube's fifteen video categories by `snippet.categoryId`, with their labels. */
val CATEGORY_NAMES: Map<String, String> = mapOf(
    "1" to "Film & Animation",
    "2" to "Autos & Vehicles",
    "10" to "Music",
    "15" to "Pets & Animals",
    "17" to "Sports",
    "19" to "Travel & Events",
    "20" to "Gaming",
    "22" to "People & Blogs",
    "23" to "Comedy",
    "24" to "Entertainment",
    "25" to "News & Politics",
    "26" to "Howto & Style",
    "27" to "Education",
    "28" to "Science & Technology",
    "29" to "Nonprofits & Activism",
)

/** A category id's label; null for an id that is not one of YouTube's fifteen. */
fun topicLabel(categoryId: String?): String? = categoryId?.let(CATEGORY_NAMES::get)

/** A feed item's topic: its category id when that is one of the fifteen; a playlist has none. */
fun itemTopic(item: FeedItem): String? = (item as? Video)?.categoryId?.takeIf { id -> id in CATEGORY_NAMES }

/** The ids among [categoryIds] that are topics, each once, in the order given. */
fun knownTopics(categoryIds: Collection<String>): Set<String> = categoryIds.filterTo(LinkedHashSet()) { id -> id in CATEGORY_NAMES }

private const val DAY_MS: Long = 86_400_000

/** The time chips: how far back a list reaches. */
enum class TimeChip(
    override val wire: String,
    /** The length of the span in milliseconds, a month being 30 days; null for no limit. */
    val spanMs: Long?,
) : WireValue {
    NONE("none", null),
    DAY("day", DAY_MS),
    WEEK("week", 7 * DAY_MS),
    MONTH("month", 30 * DAY_MS),
}

/** Where setup starts the feed: everything older is marked watched. Kept on the device, not synced. */
enum class StartFrom(
    override val wire: String,
    /** The length of the span in milliseconds; null for all time. */
    val spanMs: Long?,
) : WireValue {
    DAY("day", DAY_MS),
    WEEK("week", 7 * DAY_MS),
    ALL("all", null),
}

/**
 * Whether [publishedAt], an RFC 3339 UTC time, is no more than [spanMs] before
 * [now] (ms since the epoch); the boundary is inside. A time that can't be
 * read is outside, as on the web.
 */
fun publishedWithin(publishedAt: String, spanMs: Long, now: Long): Boolean {
    val published = try {
        Instant.parse(publishedAt).toEpochMilli()
    } catch (_: DateTimeParseException) {
        null
    }
    return published != null && now - published <= spanMs
}

/** The topics of [counts] by how many items have each, most first, then by label ignoring case. */
private fun byCountThenLabel(counts: Map<String, Int>): List<String> = counts.keys.sortedWith(
    compareByDescending<String> { id -> counts.getValue(id) }.thenBy(ignoringCase) { id -> CATEGORY_NAMES.getValue(id) },
)

private fun countTopics(items: Collection<FeedItem>, counts: MutableMap<String, Int>): Map<String, Int> {
    for (item in items) {
        val topic = itemTopic(item) ?: continue
        counts[topic] = (counts[topic] ?: 0) + 1
    }
    return counts
}

/**
 * The topic chips for a list, as category ids in row order
 * (shared/fixtures/feed-chips.json): every topic an entry of [items] has plus
 * every one in [selected], by how many entries have it, most first, then by
 * label ignoring case. [items] is the list after the channel filters and the
 * watched chip, before [chipFiltered].
 */
fun chipRow(items: Collection<FeedItem>, selected: Collection<String>): List<String> =
    byCountThenLabel(countTopics(items, knownTopics(selected).associateWithTo(LinkedHashMap()) { 0 }))

/** All fifteen topics for a channel's filter editor: by how many of its fetched videos have each, most first, then by label. */
fun editorTopics(items: Collection<FeedItem>): List<String> =
    byCountThenLabel(countTopics(items, CATEGORY_NAMES.keys.associateWithTo(LinkedHashMap()) { 0 }))

/**
 * The entries the chips keep, in the order given: inside [timeChip]'s span
 * before [now], and in a topic of [selected] when it holds any.
 */
fun chipFiltered(items: Collection<FeedItem>, timeChip: TimeChip, selected: Collection<String>, now: Long): List<FeedItem> {
    val wanted = knownTopics(selected)
    val spanMs = timeChip.spanMs
    return items.filter { item ->
        (spanMs == null || publishedWithin(item.publishedAt, spanMs, now)) &&
            (wanted.isEmpty() || itemTopic(item) in wanted)
    }
}

/**
 * The ids setup's starting point marks watched at the first load: every entry
 * of [items] published more than [start]'s span before [now], in the order
 * given. [items] is everything fetched for the channels that are on, whatever
 * their filters keep.
 */
fun startMarks(items: Collection<FeedItem>, start: StartFrom, now: Long): List<String> {
    val spanMs = start.spanMs
    return if (spanMs == null) {
        emptyList()
    } else {
        items.filter { item -> !publishedWithin(item.publishedAt, spanMs, now) }.map(FeedItem::id)
    }
}
