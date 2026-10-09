package cc.hafa.subtube.core

import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient

class PlaylistIdTest {
    @Test
    fun uploadsSwapsTheUcPrefixForUu() {
        assertEquals("UUabcdef12345", uploadsPlaylistId("UCabcdef12345"))
    }

    @Test
    fun shortsSwapsTheUcPrefixForUush() {
        assertEquals("UUSHabcdef12345", shortsPlaylistId("UCabcdef12345"))
    }
}

class ParseIsoDurationTest {
    @Test
    fun parsesHoursMinutesAndSeconds() {
        assertEquals(3723, parseIsoDuration("PT1H2M3S"))
        assertEquals(45, parseIsoDuration("PT45S"))
        assertEquals(180, parseIsoDuration("PT3M"))
        assertEquals(7200, parseIsoDuration("PT2H"))
    }

    @Test
    fun parsesADayComponent() {
        assertEquals(93600, parseIsoDuration("P1DT2H"))
    }

    @Test
    fun parsesAWholeDayDurationWithNoTimePart() {
        assertEquals(86400, parseIsoDuration("P1D"))
        assertEquals(172800, parseIsoDuration("P2D"))
    }

    @Test
    fun liveUpcomingAndUnparseableInputYieldZero() {
        assertEquals(0, parseIsoDuration("P0D"))
        assertEquals(0, parseIsoDuration(""))
        assertEquals(0, parseIsoDuration("garbage"))
    }
}

class FormatDurationTest {
    @Test
    fun underAMinutePadsTheSeconds() {
        assertEquals("0:00", formatDuration(0))
        assertEquals("0:05", formatDuration(5))
        assertEquals("0:59", formatDuration(59))
    }

    @Test
    fun minutesAndSeconds() {
        assertEquals("1:05", formatDuration(65))
        assertEquals("10:00", formatDuration(600))
    }

    @Test
    fun anHourOrMoreSwitchesToHoursMinutesSeconds() {
        assertEquals("1:00:00", formatDuration(3600))
        assertEquals("1:01:01", formatDuration(3661))
        assertEquals("10:00:00", formatDuration(36000))
    }
}

class DecodeHtmlEntitiesTest {
    @Test
    fun decodesNamedAndNumericEntities() {
        assertEquals("Tom & Jerry", decodeHtmlEntities("Tom &amp; Jerry"))
        assertEquals("don't", decodeHtmlEntities("don&#39;t"))
        assertEquals("don't", decodeHtmlEntities("don&#x27;t"))
        assertEquals("&bogus; stays", decodeHtmlEntities("&bogus; stays"))
    }
}

class ShortsListTest {
    private val server = MockWebServer().apply { start() }
    private val youtube = YouTubeClient(OkHttpClient(), server.url("/youtube/v3/"))
    private val backendError = """{"error":{"code":500,"message":"Internal error encountered.","errors":[{"reason":"backendError"}]}}"""

    @AfterTest
    fun stop() {
        server.close()
    }

    private fun fail() {
        server.enqueue(MockResponse.Builder().code(500).body(backendError).build())
    }

    @Test
    fun aShortsListThatAnswers500TwiceIsNotRead() = runTest {
        fail()
        fail()
        assertNull(youtube.fetchShortIds("UCabc", "token"))
        assertEquals(2, server.requestCount)
        assertEquals("UUSHabc", server.takeRequest().url.queryParameter("playlistId"))
    }

    private val notFound = """{"error":{"code":404,"errors":[{"reason":"playlistNotFound"}]}}"""

    @Test
    fun aChannelWithNoShortsListHasNoShortsAndIsNotProbed() = runTest {
        server.enqueue(MockResponse.Builder().code(404).body(notFound).build())
        assertEquals(emptySet(), youtube.fetchShortIds("UCabc", "token"))

        enqueueUploads()
        server.enqueue(MockResponse.Builder().code(404).body(notFound).build())
        val probed = ArrayList<String>()
        val videos = youtube.fetchUploads("UCabc", "Channel", "token", probe = { videoId -> probed.add(videoId) })
        assertEquals(mapOf<String, Boolean?>("clip" to false, "long" to false), videos.associate { video -> video.videoId to video.isShort })
        assertTrue(probed.isEmpty())
    }

    @Test
    fun aShortsListThatCannotBeReadLeavesTheVerdictToTheProbe() = runTest {
        enqueueUploads()
        fail()
        fail()
        val videos = youtube.fetchUploads("UCabc", "Channel", "token", probe = { true })
        assertEquals(mapOf<String, Boolean?>("clip" to true, "long" to false), videos.associate { video -> video.videoId to video.isShort })
    }

    @Test
    fun aChannelWithNoUploadsListHasNoUploads() = runTest {
        server.enqueue(MockResponse.Builder().code(404).body(notFound).build())
        assertEquals(emptyList(), youtube.fetchUploads("UCabc", "Channel", "token"))
        assertEquals(1, server.requestCount)
    }

