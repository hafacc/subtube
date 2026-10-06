package cc.hafa.subtube.core

import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.coroutines.executeAsync

private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")

/** How long a probe may take before its answer counts as inconclusive. */
private const val PROBE_TIMEOUT_SECONDS = 5L

/** A desktop browser's User-Agent; YouTube answers other clients differently. */
private const val BROWSER_USER_AGENT =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

/** Pre-answers the EU cookie consent page, which would otherwise redirect every probe. */
private const val CONSENT_COOKIE = "SOCS=CAI; CONSENT=YES+"

/**
 * Asks `youtube.com/shorts/{id}` whether a video is a Short: YouTube serves a
 * Short there with 200 and redirects anything else to /watch. Only a fallback
 * for when a channel's Shorts list isn't served; relies on undocumented behavior.
 */
class ShortsProbe(
    http: OkHttpClient,
    private val base: HttpUrl = "https://www.youtube.com/shorts/".toHttpUrl(),
) {
    private val client = http.newBuilder()
        .followRedirects(false)
        .followSslRedirects(false)
        .callTimeout(PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()

    /** True for a Short, false for anything else, null when the answer was inconclusive. */
    suspend fun isShort(videoId: String): Boolean? {
        if (!VIDEO_ID.matches(videoId)) {
            return null
        }
        val request = Request.Builder()
            .url(base.newBuilder().addPathSegment(videoId).build())
            .header("User-Agent", BROWSER_USER_AGENT)
            .header("Cookie", CONSENT_COOKIE)
            .build()
        return try {
            client.newCall(request).executeAsync().use { response ->
                when (response.code) {
                    200 -> true
                    in 300..399 -> false
                    else -> null
                }
            }
        } catch (_: IOException) {
            null
        }
    }
}
