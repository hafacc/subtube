package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/** A video this close to its end, in seconds, is watched. */
const val FINISHED_WITHIN_SECONDS: Int = 10

/** A watched entry's position in seconds; null when it has none: only a number that isn't negative counts. */
fun entryPosition(entry: JsonObject?): Double? {
    val position = (entry?.get("position") as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.doubleOrNull
    return position?.takeIf { seconds -> seconds >= 0 }
}

/**
 * Whether a video is watched (shared/fixtures/watch-progress.json): marked so,
 * or played into the last [FINISHED_WITHIN_SECONDS] of a length longer than
 * that. [entry] is its merged watched entry and [durationSeconds] its length,
 * 0 when unknown.
 */
fun isWatchedEntry(entry: JsonObject?, durationSeconds: Double = 0.0): Boolean {
    val position = entryPosition(entry)
    return (entry != null && entryWatched(entry)) ||
        (position != null && durationSeconds > FINISHED_WITHIN_SECONDS && position >= durationSeconds - FINISHED_WITHIN_SECONDS)
}

/** Where a video starts when opened, in seconds: its position unless it is watched. */
fun resumePosition(entry: JsonObject?, durationSeconds: Double = 0.0): Double =
    if (isWatchedEntry(entry, durationSeconds)) 0.0 else entryPosition(entry) ?: 0.0

/** How full an entry's progress bar is, from 0 to 1; null for no bar. A playlist, which has no length, shows its entry's progress. */
fun progressFraction(entry: JsonObject?, durationSeconds: Double = 0.0): Double? =
    if (isWatchedEntry(entry, durationSeconds)) {
        1.0
    } else if (durationSeconds > 0) {
        entryPosition(entry)?.let { position -> minOf(1.0, position / durationSeconds) }
    } else {
        entryProgress(entry)
    }

/** How far through a playlist a watched entry is, from 0 to 1; null when it has none: only a number in that range counts. */
fun entryProgress(entry: JsonObject?): Double? {
    val progress = (entry?.get("progress") as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.doubleOrNull
    return progress?.takeIf { fraction -> fraction in 0.0..1.0 }
}

/** Where in a playlist its player is: at [video], [progress] of the way through the playlist, from 0 to 1 ([playlistProgress]). */
data class PlaylistPlace(val video: String, val progress: Double)

/**
 * How far through a playlist its player is, from 0 to 1, counting every video
 * as equally long (shared/fixtures/watch-progress.json): [position] of
 * [durationSeconds] into the video at [index], from 0, of [count].
 */
fun playlistProgress(index: Int, count: Int, position: Double, durationSeconds: Double): Double =
    if (count <= 0) {
        0.0
    } else {
        val part = if (durationSeconds > 0) (position / durationSeconds).coerceIn(0.0, 1.0) else 0.0
        ((index + part) / count).coerceIn(0.0, 1.0)
    }

/** Where a playlist starts when opened: at its video at [index], counted from 0, [position] seconds in. */
data class PlaylistStart(val index: Int, val position: Double)

/** The video of a playlist that was playing, by a watched entry; null when it has none: only a string counts. */
fun entryVideo(entry: JsonObject?): String? = (entry?.get("video") as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content

/**
 * Where a playlist starts when opened (shared/fixtures/watch-progress.json):
 * at the video that was playing, where it was left, when [videos], the ids
 * its player loaded, still has it; otherwise, and when it is watched, at its
 * first video.
 */
fun playlistStart(entry: JsonObject?, videos: List<String>): PlaylistStart {
    val video = entryVideo(entry)
    val index = if (entry != null && !entryWatched(entry) && video != null) videos.indexOf(video) else -1
    return if (index < 0) PlaylistStart(0, 0.0) else PlaylistStart(index, entryPosition(entry) ?: 0.0)
}
