package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** Keys a stored filter must never carry: the channel's identity belongs to YouTube. */
private val IDENTITY_KEYS = setOf("channelId", "title", "thumbnail")

private fun <Value> JsonElement?.oneOf(values: Array<Value>): Value? where Value : Enum<Value>, Value : WireValue {
    val text = stringOrNull() ?: return null
    return values.firstOrNull { value -> value.wire == text }
}

/** A positive whole number of seconds, or null for anything else (0, negative, fractional, a string). */
private fun JsonElement?.positiveSeconds(): Int? {
    val primitive = (this as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString) ?: return null
    val number = primitive.longOrNull ?: primitive.doubleOrNull?.takeIf { value -> value % 1.0 == 0.0 }?.toLong()
    return number?.takeIf { value -> value in 1..Int.MAX_VALUE }?.toInt()
}

/**
 * Read a stored filter. A field that is missing or holds a value this version
 * doesn't recognize reads as its default (shared/fixtures/filters.json).
 */
fun filterFromJson(channelId: String, title: String, thumbnail: String, stored: JsonObject): ChannelFilter = ChannelFilter(
    channelId = channelId,
    title = title,
    thumbnail = thumbnail,
    enabled = stored["enabled"].booleanValue() != false,
    regex = stored["regex"].stringOrNull().orEmpty(),
    mode = stored["mode"].oneOf(FilterMode.entries.toTypedArray()) ?: FilterMode.INCLUDE,
    caseSensitive = stored["caseSensitive"].booleanValue(),
    searchScope = stored["searchScope"].oneOf(FilterScope.entries.toTypedArray()),
    minDurationSeconds = stored["minDurationSeconds"].positiveSeconds(),
    liveFilter = stored["liveFilter"].oneOf(LiveFilter.entries.toTypedArray()),
    shortsFilter = stored["shortsFilter"].oneOf(ShortsFilter.entries.toTypedArray()),
    contentMode = stored["contentMode"].oneOf(ContentMode.entries.toTypedArray()),
    topics = stored["topics"].stringsOrNull(),
    followed = stored["followed"].booleanValue(),
    groups = groupsFromJson(stored["groups"]),
    stored = stored,
)

/**
 * The filter object to store: [ChannelFilter.stored] with each setting that
 * was changed since it was read written over it. A setting left alone keeps
 * its stored value, even one this version didn't recognize, so a newer
 * client's values and fields survive; the identity keys are always dropped.
 */
fun filterToJson(filter: ChannelFilter): JsonObject {
    val before = filterFromJson(filter.channelId, filter.title, filter.thumbnail, filter.stored)
    val out = LinkedHashMap(filter.stored)
    IDENTITY_KEYS.forEach(out::remove)
    fun write(key: String, changed: Boolean, value: JsonElement?) {
        if (changed) {
            if (value == null) out.remove(key) else out[key] = value
        }
    }
    write("enabled", filter.enabled != before.enabled || "enabled" !in out, JsonPrimitive(filter.enabled))
    write("regex", filter.regex != before.regex || "regex" !in out, JsonPrimitive(filter.regex))
    write("mode", filter.mode != before.mode || "mode" !in out, JsonPrimitive(filter.mode.wire))
    write("caseSensitive", filter.caseSensitive != before.caseSensitive, filter.caseSensitive?.let(::JsonPrimitive))
    write("searchScope", filter.searchScope != before.searchScope, filter.searchScope?.let { scope -> JsonPrimitive(scope.wire) })
    write("minDurationSeconds", filter.minDurationSeconds != before.minDurationSeconds, filter.minDurationSeconds?.let(::JsonPrimitive))
    write("liveFilter", filter.liveFilter != before.liveFilter, filter.liveFilter?.let { live -> JsonPrimitive(live.wire) })
    write("shortsFilter", filter.shortsFilter != before.shortsFilter, filter.shortsFilter?.let { shorts -> JsonPrimitive(shorts.wire) })
    write("contentMode", filter.contentMode != before.contentMode, filter.contentMode?.let { content -> JsonPrimitive(content.wire) })
    write("topics", filter.topics != before.topics, filter.topics?.let { ids -> JsonArray(ids.distinct().map(::JsonPrimitive)) })
    write("followed", filter.followed != before.followed, filter.followed?.let(::JsonPrimitive))
    write("groups", filter.groups != before.groups, JsonArray(filter.groups.map(::JsonPrimitive)))
    return JsonObject(out)
}

