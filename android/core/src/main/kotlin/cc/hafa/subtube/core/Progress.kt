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

/** How full a video's progress bar is, from 0 to 1; null for no bar. */
fun progressFraction(entry: JsonObject?, durationSeconds: Double = 0.0): Double? {
    val position = entryPosition(entry)
    return if (isWatchedEntry(entry, durationSeconds)) {
        1.0
    } else if (position == null || durationSeconds <= 0) {
        null
    } else {
        minOf(1.0, position / durationSeconds)
    }
}
