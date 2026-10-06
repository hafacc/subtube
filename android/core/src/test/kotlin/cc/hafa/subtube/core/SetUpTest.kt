package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SetUpTest {
    private val day = 86_400_000L
    private val now = 10 * day

    private fun video(id: String, channelId: String, publishedAt: String): Video =
        Video(videoId = id, channelId = channelId, channelTitle = channelId, title = id, description = "", publishedAt = publishedAt, thumbnail = "")

    private fun channel(id: String, shorts: ShortsFilter?): ChannelFilter =
        ChannelFilter(channelId = id, title = id, thumbnail = "", enabled = true, regex = "", mode = FilterMode.INCLUDE, shortsFilter = shorts)

    @Test
    fun theMostCommonShortsChoiceWinsAndATieIsShow() {
        assertEquals(ShortsFilter.ALL, commonShortsFilter(emptyList()))
        assertEquals(
            ShortsFilter.NORMAL,
            commonShortsFilter(listOf(channel("a", ShortsFilter.NORMAL), channel("b", ShortsFilter.NORMAL), channel("c", null))),
        )
        assertEquals(ShortsFilter.ALL, commonShortsFilter(listOf(channel("a", ShortsFilter.NORMAL), channel("b", ShortsFilter.SHORTS))))
    }

    @Test
    fun allTimeOrNoChannelLeavesNothingWaiting() {
        assertNull(pendingStart(StartFrom.ALL, now, listOf("a")))
        assertNull(pendingStart(StartFrom.DAY, now, emptyList()))
    }

    @Test
    fun aFetchedChannelIsMarkedAndAFailedOneKeepsWaiting() {
        val pending = pendingStart(StartFrom.DAY, now, listOf("a", "b"))!!
        val old = video("old", "a", "1970-01-08T00:00:00Z")
        val fresh = video("fresh", "a", "1970-01-10T12:00:00Z")
        val first = applyStart(pending, listOf("a", "later"), listOf(old, fresh, video("other", "later", "1970-01-01T00:00:00Z")))
        assertEquals(listOf("old"), first.marks)
        assertEquals(listOf("b"), first.pending?.channels)
        // counted back from when setup finished, however much later the channel loads
        val second = applyStart(first.pending, listOf("b"), listOf(video("b-old", "b", "1970-01-09T12:00:00Z"), video("b-new", "b", "1970-01-10T12:00:00Z")))
        assertEquals(listOf("b-old"), second.marks)
        assertNull(second.pending)
    }

    @Test
    fun whatWaitsIsReadBackAsWritten() {
        val pending = PendingStart(StartFrom.WEEK, now, listOf("a", "b"))
        assertEquals(pending, decodePendingStart(encodePendingStart(pending)))
        assertNull(decodePendingStart(null))
        assertNull(decodePendingStart("day"))
        assertNull(decodePendingStart("""{"start":"all time","cutoff":1,"channels":[]}"""))
    }

    @Test
    fun aSearchIgnoresCaseOnly() {
        assertTrue(matchesSearch("Wood Working", "  wood w "))
        assertTrue(matchesSearch("Anything", "  "))
        assertFalse(matchesSearch("Café", "cafe"))
    }
}
