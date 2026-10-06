package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals

class ChannelOrderTest {
    private fun video(channelId: String, day: Int): Video =
        Video("v$channelId$day", channelId, "", "live now", "", "2026-01-%02dT00:00:00Z".format(day), "")

    private fun playlist(channelId: String, day: Int): Playlist =
        Playlist("PL$channelId$day", channelId, "", "", "", "2026-01-%02dT00:00:00Z".format(day), "", itemCount = 1)

    private fun channel(channelId: String): ChannelFilter = defaultFilter(Subscription(channelId, channelId, ""))

    private val items = listOf(video("UCa", 9), video("UCa", 2), video("UCb", 5), playlist("UCc", 8), video("UCd", 10))

    @Test
    fun takesEachChannelsNewestEntryOfEitherKind() {
        assertEquals(
            mapOf(
                "UCa" to "2026-01-09T00:00:00Z",
                "UCb" to "2026-01-05T00:00:00Z",
                "UCc" to "2026-01-08T00:00:00Z",
                "UCd" to "2026-01-10T00:00:00Z",
            ),
            newestFetched(items),
        )
    }

    @Test
    fun aFilterThatHidesTheNewestEntryDoesNotMoveItsChannel() {
        val channels = listOf(
            channel("UCb"),
            channel("UCc").copy(mode = FilterMode.INCLUDE, regex = "nothing matches"),
            channel("UCd").copy(enabled = false),
            channel("UCa").copy(regex = "live"),
            channel("UCe"),
        )
        assertEquals(
            listOf("UCa", "UCc", "UCb", "UCe", "UCd"),
            orderChannels(channels, newestFetched(items)).map(ChannelFilter::channelId),
        )
    }

    @Test
    fun aHeldOrderKeepsItsRowsInPlaceUntilItIsTakenAgain() {
        val channels = listOf(channel("UCa"), channel("UCb"), channel("UCc"), channel("UCd"))
        fun ordered(shown: List<ChannelFilter>): List<String> = orderChannels(shown, newestFetched(items)).map(ChannelFilter::channelId)
        val held = ordered(channels)
        assertEquals(listOf("UCd", "UCa", "UCc", "UCb"), held)

        val edited = channels.map { shown -> if (shown.channelId == "UCa") shown.copy(enabled = false) else shown }
        assertEquals(listOf("UCd", "UCc", "UCb", "UCa"), ordered(edited))
        assertEquals(held, heldOrder(held, ordered(edited)))
        assertEquals(ordered(edited), heldOrder(ordered(edited), ordered(edited)))
    }

    @Test
    fun aHeldOrderDropsChannelsThatAreGoneAndPutsNewOnesLast() {
        assertEquals(listOf("UCc", "UCa", "UCe", "UCb"), heldOrder(held = listOf("UCc", "UCd", "UCa"), ordered = listOf("UCa", "UCe", "UCb", "UCc")))
        assertEquals(listOf("UCb", "UCa"), heldOrder(held = emptyList(), ordered = listOf("UCb", "UCa")))
    }

    @Test
    fun aHeldRowStaysWhenTheChipsStopKeepingItAndANewlyKeptOneGoesLast() {
        val ordered = listOf("UCa", "UCb", "UCc", "UCd")
        val held = listedOrder(ordered, setOf("UCb", "UCd"))
        assertEquals(listOf("UCb", "UCd"), held)
        assertEquals(listOf("UCb", "UCd"), heldOrder(held, ordered, kept = setOf("UCd")))
        assertEquals(listOf("UCb", "UCd", "UCa", "UCc"), heldOrder(held, ordered, kept = setOf("UCa", "UCc")))
        assertEquals(listOf("UCb", "UCd", "UCa", "UCc"), heldOrder(held, ordered, kept = null))
        assertEquals(listOf("UCd"), heldOrder(held, listOf("UCa", "UCd"), kept = emptySet()))
        assertEquals(ordered, listedOrder(ordered, null))
    }
}