/** A filter as an edit saves it: a pattern that is not built from phrases is dropped. */
fun editedFilter(filter: ChannelFilter): ChannelFilter = filter.copy(regex = phrasePatternOnly(filter.regex))

/** A [ChannelFilter] with its defaults applied and its pattern compiled. */
data class CompiledFilter(
    /** Whether the main feed loads the channel. */
    val enabled: Boolean,
    /** Null when there is no pattern, or when it isn't one built from phrases. */
    val regex: Regex?,
    /** Keep or drop what the pattern finds. */
    val mode: FilterMode,
    /** What the pattern is searched in. */
    val scope: FilterScope,
    /** The shortest video kept, in seconds; 0 for no limit. */
    val minDurationSeconds: Int,
    /** Which broadcast kinds are kept. */
    val liveFilter: LiveFilter,
    /** Whether Shorts are kept, hidden or the only ones kept. */
    val shortsFilter: ShortsFilter,
    /** The categories kept; empty keeps every one. */
    val topics: Set<String>,
    /** Why the saved pattern was ignored, or null. */
    val error: String?,
)

/**
 * Compile a filter. A pattern outside the shared pattern language, or one not
 * built from phrases, reads as no pattern (shared/fixtures/filters.json).
 */
fun compileFilter(filter: ChannelFilter): CompiledFilter {
    val base = CompiledFilter(
        enabled = filter.enabled,
        regex = null,
        mode = filter.mode,
        scope = filter.searchScope ?: FilterScope.TITLE,
        minDurationSeconds = filter.minDurationSeconds ?: 0,
        liveFilter = filter.liveFilter ?: LiveFilter.ALL,
        shortsFilter = filter.shortsFilter ?: ShortsFilter.ALL,
        topics = knownTopics(filter.topics.orEmpty()),
        error = null,
    )
    return if (filter.regex.isEmpty()) {
        base
    } else {
        val regex = compilePattern(filter.regex, filter.caseSensitive == true)
        when {
            regex == null -> base.copy(error = "unsupported pattern")
            patternToPhrases(filter.regex) == null -> base.copy(error = "not phrases")
            else -> base.copy(regex = regex)
        }
    }
}

/** Whether a feed item passes its channel's filter. */
fun passesFilter(item: FeedItem, compiled: CompiledFilter): Boolean {
    val regex = compiled.regex
    return if (item is Video && !passesVideoGates(item, compiled)) {
        false
    } else if (regex == null) {
        true
    } else {
        // title and description are searched separately, so a match can't straddle the two
        val matches =
            (compiled.scope != FilterScope.DESCRIPTION && regex.containsMatchIn(item.title)) ||
                (compiled.scope != FilterScope.TITLE && regex.containsMatchIn(item.description))
        if (compiled.mode == FilterMode.INCLUDE) matches else !matches
    }
}

/** The Shorts, broadcast, duration and topic gates, which playlists skip. */
private fun passesVideoGates(video: Video, compiled: CompiledFilter): Boolean {
    // a channel that gates on Shorts also hides what it couldn't judge
    val shortsOk = when (compiled.shortsFilter) {
        ShortsFilter.ALL -> true
        ShortsFilter.NORMAL -> video.isShort == false
        ShortsFilter.SHORTS -> video.isShort == true
    }
    val status = video.liveStatus ?: LiveStatus.NORMAL
    val liveOk = when {
        status == LiveStatus.UPCOMING -> false
        compiled.liveFilter == LiveFilter.VOD -> status != LiveStatus.NORMAL
        compiled.liveFilter == LiveFilter.NORMAL -> status == LiveStatus.NORMAL
        else -> true
    }
    // an unknown duration (absent or 0, e.g. live) is kept
    val duration = video.durationSeconds ?: 0
    val longEnough = compiled.minDurationSeconds <= 0 || duration == 0 || duration >= compiled.minDurationSeconds
    return shortsOk && liveOk && longEnough && (compiled.topics.isEmpty() || video.categoryId in compiled.topics)
}
