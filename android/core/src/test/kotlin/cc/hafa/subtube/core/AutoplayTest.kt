package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NextUnwatchedTest {
    private val shown = listOf("a", "b", "c", "d").map { id -> video(videoId = id, title = id) }

    private fun next(endedId: String, vararg watched: String): String? = nextUnwatched(shown, endedId, watched.toSet())?.id

    @Test
    fun isTheEntryAfterTheOneThatEndedInTheOrderShown() {
        assertEquals("b", next("a", "a"))
    }

    @Test
    fun skipsWatchedEntries() {
        assertEquals("d", next("a", "a", "b", "c"))
    }

    @Test
    fun neverGoesBackToAnEarlierEntry() {
        assertNull(next("c", "c", "d"))
    }

    @Test
    fun stopsAtTheEndOfTheList() {
        assertNull(next("d", "d"))
    }

    @Test
    fun stopsWhenTheEndedEntryIsNotInTheList() {
        assertNull(next("elsewhere"))
    }

    @Test
    fun aPlaylistCanBeNext() {
        val list = shown.take(1) + playlist()
        assertEquals("PL1", nextUnwatched(list, "a", setOf("a"))?.id)
    }
}
