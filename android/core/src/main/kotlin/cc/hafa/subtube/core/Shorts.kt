package cc.hafa.subtube.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/** Shorts are capped at 3 minutes, so a longer video can't be one and needs no verdict. */
const val SHORTS_MAX_SECONDS: Int = 180

/** How many `/shorts/{id}` probes run at once. */
private const val PROBE_CONCURRENCY = 6

/** Whether a video could be a Short at all, and so is worth classifying. */
fun isShortsCandidate(item: FeedItem): Boolean {
    val duration = (item as? Video)?.durationSeconds ?: 0
    return duration in 1..SHORTS_MAX_SECONDS
}

/**
 * One channel's uploads when its Shorts list isn't read, because nothing
 * filters on Shorts: a video that can't be a Short is marked not one, and a
 * candidate is left unjudged.
 */
fun withoutShortsList(videos: List<Video>): List<Video> =
    videos.map { video -> video.copy(isShort = if (isShortsCandidate(video)) null else false) }

/**
 * Set [Video.isShort] on one channel's uploads. The verdict comes from the
 * channel's Shorts list ([loadShortIds], null when it couldn't be read). When
 * it can't be, every channel would look Short-free, so a platform that can
 * ask `/shorts/{id}` directly ([probe]) does so instead; an inconclusive
 * answer leaves the verdict unknown, which a channel filtering on Shorts
 * holds back.
 */
suspend fun classifyShorts(
    videos: List<Video>,
    loadShortIds: suspend () -> Set<String>?,
    probe: (suspend (String) -> Boolean?)? = null,
): List<Video> {
    val candidates = videos.filter(::isShortsCandidate)
    val shortIds = if (candidates.isEmpty()) emptySet() else loadShortIds()
    return if (shortIds != null || probe == null) {
        videos.map { video -> video.copy(isShort = isShortsCandidate(video) && shortIds?.contains(video.videoId) == true) }
    } else {
        val verdicts = HashMap<String, Boolean?>()
        for (batch in candidates.chunked(PROBE_CONCURRENCY)) {
            val answers = coroutineScope {
                batch.map { video -> async { probeOrNull(probe, video.videoId) } }.awaitAll()
            }
            batch.zip(answers).forEach { (video, answer) -> verdicts[video.videoId] = answer }
        }
        videos.map { video -> video.copy(isShort = if (isShortsCandidate(video)) verdicts[video.videoId] else false) }
    }
}

private suspend fun probeOrNull(probe: suspend (String) -> Boolean?, videoId: String): Boolean? =
    try {
        probe(videoId)
    } catch (caught: CancellationException) {
        throw caught
    } catch (_: Exception) {
        null
    }
