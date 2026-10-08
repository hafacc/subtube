package cc.hafa.subtube

import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.FeedSort
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.core.TimeChip
import cc.hafa.subtube.core.WatchedMode
import cc.hafa.subtube.core.sortFeed
import cc.hafa.subtube.ui.SubtubeViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The "Sort and filter" menu's sort chips and its button's selected state, on the demo data with no screen drawn. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h914dp-420dpi")
class FilterMenuTest {
    private fun model(settings: Settings = Settings(), watchedMode: WatchedMode = WatchedMode.UNWATCHED): SubtubeViewModel {
        val model = SubtubeViewModel(ApplicationProvider.getApplicationContext())
        model.showDemo(demoData(settings = settings, watchedMode = watchedMode))
        return model
    }

    private val SubtubeViewModel.sort: FeedSort
        get() = settings.feedSort

    @Test
    fun theSelectedSortChipTurnsRoundAndBack() {
        val model = model()
        assertEquals(listOf(FeedSort.NEWEST, FeedSort.SHORTEST, FeedSort.TITLE, FeedSort.RANDOM), model.sortChips)
        model.pressSortChip(0)
        assertEquals(FeedSort.OLDEST, model.sort)
        assertEquals(FeedSort.OLDEST, model.sortChips[0])
        assertEquals(sortFeed(model.feed.items, FeedSort.OLDEST), model.feed.items)
        model.pressSortChip(0)
        assertEquals(FeedSort.NEWEST, model.sort)
        model.pressSortChip(2)
        model.pressSortChip(2)
        assertEquals(FeedSort.TITLE_REVERSED, model.sort)
    }

    @Test
    fun anUnselectedSortChipIsChosenInTheDirectionItLastShowed() {
        val model = model()
        model.pressSortChip(1)
        assertEquals(FeedSort.SHORTEST, model.sort)
        model.pressSortChip(1)
        assertEquals(FeedSort.LONGEST, model.sort)
        model.pressSortChip(0)
        assertEquals(FeedSort.NEWEST, model.sort)
        assertEquals(FeedSort.LONGEST, model.sortChips[1])
        model.pressSortChip(1)
        assertEquals(FeedSort.LONGEST, model.sort)
        assertEquals(FeedSort.NEWEST, model.sortChips[0])
    }

    @Test
    fun aSavedReversedSortShowsOnItsChip() {
        val model = model(Settings(feedSort = FeedSort.TITLE_REVERSED))
        assertEquals(listOf(FeedSort.NEWEST, FeedSort.SHORTEST, FeedSort.TITLE_REVERSED, FeedSort.RANDOM), model.sortChips)
    }

    @Test
    fun randomPressedWhileSelectedShufflesAgain() {
        val model = model()
        val before = model.shuffleSeed
        model.pressSortChip(3)
        assertEquals(FeedSort.RANDOM, model.sort)
        assertEquals("choosing Random keeps the load's seed", before, model.shuffleSeed)
        assertEquals(sortFeed(model.feed.items, FeedSort.RANDOM, before), model.feed.items)
        model.pressSortChip(3)
        assertEquals(FeedSort.RANDOM, model.sort)
        assertNotEquals(before, model.shuffleSeed)
        assertEquals(sortFeed(model.feed.items, FeedSort.RANDOM, model.shuffleSeed), model.feed.items)
        assertEquals(model.feed.items.map(FeedItem::id).toSet().size, model.feed.items.size)
    }

    @Test
    fun aDemoAskedToStartOnAllStartsOnUnwatched() {
        assertEquals(WatchedMode.UNWATCHED, model(watchedMode = WatchedMode.ALL).watchedMode)
        assertEquals(WatchedMode.WATCHED, model(watchedMode = WatchedMode.WATCHED).watchedMode)
    }

    @Test
    fun theButtonIsSelectedOffTheStartingTimeOrWatchedMode() {
        val model = model()
        assertFalse(model.menuNarrows)
        model.setAutoplay(true)
        model.pressSortChip(1)
        assertFalse("auto-play and the sort don't count", model.menuNarrows)
        model.setTimeChip(TimeChip.WEEK)
        assertTrue(model.menuNarrows)
        model.setTimeChip(TimeChip.NONE)
        assertFalse(model.menuNarrows)
        model.chooseWatchedMode(WatchedMode.WATCHED)
        assertTrue(model.menuNarrows)
        model.chooseWatchedMode(WatchedMode.UNWATCHED)
        assertFalse(model.menuNarrows)
    }
}
