package cc.hafa.subtube.core

import java.io.IOException
import java.util.logging.Level
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

/** A channel's uploads playlist id: its channel id with "UC" swapped for "UU". */
fun uploadsPlaylistId(channelId: String): String = "UU" + channelId.drop(2)

/**
 * A channel's Shorts, as their own playlist: "UUSH" in place of "UC".
 * Undocumented, like the `/shorts/` redirect.
 */
fun shortsPlaylistId(channelId: String): String = "UUSH" + channelId.drop(2)

/** A channel as subtube lists it outside the feed. */
data class ChannelSummary(
    /** The `UC…` channel id. */
    val channelId: String,
    /** The channel's name. */
    val title: String,
    /** Avatar URL; empty when YouTube gave none. */
    val thumbnail: String,
    /** The `@handle`, when YouTube reports one. */
    val handle: String?,
)

/** A video's duration, broadcast kind and category id, which playlistItems doesn't report. */
data class VideoDetails(
    /** Length in seconds; 0 for live or upcoming. */
    val durationSeconds: Int,
    /** The video's broadcast kind. */
    val liveStatus: LiveStatus,
    /** YouTube's category id, as written; null when it has none. */
    val categoryId: String? = null,
)

/** The statuses that mean the server failed, not the request. */
private val SERVER_ERRORS = 500..599

/** Titles the Data API gives entries that can't be played. */
private val HIDDEN_TITLES = setOf("Private video", "Deleted video")

/** The parts of a `thumbnails` object that are read, as a `fields` selector. */
private const val THUMBNAIL_FIELDS = "thumbnails(default(url),medium(url))"

// each request's `fields`: exactly what its response class below reads, so YouTube sends nothing else
private const val SUBSCRIPTION_FIELDS = "nextPageToken,items(snippet(title,resourceId(channelId),$THUMBNAIL_FIELDS))"
private const val VIDEO_FIELDS = "items(id,snippet(liveBroadcastContent,categoryId),contentDetails(duration),liveStreamingDetails(actualEndTime))"
private const val UPLOAD_FIELDS =
    "items(snippet(title,description,publishedAt,videoOwnerChannelId,videoOwnerChannelTitle,$THUMBNAIL_FIELDS),contentDetails(videoId,videoPublishedAt))"
private const val SHORT_ID_FIELDS = "items(contentDetails(videoId))"
private const val PLAYLIST_FIELDS = "items(id,snippet(title,description,publishedAt,channelId,channelTitle,$THUMBNAIL_FIELDS),contentDetails(itemCount))"
private const val CHANNEL_FIELDS = "items(id,snippet(title,customUrl,$THUMBNAIL_FIELDS))"

@Serializable
private data class Thumbnail(val url: String)

@Serializable
private data class Thumbnails(val default: Thumbnail? = null, val medium: Thumbnail? = null) {
    val best: String get() = medium?.url ?: default?.url ?: ""
}

@Serializable
private data class ResourceId(val channelId: String = "")

@Serializable
private data class SubscriptionSnippet(val title: String = "", val resourceId: ResourceId = ResourceId(), val thumbnails: Thumbnails = Thumbnails())

@Serializable
private data class SubscriptionItem(val snippet: SubscriptionSnippet = SubscriptionSnippet())

@Serializable
private data class SubscriptionListResponse(val items: List<SubscriptionItem> = emptyList(), val nextPageToken: String? = null)

@Serializable
private data class PlaylistItemSnippet(
    val title: String = "",
    val description: String = "",
    val publishedAt: String = "",
    val videoOwnerChannelId: String? = null,
    val videoOwnerChannelTitle: String? = null,
    val thumbnails: Thumbnails = Thumbnails(),
)

@Serializable
private data class PlaylistItemDetails(val videoId: String, val videoPublishedAt: String? = null)

@Serializable
private data class PlaylistItem(val snippet: PlaylistItemSnippet = PlaylistItemSnippet(), val contentDetails: PlaylistItemDetails)

@Serializable
private data class PlaylistItemsResponse(val items: List<PlaylistItem> = emptyList(), val nextPageToken: String? = null)

