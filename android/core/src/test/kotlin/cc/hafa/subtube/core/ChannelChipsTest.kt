package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ChannelChipsTest {
    private val now = 1_769_904_000_000

    private fun video(id: String, channelId: String, title: String = "", categoryId: String? = null, publishedAt: String = "2026-01-31T12:00:00Z"): Video =
        Video(id, channelId, "", title, "", publishedAt, "", categoryId = categoryId)

    private fun playlist(id: String, channelId: String): Playlist = Playlist(id, channelId, "", "", "", "2026-01-31T12:00:00Z", "", itemCount = 1)

    private fun channel(channelId: String): ChannelFilter = defaultFilter(Subscription(channelId, channelId, ""))

    @Test
    fun onlyOnChannelsEntriesOfTheirKindThatPassTheirFilterAreLookedAt() {
        val channels = listOf(
            channel("UCa").copy(regex = phrasesToPattern(listOf("keep")), mode = FilterMode.INCLUDE),
            channel("UCb").copy(contentMode = ContentMode.PLAYLISTS),
            channel("UCoff").copy(enabled = false),
        )
        val items = listOf(
            video("a1", "UCa", title = "keep this"),
            video("a2", "UCa", title = "drop this"),
            playlist("PLa", "UCa"),
            video("b1", "UCb"),
            playlist("PLb", "UCb"),
            video("off1", "UCoff"),
            video("gone1", "UCgone"),
        )
        assertEquals(listOf("a1", "PLb"), passingItems(channels, items).map(FeedItem::id))
    }

    @Test
    fun noSpanAndNoKnownTopicKeepsEveryChannel() {
        val items = listOf(video("a1", "UCa", categoryId = "10"))
        assertNull(chipKeptChannels(items, TimeChip.NONE, emptyList(), now))
        assertNull(chipKeptChannels(items, TimeChip.NONE, listOf("99"), now))
        assertEquals(emptySet(), chipKeptChannels(items, TimeChip.NONE, listOf("20"), now))
        assertEquals(setOf("UCa"), chipKeptChannels(items, TimeChip.DAY, emptyList(), now))
    }

    @Test
    fun oneEntryMustMeetBothTheSpanAndTheTopic() {
        val items = listOf(
            video("a1", "UCa", categoryId = "10", publishedAt = "2026-01-01T00:00:00Z"),
            video("a2", "UCa", categoryId = "20"),
            video("b1", "UCb", categoryId = "10"),
        )
        assertEquals(setOf("UCb"), chipKeptChannels(items, TimeChip.DAY, listOf("10"), now))
    }
}
