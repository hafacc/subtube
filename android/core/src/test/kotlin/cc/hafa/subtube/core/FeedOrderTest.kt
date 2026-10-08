package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals

private fun dated(id: String, day: Int): Video = video(videoId = id, title = id, publishedAt = "2026-01-%02dT00:00:00Z".format(day))

class ByNewestTest {
    @Test
    fun sortsNewestFirstAndTiesByIdAscending() {
        val items = listOf(dated("a", 5), dated("c", 9), dated("b", 9), dated("z", 1))
        assertEquals(listOf("b", "c", "a", "z"), items.sortedWith(byNewest).map(FeedItem::id))
    }
}

class WatchedModeTest {
    private val items = listOf(dated("old", 1), dated("seen", 2), dated("justSeen", 3))
    private val watched = setOf("seen", "justSeen")

    private fun listed(mode: WatchedMode, vararg staying: String): List<String> =
        modeFiltered(items, mode, watched, staying.toSet()).map(FeedItem::id)

    @Test
    fun listsOneSideOrBoth() {
        assertEquals(listOf("old"), listed(WatchedMode.UNWATCHED))
        assertEquals(listOf("seen", "justSeen"), listed(WatchedMode.WATCHED))
        assertEquals(listOf("old", "seen", "justSeen"), listed(WatchedMode.ALL))
    }

    @Test
    fun keepsWhatChangedSidesOnScreen() {
        assertEquals(listOf("old", "justSeen"), listed(WatchedMode.UNWATCHED, "justSeen"))
        assertEquals(listOf("old", "seen", "justSeen"), listed(WatchedMode.WATCHED, "old"))
    }

    @Test
    fun autoplayDoesNotMoveOnAmongWatchedOnly() {
        assertEquals(listOf(true, false, true), WatchedMode.entries.map(::autoplayAdvances))
    }

    @Test
    fun anEmptyListIsBlamedOnTheSelectionUnlessNothingIsSelected() {
        assertEquals(false, emptiedBySelection(WatchedMode.UNWATCHED, TimeChip.NONE, emptyList()))
        assertEquals(false, emptiedBySelection(WatchedMode.UNWATCHED, TimeChip.NONE, listOf("999")))
        assertEquals(true, emptiedBySelection(WatchedMode.ALL, TimeChip.NONE, emptyList()))
        assertEquals(true, emptiedBySelection(WatchedMode.UNWATCHED, TimeChip.DAY, emptyList()))
        assertEquals(true, emptiedBySelection(WatchedMode.UNWATCHED, TimeChip.NONE, listOf("10")))
    }
}

class SortChipsTest {
    @Test
    fun everyOrderIsOnOneChip() {
        assertEquals(FeedSort.entries, FEED_SORT_CHIPS.flatten())
        assertEquals(listOf(0, 0, 1, 1, 2, 2, 3), FeedSort.entries.map(::sortChipOf))
    }

    @Test
    fun theSelectedChipTurnsRoundAndRandomStays() {
        assertEquals(FeedSort.OLDEST, sortAfterPress(0, FeedSort.NEWEST, emptyMap()))
        assertEquals(FeedSort.NEWEST, sortAfterPress(0, FeedSort.OLDEST, emptyMap()))
        assertEquals(FeedSort.TITLE, sortAfterPress(2, FeedSort.TITLE_REVERSED, emptyMap()))
        assertEquals(FeedSort.RANDOM, sortAfterPress(3, FeedSort.RANDOM, emptyMap()))
    }

    @Test
    fun anotherChipIsChosenInTheDirectionItLastShowed() {
        assertEquals(FeedSort.SHORTEST, sortAfterPress(1, FeedSort.OLDEST, emptyMap()))
        assertEquals(FeedSort.LONGEST, sortAfterPress(1, FeedSort.OLDEST, mapOf(1 to FeedSort.LONGEST)))
        assertEquals(
            listOf(FeedSort.OLDEST, FeedSort.LONGEST, FeedSort.TITLE, FeedSort.RANDOM),
            shownSorts(FeedSort.OLDEST, mapOf(0 to FeedSort.NEWEST, 1 to FeedSort.LONGEST)),
        )
    }

    @Test
    fun theMenuNarrowsOffTheStartingTimeOrWatchedMode() {
        assertEquals(false, menuNarrows(WatchedMode.UNWATCHED, TimeChip.NONE))
        assertEquals(true, menuNarrows(WatchedMode.ALL, TimeChip.NONE))
        assertEquals(true, menuNarrows(WatchedMode.WATCHED, TimeChip.NONE))
        assertEquals(true, menuNarrows(WatchedMode.UNWATCHED, TimeChip.WEEK))
    }
}