@Serializable
private data class VideoSnippet(val liveBroadcastContent: String = "none", val categoryId: String? = null)

@Serializable
private data class VideoContentDetails(val duration: String = "")

@Serializable
private data class LiveStreamingDetails(val actualEndTime: String? = null)

@Serializable
private data class VideoItem(
    val id: String,
    val snippet: VideoSnippet = VideoSnippet(),
    val contentDetails: VideoContentDetails = VideoContentDetails(),
    val liveStreamingDetails: LiveStreamingDetails? = null,
)

@Serializable
private data class VideoListResponse(val items: List<VideoItem> = emptyList())

@Serializable
private data class PlaylistSnippet(
    val title: String = "",
    val description: String = "",
    val publishedAt: String = "",
    val channelId: String? = null,
    val channelTitle: String? = null,
    val thumbnails: Thumbnails = Thumbnails(),
)

@Serializable
private data class PlaylistContentDetails(val itemCount: Int = 0)

@Serializable
private data class PlaylistResource(
    val id: String,
    val snippet: PlaylistSnippet = PlaylistSnippet(),
    val contentDetails: PlaylistContentDetails = PlaylistContentDetails(),
)

@Serializable
private data class PlaylistListResponse(val items: List<PlaylistResource> = emptyList())

@Serializable
private data class ChannelSnippet(val title: String = "", val customUrl: String? = null, val thumbnails: Thumbnails = Thumbnails())

@Serializable
private data class ChannelResource(val id: String, val snippet: ChannelSnippet = ChannelSnippet())

@Serializable
private data class ChannelListResponse(val items: List<ChannelResource>? = null)

private fun ChannelResource.toSummary(): ChannelSummary =
    ChannelSummary(channelId = id, title = decodeHtmlEntities(snippet.title), thumbnail = snippet.thumbnails.best, handle = snippet.customUrl)

/**
 * A finished broadcast (a stream replay or aired premiere) reports
 * liveBroadcastContent "none" but carries an actualEndTime; a plain upload has neither.
 */
private fun VideoItem.liveStatus(): LiveStatus = when (snippet.liveBroadcastContent) {
    "live" -> LiveStatus.LIVE
    "upcoming" -> LiveStatus.UPCOMING
    else -> if (liveStreamingDetails?.actualEndTime != null) LiveStatus.VOD else LiveStatus.NORMAL
}

/** Whether what is held of a video can stand for a new `videos.list` answer: it has a length and is neither live nor upcoming. */
private fun Video.hasSettledDetails(): Boolean =
    (durationSeconds ?: 0) > 0 && (liveStatus == LiveStatus.VOD || liveStatus == LiveStatus.NORMAL)