    @Test
    fun aSubscriptionWithoutThumbnailsIsListedAndOneWithoutAChannelIsLeftOut() = runTest {
        server.enqueue(
            MockResponse.Builder().body(
                """{"items":[{"snippet":{"title":"Bare","resourceId":{"channelId":"UCbare"}}},{"snippet":{"title":"Nowhere"}},{}]}""",
            ).build(),
        )
        assertEquals(listOf(Subscription("UCbare", "Bare", "")), youtube.fetchSubscriptions("token"))
    }

    @Test
    fun aShortsListThatAnswersOnTheRetryIsRead() = runTest {
        fail()
        server.enqueue(MockResponse.Builder().body("""{"items":[{"contentDetails":{"videoId":"short"}}]}""").build())
        assertEquals(setOf("short"), youtube.fetchShortIds("UCabc", "token"))
    }

    @Test
    fun aShortsListRefusedForAnotherReasonStillFails() = runTest {
        server.enqueue(MockResponse.Builder().code(403).body("""{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}""").build())
        assertEquals(403, assertFailsWith<GoogleApiException> { youtube.fetchShortIds("UCabc", "token") }.status)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun theDailyLimitIsItsOwnFailureAndIsNotAskedAgain() = runTest {
        server.enqueue(MockResponse.Builder().code(403).body("""{"error":{"errors":[{"reason":"quotaExceeded"}]}}""").build())
        assertFailsWith<DailyLimitException> { youtube.fetchShortIds("UCabc", "token") }
        assertEquals(1, server.requestCount)
    }

    @Test
    fun onlyA403NamingTheDailyQuotaIsTheDailyLimit() {
        assertTrue(isDailyLimit(403, """{"error":{"errors":[{"reason":"quotaExceeded"}]}}"""))
        assertTrue(isDailyLimit(403, """{"error":{"errors":[{"reason":"other"},{"reason":"dailyLimitExceeded"}]}}"""))
        assertFalse(isDailyLimit(403, """{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}"""))
        assertFalse(isDailyLimit(429, """{"error":{"errors":[{"reason":"quotaExceeded"}]}}"""))
        assertFalse(isDailyLimit(403, "quotaExceeded"))
        assertFalse(isDailyLimit(403, """{"error":{"errors":"quotaExceeded"}}"""))
    }

    private fun enqueueUploads() {
        server.enqueue(
            MockResponse.Builder().body(
                """{"items":[{"snippet":{"title":"Clip","publishedAt":"2026-01-01T00:00:00Z"},"contentDetails":{"videoId":"clip"}},""" +
                    """{"snippet":{"title":"Long","publishedAt":"2026-01-02T00:00:00Z"},"contentDetails":{"videoId":"long"}}]}""",
            ).build(),
        )
        server.enqueue(
            MockResponse.Builder().body(
                """{"items":[{"id":"clip","contentDetails":{"duration":"PT30S"}},{"id":"long","contentDetails":{"duration":"PT10M"}}]}""",
            ).build(),
        )
    }

    @Test
    fun uploadsWithoutShortsVerdictsSkipTheShortsList() = runTest {
        enqueueUploads()
        val videos = youtube.fetchUploads("UCabc", "Channel", "token", judgeShorts = false)
        assertEquals(mapOf("clip" to null, "long" to false), videos.associate { video -> video.videoId to video.isShort })
        assertEquals(2, server.requestCount)

        server.enqueue(MockResponse.Builder().body("""{"items":[{"contentDetails":{"videoId":"clip"}}]}""").build())
        val marked = youtube.markShorts(videos, "UCabc", "token", 50)
        assertEquals(mapOf<String, Boolean?>("clip" to true, "long" to false), marked.associate { video -> video.videoId to video.isShort })
        assertEquals(3, server.requestCount)
    }

    @Test
    fun videoDetailsKeepTheCategoryAndDoNotAskForTopics() = runTest {
        server.enqueue(
            MockResponse.Builder().body(
                """{"items":[{"id":"v1","snippet":{"categoryId":"10"},"contentDetails":{"duration":"PT1M"}},""" +
                    """{"id":"v2","contentDetails":{"duration":"PT2M"}}]}""",
            ).build(),
        )
        val details = youtube.fetchVideoDetails(listOf("v1", "v2"), "token")
        assertEquals("10", details.getValue("v1").categoryId)
        assertNull(details.getValue("v2").categoryId)
        assertEquals("snippet,contentDetails,liveStreamingDetails", server.takeRequest().url.queryParameter("part"))
    }

    @Test
    fun everyRequestAsksOnlyForTheFieldsItReads() = runTest {
        val thumbnails = "thumbnails(default(url),medium(url))"
        val empty = MockResponse.Builder().body("""{"items":[]}""").build()
        server.enqueue(empty)
        youtube.fetchSubscriptions("token")
        assertEquals("nextPageToken,items(snippet(title,resourceId(channelId),$thumbnails))", server.takeRequest().url.queryParameter("fields"))

        enqueueUploads()
        server.enqueue(empty)
        youtube.fetchUploads("UCabc", "Channel", "token")
        assertEquals(
            "items(snippet(title,description,publishedAt,videoOwnerChannelId,videoOwnerChannelTitle,$thumbnails),contentDetails(videoId,videoPublishedAt))",
            server.takeRequest().url.queryParameter("fields"),
        )
        assertEquals(
            "items(id,snippet(liveBroadcastContent,categoryId),contentDetails(duration),liveStreamingDetails(actualEndTime))",
            server.takeRequest().url.queryParameter("fields"),
        )
        assertEquals("items(contentDetails(videoId))", server.takeRequest().url.queryParameter("fields"))

        server.enqueue(empty)
        youtube.fetchPlaylists("UCabc", "Channel", "token")
        assertEquals(
            "items(id,snippet(title,description,publishedAt,channelId,channelTitle,$thumbnails),contentDetails(itemCount))",
            server.takeRequest().url.queryParameter("fields"),
        )

        server.enqueue(MockResponse.Builder().body("""{"items":[{"id":"UCme","snippet":{"title":"Me"}}]}""").build())
        youtube.fetchMyChannel("token")
        assertEquals("items(id,snippet(title,customUrl,$thumbnails))", server.takeRequest().url.queryParameter("fields"))
    }

    @Test
    fun videoDetailsAreAskedOnlyForVideosNotHeldOrHeldUnsettled() = runTest {
        fun item(videoId: String): String =
            """{"snippet":{"title":"$videoId","publishedAt":"2026-01-01T00:00:00Z"},"contentDetails":{"videoId":"$videoId"}}"""
        val ids = listOf("settled", "replay", "live", "upcoming", "unknown", "new")
        server.enqueue(MockResponse.Builder().body("""{"items":[${ids.joinToString(",", transform = ::item)}]}""").build())
        server.enqueue(
            MockResponse.Builder().body(
                """{"items":[{"id":"live","contentDetails":{"duration":"PT1H"},"liveStreamingDetails":{"actualEndTime":"2026-01-01T01:00:00Z"}},""" +
                    """{"id":"upcoming","snippet":{"liveBroadcastContent":"live"}},{"id":"unknown","contentDetails":{"duration":"PT5M"}},""" +
                    """{"id":"new","snippet":{"categoryId":"10"},"contentDetails":{"duration":"PT4M"}}]}""",
            ).build(),
        )
        val held = listOf(
            video("settled", durationSeconds = 600).copy(categoryId = "27"),
            video("replay", durationSeconds = 7200, liveStatus = LiveStatus.VOD),
            video("live", durationSeconds = 0, liveStatus = LiveStatus.LIVE),
            video("upcoming", durationSeconds = 0, liveStatus = LiveStatus.UPCOMING),
            video("unknown", durationSeconds = 0),
        ).associateBy(Video::videoId)
        val videos = youtube.fetchUploads("UCabc", "Channel", "token", judgeShorts = false, held = held).associateBy(Video::videoId)

        server.takeRequest()
        assertEquals("live,upcoming,unknown,new", server.takeRequest().url.queryParameter("id"))
        assertEquals(Triple(600, LiveStatus.NORMAL, "27"), videos.getValue("settled").let { video -> Triple(video.durationSeconds, video.liveStatus, video.categoryId) })
        assertEquals(7200 to LiveStatus.VOD, videos.getValue("replay").let { video -> video.durationSeconds to video.liveStatus })
        assertEquals(3600 to LiveStatus.VOD, videos.getValue("live").let { video -> video.durationSeconds to video.liveStatus })
        assertEquals(LiveStatus.LIVE, videos.getValue("upcoming").liveStatus)
        assertEquals(300, videos.getValue("unknown").durationSeconds)
        assertEquals(240 to "10", videos.getValue("new").let { video -> video.durationSeconds to video.categoryId })
    }

    @Test
    fun noVideoDetailsAreAskedWhenEveryVideoIsHeld() = runTest {
        enqueueUploads()
        val held = listOf(video("clip", durationSeconds = 30), video("long", durationSeconds = 600)).associateBy(Video::videoId)
        val videos = youtube.fetchUploads("UCabc", "Channel", "token", judgeShorts = false, held = held)
        assertEquals(listOf(30, 600), videos.map(Video::durationSeconds))
        assertEquals(1, server.requestCount)
    }

    @Test
    fun anUploadsListThatAnswers500IsStillAnError() = runTest {
        fail()
        assertEquals(500, assertFailsWith<GoogleApiException> { youtube.fetchUploads("UCabc", "Channel", "token") }.status)
        assertEquals(1, server.requestCount)
    }
}
