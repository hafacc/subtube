package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals

class UnwatchedPassingTest {
    private val hidesTrailers = channel(regex = "\\btrailer\\b", mode = FilterMode.EXCLUDE)

    @Test
    fun picksTheChannelsUnwatchedEntriesThatPassItsFilter() {
        val items = listOf(
            video(videoId = "new"),
            video(videoId = "seen"),
            video(videoId = "filtered", title = "Official Trailer"),
            video(videoId = "elsewhere").copy(channelId = "UC2"),
            playlist(),
            video(videoId = "new"),
        )
        assertEquals(listOf("new"), unwatchedPassing(hidesTrailers, items, setOf("seen")))
    }

    @Test
    fun picksPlaylistsForAChannelThatShowsPlaylists() {
        val showsPlaylists = channel().copy(contentMode = ContentMode.PLAYLISTS)
        val items = listOf(video(videoId = "upload"), playlist())
        assertEquals(listOf("PL1"), unwatchedPassing(showsPlaylists, items, emptySet()))
        assertEquals(emptyList(), unwatchedPassing(showsPlaylists, items, setOf("PL1")))
    }

    @Test
    fun picksNothingWhenEverythingIsWatchedOrFiltered() {
        val items = listOf(video(videoId = "seen"), video(videoId = "filtered", title = "Trailer 2"))
        assertEquals(emptyList(), unwatchedPassing(hidesTrailers, items, setOf("seen")))
    }
}
