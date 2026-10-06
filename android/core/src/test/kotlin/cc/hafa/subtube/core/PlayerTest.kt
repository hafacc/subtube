package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlayerTest {
    private val list = listOf("a", "b", "c", "d").map { id -> video(videoId = id, title = id) }

    private fun item(id: String): FeedItem = list.first { item -> item.id == id }

    private fun inCard(id: String, page: String? = null): Playing = played(item(id), page, list, WatchedMode.UNWATCHED)

    @Test
    fun aPressedCardPlaysInItWithThePagesListAsItWas() {
        val playing = played(item("b"), "UC1", list, WatchedMode.ALL)
        assertEquals(PlayerPlace.CARD, playing.place)
        assertEquals("UC1", playing.page)
        assertEquals(PlayQueue(list, WatchedMode.ALL), playing.queue)
    }

    @Test
    fun leavingThePageOrTheCardLeavingTheListMinimizes() {
        val playing = inCard("b")
        assertEquals(playing, afterPageChange(playing, null, list))
        assertEquals(PlayerPlace.MINIMIZED, afterPageChange(playing, "UC1", list).place)
        assertEquals(PlayerPlace.MINIMIZED, afterPageChange(playing, null, list - item("b")).place)
    }

    @Test
    fun aMinimizedPlayerStaysMinimizedWhateverThePage() {
        val playing = minimized(inCard("b"))
        assertEquals(playing, afterPageChange(playing, null, list))
        assertEquals(playing, afterPageChange(playing, "UC1", emptyList()))
    }

    @Test
    fun minimizingKeepsTheEntryThePageAndTheList() {
        val playing = inCard("b", page = "UC1")
        assertEquals(playing.copy(place = PlayerPlace.MINIMIZED), minimized(playing))
    }

    @Test
    fun expandGoesBackIntoTheCardOnThePageItStartedOn() {
        val playing = minimized(inCard("b", page = "UC1"))
        assertEquals(PlayerPlace.CARD, expanded(playing, "UC1", list).place)
    }

    @Test
    fun expandStaysMinimizedOnAnotherPageOrWhenThePageNoLongerListsTheCard() {
        val playing = minimized(inCard("b", page = "UC1"))
        assertEquals(playing, expanded(playing, null, list))
        assertEquals(playing, expanded(playing, "UC1", list - item("b")))
    }

    @Test
    fun theEndPlaysTheNextOfTheListItStartedFromInTheNextCard() {
        val next = afterEnd(inCard("a"), setOf("a", "b"), autoplay = true, page = null, shown = list)
        assertEquals("c", next?.item?.id)
        assertEquals(PlayerPlace.CARD, next?.place)
    }

    @Test
    fun theEndPlaysMinimizedWhenTheNextCardIsNotOnThePageShowing() {
        val elsewhere = afterEnd(inCard("a"), setOf("a"), autoplay = true, page = "UC1", shown = list)
        assertEquals("b" to PlayerPlace.MINIMIZED, elsewhere?.let { playing -> playing.item.id to playing.place })
        val gone = afterEnd(inCard("a"), setOf("a"), autoplay = true, page = null, shown = list - item("b"))
        assertEquals("b" to PlayerPlace.MINIMIZED, gone?.let { playing -> playing.item.id to playing.place })
    }

    @Test
    fun aMinimizedPlayerPlaysTheNextMinimizedFromItsOwnList() {
        val next = afterEnd(minimized(inCard("a")), setOf("a"), autoplay = true, page = "UC1", shown = emptyList())
        assertEquals("b" to PlayerPlace.MINIMIZED, next?.let { playing -> playing.item.id to playing.place })
        assertEquals(list, next?.queue?.items)
    }

    @Test
    fun withNothingNextACardsPlayerClosesAndTheMinimizedOneStays() {
        assertNull(afterEnd(inCard("a"), setOf("a"), autoplay = false, page = null, shown = list))
        val inCorner = minimized(inCard("d"))
        assertEquals(inCorner, afterEnd(inCorner, setOf("d"), autoplay = true, page = null, shown = list))
        assertEquals(minimized(inCard("a")), afterEnd(minimized(inCard("a")), setOf("a"), autoplay = false, page = null, shown = list))
        val startedInWatched = played(item("a"), null, list, WatchedMode.WATCHED)
        assertNull(afterEnd(startedInWatched, setOf("a"), autoplay = true, page = null, shown = list))
    }

    @Test
    fun aCardThatCannotHoldThePlayerGivesItToTheCorner() {
        val playing = inCard("b")
        assertEquals(playing, afterCardMeasured(playing, "b", holds = true))
        assertEquals(PlayerPlace.MINIMIZED, afterCardMeasured(playing, "b", holds = false).place)
        assertEquals(playing, afterCardMeasured(playing, "c", holds = false))
        assertEquals(minimized(playing), afterCardMeasured(minimized(playing), "b", holds = true))
    }

    @Test
    fun theEndOfAPlaylistOrAVideoNotInItsListCloses() {
        val stranger = inCard("a").copy(item = video(videoId = "z"))
        assertNull(afterEnd(stranger, setOf("z"), autoplay = true, page = null, shown = list))
    }

    @Test
    fun visibleFractionIsTheShareOfTheBoxInsideTheView() {
        val view = ScreenBox(0f, 100f, 400f, 600f)
        assertEquals(1f, visibleFraction(ScreenBox(0f, 100f, 400f, 200f), view))
        assertEquals(0.5f, visibleFraction(ScreenBox(0f, 0f, 400f, 200f), view))
        assertEquals(0f, visibleFraction(ScreenBox(0f, 700f, 400f, 200f), view))
        assertEquals(0f, visibleFraction(ScreenBox(0f, 100f, 0f, 200f), view))
    }

    @Test
    fun aCardHoldsThePlayerWhenHalfOfItShowsAndItIsBigEnough() {
        val view = ScreenBox(0f, 100f, 400f, 600f)
        assertTrue(cardHolds(ScreenBox(16f, 0f, 368f, 200f), view))
        assertFalse(cardHolds(ScreenBox(16f, -1f, 368f, 200f), view))
        assertFalse(cardHolds(ScreenBox(16f, 200f, 368f, 199f), view))
        assertFalse(cardHolds(ScreenBox(16f, 200f, 199f, 200f), view))
    }
}
