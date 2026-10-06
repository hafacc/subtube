package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonObject

/** A filter field's value as the Drive file spells it. */
interface WireValue {
    /** The JSON string. */
    val wire: String
}

/** Whether a channel's pattern keeps or drops what it finds. */
enum class FilterMode(override val wire: String) : WireValue {
    /** Only what the pattern finds is kept. */
    INCLUDE("include"),

    /** What the pattern finds is dropped. */
    EXCLUDE("exclude"),
}

/** What the per-channel pattern is searched in. */
enum class FilterScope(override val wire: String) : WireValue {
    /** The title only. */
    TITLE("title"),

    /** The title and the description, each on its own. */
    BOTH("both"),

    /** The description only. */
    DESCRIPTION("description"),
}

/** Whether a channel contributes its uploads or its playlists to the feed. */
enum class ContentMode(override val wire: String) : WireValue {
    /** The channel's uploads. */
    VIDEOS("videos"),

    /** The channel's playlists, each one entry. */
    PLAYLISTS("playlists"),
}

/** A video's broadcast kind. */
enum class LiveStatus {
    /** Scheduled, not yet started. */
    UPCOMING,

    /** Being broadcast now. */
    LIVE,

    /** A finished live stream or premiere. */
    VOD,

    /** A plain upload that was never broadcast. */
    NORMAL,
}

/** Per-channel broadcast filter. */
enum class LiveFilter(override val wire: String) : WireValue {
    /** Everything but upcoming. */
    ALL("all"),

    /** Only live streams and their replays. */
    VOD("vod"),

    /** Only plain uploads. */
    NORMAL("normal"),
}

/** Per-channel Shorts filter. */
enum class ShortsFilter(override val wire: String) : WireValue {
    /** Shorts and other uploads alike. */
    ALL("all"),

    /** Hides Shorts. */
    NORMAL("normal"),

    /** Keeps only Shorts. */
    SHORTS("shorts"),
}

/** A channel the account subscribes to on YouTube. */
data class Subscription(
    /** The `UC…` channel id. */
    val channelId: String,
    /** The channel's name. */
    val title: String,
    /** Avatar URL; empty when YouTube gave none. */
    val thumbnail: String,
)

/**
 * A channel's feed settings, with the channel's identity alongside. The Drive
 * file stores only the settings (see [filterFromJson] and [filterToJson]); the
 * identity belongs to YouTube. Null optional fields read as their defaults.
 */
data class ChannelFilter(
    /** The `UC…` channel id. */
    val channelId: String,
    /** The channel's name, from YouTube. */
    val title: String,
    /** The channel's avatar URL, from YouTube; empty when unknown. */
    val thumbnail: String,
    /** Whether the main feed loads the channel. */
    val enabled: Boolean,
    /** A pattern in the shared pattern language; empty means none. */
    val regex: String,
    /** Keep or drop what the pattern finds. */
    val mode: FilterMode,
    /** Null (the default) and false both mean case-insensitive. */
    val caseSensitive: Boolean? = null,
    /** Null means [FilterScope.TITLE]. */
    val searchScope: FilterScope? = null,
    /** Hide videos shorter than this many seconds; null or 0 disables it. */
    val minDurationSeconds: Int? = null,
    /** Null means [LiveFilter.ALL]. */
    val liveFilter: LiveFilter? = null,
    /** Null means [ShortsFilter.ALL]. */
    val shortsFilter: ShortsFilter? = null,
    /** Null means [ContentMode.VIDEOS]. */
    val contentMode: ContentMode? = null,
    /** YouTube category ids; with any that is a topic, only videos in one of them are kept. Null when none are saved. */
    val topics: List<String>? = null,
    /** Added in subtube rather than subscribed to on YouTube; listed while true. */
    val followed: Boolean? = null,
    /** The names of the groups the channel is in ([groupsFromJson]). */
    val groups: List<String> = emptyList(),
    /** The filter object as last read from Drive, so fields this version doesn't know are written back. */
    val stored: JsonObject = JsonObject(emptyMap()),
)

/** A feed entry: a single video or a whole playlist, depending on the channel's content mode. */
sealed interface FeedItem {
    /** The video id or playlist id: the key for watched state and de-duplication. */
    val id: String

    /** The `UC…` id of the channel it belongs to. */
    val channelId: String

    /** That channel's name. */
    val channelTitle: String

    /** The entry's title, with HTML entities decoded. */
    val title: String

    /** The entry's description, as YouTube gives it. */
    val description: String

    /** ISO 8601 timestamp; compared as a string, as the web app does. */
    val publishedAt: String

    /** Thumbnail URL; empty when YouTube gave none. */
    val thumbnail: String
}

/** One uploaded video. */
data class Video(
    /** YouTube's id for the video. */
    val videoId: String,
    override val channelId: String,
    override val channelTitle: String,
    override val title: String,
    override val description: String,
    override val publishedAt: String,
    override val thumbnail: String,
    /** Length in seconds; 0 or null for live or upcoming. */
    val durationSeconds: Int? = null,
    /** Null is treated as [LiveStatus.NORMAL]. */
    val liveStatus: LiveStatus? = null,
    /** Null means not yet classified. */
    val isShort: Boolean? = null,
    /** YouTube's category id, as written; null when it has none. */
    val categoryId: String? = null,
) : FeedItem {
    override val id: String get() = videoId
}

/** One of a channel's playlists, shown as a single feed entry. */
data class Playlist(
    /** YouTube's id for the playlist. */
    val playlistId: String,
    override val channelId: String,
    override val channelTitle: String,
    override val title: String,
    override val description: String,
    /** Creation time, used for feed ordering. */
    override val publishedAt: String,
    override val thumbnail: String,
    /** How many videos it holds. */
    val itemCount: Int,
) : FeedItem {
    override val id: String get() = playlistId
}