/** The YouTube Data API v3, as subtube reads it. Every call takes the access token to use. */
class YouTubeClient(
    private val http: OkHttpClient,
    private val baseUrl: HttpUrl = "https://www.googleapis.com/youtube/v3/".toHttpUrl(),
    /** Where answers are decoded, so a caller on the main thread isn't held up. */
    private val compute: CoroutineDispatcher = Dispatchers.Default,
) {
    private val json = Json { ignoreUnknownKeys = true }

    private suspend inline fun <reified Response> get(path: String, params: Map<String, String>, token: String): Response {
        val url = baseUrl.newBuilder().addPathSegments(path).apply {
            params.forEach { (key, value) -> addQueryParameter(key, value) }
        }.build()
        val body = http.googleCall(Request.Builder().url(url).build(), token, GoogleApi.YOUTUBE, "YouTube API /$path")
        return withContext(compute) { json.decodeFromString(body) }
    }

    /** Every channel the account subscribes to, alphabetically. */
    suspend fun fetchSubscriptions(token: String): List<Subscription> {
        val subscriptions = ArrayList<Subscription>()
        var pageToken: String? = null
        do {
            val params = buildMap {
                put("part", "snippet")
                put("mine", "true")
                put("maxResults", "50")
                put("order", "alphabetical")
                put("fields", SUBSCRIPTION_FIELDS)
                pageToken?.let { put("pageToken", it) }
            }
            val data = get<SubscriptionListResponse>("subscriptions", params, token)
            // an entry YouTube sends without its channel can't be listed
            data.items.filter { item -> item.snippet.resourceId.channelId.isNotEmpty() }.mapTo(subscriptions) { item ->
                Subscription(
                    channelId = item.snippet.resourceId.channelId,
                    title = decodeHtmlEntities(item.snippet.title),
                    thumbnail = item.snippet.thumbnails.best,
                )
            }
            pageToken = data.nextPageToken
        } while (pageToken != null)
        return subscriptions
    }

    /** Duration, broadcast kind and category for each video, 50 ids per call (1 quota unit each). */
    suspend fun fetchVideoDetails(videoIds: List<String>, token: String): Map<String, VideoDetails> {
        val details = HashMap<String, VideoDetails>()
        for (batch in videoIds.chunked(50)) {
            val data = get<VideoListResponse>(
                "videos",
                mapOf("part" to "snippet,contentDetails,liveStreamingDetails", "id" to batch.joinToString(","), "fields" to VIDEO_FIELDS),
                token,
            )
            for (item in data.items) {
                details[item.id] = VideoDetails(
                    durationSeconds = parseIsoDuration(item.contentDetails.duration),
                    liveStatus = item.liveStatus(),
                    categoryId = item.snippet.categoryId,
                )
            }
        }
        return details
    }

    /**
     * A channel's newest uploads, each with its duration, broadcast kind and
     * category, and with [judgeShorts] whether it is a Short; without, the
     * Shorts list is not fetched and a video that could be a Short is left
     * unjudged. [probe] asks `/shorts/{id}` directly, for when the Shorts list
     * can't be read. A channel YouTube has no uploads list for has no uploads.
     * A video among [held], by id, keeps the details it has there and is not
     * asked for again, unless it has no length or is live or upcoming.
     */
    suspend fun fetchUploads(
        channelId: String,
        channelTitle: String,
        token: String,
        maxResults: Int = 15,
        probe: (suspend (String) -> Boolean?)? = null,
        judgeShorts: Boolean = true,
        held: Map<String, Video> = emptyMap(),
    ): List<Video> {
        val data = try {
            get<PlaylistItemsResponse>(
                "playlistItems",
                mapOf(
                    "part" to "snippet,contentDetails",
                    "playlistId" to uploadsPlaylistId(channelId),
                    "maxResults" to "$maxResults",
                    "fields" to UPLOAD_FIELDS,
                ),
                token,
            )
        } catch (_: PlaylistNotFoundException) {
            PlaylistItemsResponse()
        }
        val videos = data.items.filter { item -> item.snippet.title !in HIDDEN_TITLES }.map { item ->
            Video(
                videoId = item.contentDetails.videoId,
                channelId = item.snippet.videoOwnerChannelId ?: channelId,
                channelTitle = decodeHtmlEntities(item.snippet.videoOwnerChannelTitle ?: channelTitle),
                title = decodeHtmlEntities(item.snippet.title),
                description = item.snippet.description,
                publishedAt = item.contentDetails.videoPublishedAt ?: item.snippet.publishedAt,
                thumbnail = item.snippet.thumbnails.best,
            )
        }
        val settled = videos.mapNotNull { video -> held[video.videoId]?.takeIf(Video::hasSettledDetails) }.associate { kept ->
            kept.videoId to VideoDetails(kept.durationSeconds ?: 0, kept.liveStatus ?: LiveStatus.NORMAL, kept.categoryId)
        }
        val details = settled + fetchVideoDetails(videos.map(Video::videoId).filter { videoId -> videoId !in settled }, token)
        val detailed = videos.map { video ->
            val detail = details[video.videoId]
            video.copy(
                durationSeconds = detail?.durationSeconds ?: 0,
                liveStatus = detail?.liveStatus ?: LiveStatus.NORMAL,
                categoryId = detail?.categoryId,
            )
        }
        return if (judgeShorts) markShorts(detailed, channelId, token, maxResults, probe) else withoutShortsList(detailed)
    }

    /**
     * Say which of a channel's already fetched uploads are Shorts, from its
     * Shorts list; [maxResults] is the size of the uploads page they came from.
     */
    suspend fun markShorts(
        videos: List<Video>,
        channelId: String,
        token: String,
        maxResults: Int,
        probe: (suspend (String) -> Boolean?)? = null,
    ): List<Video> = classifyShorts(videos, { fetchShortIds(channelId, token, maxResults) }, probe)

    /**
     * A channel's public playlists, newest first by creation time (playlists.list
     * has no order parameter). One page keeps it quota-neutral with the uploads path.
     */
    suspend fun fetchPlaylists(channelId: String, channelTitle: String, token: String, maxResults: Int = 50): List<Playlist> {
        val data = get<PlaylistListResponse>(
            "playlists",
            mapOf("part" to "snippet,contentDetails", "channelId" to channelId, "maxResults" to "$maxResults", "fields" to PLAYLIST_FIELDS),
            token,
        )
        return data.items.map { item ->
            Playlist(
                playlistId = item.id,
                channelId = item.snippet.channelId ?: channelId,
                channelTitle = decodeHtmlEntities(item.snippet.channelTitle ?: channelTitle),
                title = decodeHtmlEntities(item.snippet.title),
                description = item.snippet.description,
                publishedAt = item.snippet.publishedAt,
                thumbnail = item.snippet.thumbnails.best,
                itemCount = item.contentDetails.itemCount,
            )
        }.sortedByDescending(Playlist::publishedAt)
    }

    /**
     * The ids of a channel's newest Shorts: none when YouTube has no Shorts
     * list for it, which is a channel without Shorts, and null when the list
     * couldn't be read, which leaves the verdict to a probe.
     * Every Short among a channel's newest [max] uploads is among its newest [max]
     * Shorts, so this one page judges every video of an uploads page that size.
     *
     * The list can't be read when the request doesn't get through, or when
     * YouTube answers 5xx twice running (it answers 500 `backendError` for the
     * Shorts list of some channels). Only this request is read that way.
     */
    suspend fun fetchShortIds(channelId: String, token: String, max: Int = 50): Set<String>? {
        val playlistId = shortsPlaylistId(channelId)
        suspend fun ask(): Set<String> = get<PlaylistItemsResponse>(
            "playlistItems",
            mapOf("part" to "contentDetails", "playlistId" to playlistId, "maxResults" to "$max", "fields" to SHORT_ID_FIELDS),
            token,
        ).items.mapTo(HashSet()) { item -> item.contentDetails.videoId }
        return try {
            try {
                ask()
            } catch (first: GoogleApiException) {
                if (first.status in SERVER_ERRORS) ask() else throw first
            }
        } catch (_: PlaylistNotFoundException) {
            emptySet()
        } catch (caught: GoogleApiException) {
            if (caught.status in SERVER_ERRORS) {
                logger.log(Level.WARNING, "Shorts list $playlistId answered ${caught.status} twice; not read", caught)
                null
            } else {
                throw caught
            }
        } catch (caught: IOException) {
            logger.log(Level.WARNING, "Shorts list $playlistId wasn't reached; not read", caught)
            null
        }
    }

    /** The signed-in account's own channel: its id keys everything stored for the account. */
    suspend fun fetchMyChannel(token: String): ChannelSummary {
        val data = get<ChannelListResponse>("channels", mapOf("part" to "snippet", "mine" to "true", "fields" to CHANNEL_FIELDS), token)
        return data.items?.firstOrNull()?.toSummary() ?: throw NoYouTubeChannelException()
    }

    /** Look up channels by id, 50 per call (1 quota unit each); ids YouTube doesn't know are left out. */
    suspend fun fetchChannels(channelIds: List<String>, token: String): List<ChannelSummary> {
        val found = ArrayList<ChannelSummary>()
        for (batch in channelIds.distinct().chunked(50)) {
            val data = get<ChannelListResponse>(
                "channels",
                mapOf("part" to "snippet", "id" to batch.joinToString(","), "maxResults" to "50", "fields" to CHANNEL_FIELDS),
                token,
            )
            data.items.orEmpty().mapTo(found) { item -> item.toSummary() }
        }
        return found
    }
}

/** The Google account has no YouTube channel, so there's no account id to key its data by. */
class NoYouTubeChannelException : Exception("This Google account has no YouTube channel.")
