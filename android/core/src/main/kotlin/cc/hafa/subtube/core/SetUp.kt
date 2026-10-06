package cc.hafa.subtube.core

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/** The Shorts setting most of [channels] have, which setup starts its choice on; [ShortsFilter.ALL] on a tie or with none. */
fun commonShortsFilter(channels: Collection<ChannelFilter>): ShortsFilter {
    val counts = channels.groupingBy { channel -> channel.shortsFilter ?: ShortsFilter.ALL }.eachCount()
    val most = counts.values.maxOrNull() ?: 0
    val leaders = counts.filterValues { count -> count == most }.keys
    return if (leaders.size == 1) leaders.first() else ShortsFilter.ALL
}

/** Setup's starting point, kept on the device while channels that were on then still wait to be loaded. */
data class PendingStart(
    /** The choice made. */
    val start: StartFrom,
    /** When setup finished (ms since the epoch): what the choice's span counts back from. */
    val cutoff: Long,
    /** The channels that were on and have not been fully fetched since, in the order kept. */
    val channels: List<String>,
)

/** What setup's starting point comes to once some of its channels are fetched. */
data class StartApplied(
    /** The ids to mark watched. */
    val marks: List<String>,
    /** What still waits; null when every channel has had its turn. */
    val pending: PendingStart?,
)

/**
 * Setup's starting point for a finished setup; null when nothing is to be
 * marked, with [StartFrom.ALL] or no channel on.
 */
fun pendingStart(start: StartFrom, cutoff: Long, channelsOn: Collection<String>): PendingStart? =
    if (start.spanMs == null || channelsOn.isEmpty()) null else PendingStart(start, cutoff, channelsOn.distinct())

/**
 * Apply [pending] (shared/fixtures/setup-start.json) to the channels just
 * [fetched] in full, whose entries are among [items]: every entry of a
 * waiting channel from before the starting point is marked ([startMarks]),
 * in the order of [items], and that channel waits no longer. A channel that
 * failed or was skipped isn't in [fetched] and keeps waiting; one turned on
 * after setup never waited. With no [pending] nothing is marked.
 */
fun applyStart(pending: PendingStart?, fetched: Collection<String>, items: Collection<FeedItem>): StartApplied =
    if (pending == null) {
        StartApplied(emptyList(), null)
    } else {
        val reached = pending.channels.filter { channelId -> channelId in fetched }.toSet()
        val marks = startMarks(items.filter { item -> item.channelId in reached }, pending.start, pending.cutoff)
        val waiting = pending.channels.filter { channelId -> channelId !in reached }
        StartApplied(marks, if (waiting.isEmpty()) null else pending.copy(channels = waiting))
    }

/** [pending] as the text the device keeps. */
fun encodePendingStart(pending: PendingStart): String = JsonObject(
    mapOf(
        "start" to JsonPrimitive(pending.start.wire),
        "cutoff" to JsonPrimitive(pending.cutoff),
        "channels" to JsonArray(pending.channels.map(::JsonPrimitive)),
    ),
).toString()

/** Read what [encodePendingStart] wrote; null for anything else. */
fun decodePendingStart(text: String?): PendingStart? {
    val root = try {
        text?.let(Json::parseToJsonElement) as? JsonObject
    } catch (_: SerializationException) {
        null
    }
    val start = StartFrom.entries.firstOrNull { choice -> choice.wire == root?.get("start").stringOrNull() }
    val cutoff = (root?.get("cutoff") as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.longOrNull
    val channels = root?.get("channels").stringsOrNull()
    return if (start == null || cutoff == null || channels == null) null else PendingStart(start, cutoff, channels)
}
