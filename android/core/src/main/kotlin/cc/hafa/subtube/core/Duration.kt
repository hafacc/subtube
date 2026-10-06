package cc.hafa.subtube.core

import java.util.Locale

/** Format a length in seconds as M:SS or H:MM:SS. */
fun formatDuration(totalSeconds: Int): String {
    val hours = totalSeconds / 3600
    val minutes = totalSeconds % 3600 / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(Locale.ROOT, hours, minutes, seconds)
    } else {
        "%d:%02d".format(Locale.ROOT, minutes, seconds)
    }
}

private val ISO_DURATION = Regex("""^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$""")

/**
 * Parse an ISO 8601 duration (e.g. "PT1H2M3S", "P1DT4M") to seconds. Live and
 * upcoming videos report "P0D", which yields 0, as does anything unparseable.
 */
fun parseIsoDuration(iso: String): Int {
    val match = ISO_DURATION.matchEntire(iso) ?: return 0
    val (days, hours, minutes, seconds) = match.destructured.toList().map { part -> part.toIntOrNull() ?: 0 }
    return days * 86400 + hours * 3600 + minutes * 60 + seconds
}
