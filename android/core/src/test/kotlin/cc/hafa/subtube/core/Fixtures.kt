package cc.hafa.subtube.core

fun channel(
    regex: String = "",
    mode: FilterMode = FilterMode.INCLUDE,
    caseSensitive: Boolean? = null,
    searchScope: FilterScope? = null,
    minDurationSeconds: Int? = null,
    liveFilter: LiveFilter? = null,
    shortsFilter: ShortsFilter? = null,
): ChannelFilter = ChannelFilter(
    channelId = "UC1",
    title = "Chan",
    thumbnail = "",
    enabled = true,
    regex = regex,
    mode = mode,
    caseSensitive = caseSensitive,
    searchScope = searchScope,
    minDurationSeconds = minDurationSeconds,
    liveFilter = liveFilter,
    shortsFilter = shortsFilter,
)

fun video(
    videoId: String = "v1",
    title: String = "Hello World",
    description: String = "",
    publishedAt: String = "2026-01-01T00:00:00Z",
    durationSeconds: Int? = 600,
    liveStatus: LiveStatus? = LiveStatus.NORMAL,
    isShort: Boolean? = null,
): Video = Video(
    videoId = videoId,
    channelId = "UC1",
    channelTitle = "Chan",
    title = title,
    description = description,
    publishedAt = publishedAt,
    thumbnail = "",
    durationSeconds = durationSeconds,
    liveStatus = liveStatus,
    isShort = isShort,
)

fun playlist(title: String = "Episode 1"): Playlist = Playlist(
    playlistId = "PL1",
    channelId = "UC1",
    channelTitle = "Chan",
    title = title,
    description = "",
    publishedAt = "2026-01-01T00:00:00Z",
    thumbnail = "",
    itemCount = 5,
)
