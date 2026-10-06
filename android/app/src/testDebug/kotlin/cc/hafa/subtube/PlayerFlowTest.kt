package cc.hafa.subtube

import androidx.compose.ui.geometry.Rect
import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.PlayerPlace
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.ui.Screen
import cc.hafa.subtube.ui.SubtubeViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The feed's list on the test screen, in pixels. */
private val LIST = Rect(0f, 250f, 1078f, 2190f)

/** A card's thumbnail wholly inside [LIST]: 379dp by 213dp at this density. */
private val THUMBNAIL = Rect(42f, 300f, 1037f, 860f)

/** The one player's moves between a card, the corner and the pages, on the demo data with no screen drawn. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h914dp-420dpi")
class PlayerFlowTest {
    private fun model(screen: String = "feed", autoplay: Boolean = false): SubtubeViewModel {
        val model = SubtubeViewModel(ApplicationProvider.getApplicationContext())
        model.showDemo(demoData(screen = screen, settings = Settings(autoplay = autoplay)))
        return model
    }

    private fun SubtubeViewModel.playFirst(): FeedItem {
        val item = (if (backStack.last() == Screen.Feed) feed else channelFeed).items.first()
        play(item)
        return item
    }

    private val SubtubeViewModel.place: PlayerPlace?
        get() = playing?.place

    @Test
    fun aPressedCardPlaysInItsCard() {
        val model = model()
        val item = model.playFirst()
        assertEquals(PlayerPlace.CARD, model.place)
        assertTrue(model.playsInCard(item.id, null))
        assertFalse(model.playsInCard(item.id, item.channelId))
        assertEquals(model.feed.items, model.playing?.queue?.items)
    }

    @Test
    fun aCardStaysWhileHalfOfItShowsAndMinimizesBelowThat() {
        val model = model()
        val item = model.playFirst()
        model.playerViewMoved(null, LIST)
        model.playerSlotMoved(item.id, THUMBNAIL)
        model.cardShown(model.cardRequest!!)
        assertEquals(PlayerPlace.CARD, model.place)
        model.playerSlotMoved(item.id, THUMBNAIL.translate(0f, -300f))
        assertEquals(PlayerPlace.CARD, model.place)
        model.playerSlotMoved(item.id, THUMBNAIL.translate(0f, -340f))
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        assertNull(model.playerSlot)
        // it never comes back by itself
        model.playerSlotMoved(item.id, THUMBNAIL)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun aCardLeavingItsListsRowsMinimizes() {
        val model = model()
        val item = model.playFirst()
        model.playerViewMoved(null, LIST)
        model.playerSlotMoved(item.id, THUMBNAIL)
        model.cardShown(model.cardRequest!!)
        model.playerSlotGone("another")
        assertEquals(PlayerPlace.CARD, model.place)
        model.playerSlotGone(item.id)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun aPressedCardMostlyOffTheScreenKeepsThePlayerWhileItsListBringsItIntoView() {
        val model = model()
        val item = model.playFirst()
        assertEquals(item.id, model.cardRequest?.id)
        model.playerViewMoved(null, LIST)
        model.playerSlotMoved(item.id, THUMBNAIL.translate(0f, -340f))
        assertEquals(PlayerPlace.CARD, model.place)
        model.playerSlotMoved(item.id, THUMBNAIL)
        model.cardShown(model.cardRequest!!)
        assertEquals(PlayerPlace.CARD, model.place)
    }

    @Test
    fun aCardsPlayerStaysItsCardsThroughFullScreen() {
        val model = model()
        val item = model.playFirst()
        model.playerViewMoved(null, LIST)
        model.playerSlotMoved(item.id, THUMBNAIL)
        model.cardShown(model.cardRequest!!)
        model.playerFullscreen(true)
        model.playerSlotMoved(item.id, THUMBNAIL.translate(0f, -340f))
        model.playerSlotGone(item.id)
        assertEquals(PlayerPlace.CARD, model.place)
    }

    @Test
    fun theEndLeavesTheMinimizedPlayerOnItsVideoWithNothingNext() {
        val model = model()
        val item = model.playFirst()
        model.minimizePlayer()
        model.playbackEnded(item.id)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        assertEquals(item.id, model.playing?.item?.id)
        assertNull(model.cardRequest)
        model.closePlayer()
        assertNull(model.playing)
    }

    @Test
    fun changingPageMinimizesAndThePlayerOutlivesEveryPage() {
        val model = model()
        val item = model.playFirst()
        model.selectTab(Screen.Channels)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        model.selectTab(Screen.Settings)
        model.showChannel("UCOne")
        model.pop()
        model.selectTab(Screen.Feed)
        assertEquals(item.id, model.playing?.item?.id)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun openingAChannelMinimizesAndBackDoesNotBringItBack() {
        val model = model()
        model.playFirst()
        model.showChannel("UCOne")
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        model.pop()
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun expandReturnsToTheFeedAndAsksItsListForTheCard() {
        val model = model()
        val item = model.playFirst()
        model.selectTab(Screen.Channels)
        model.expandPlayer()
        assertEquals(listOf<Screen>(Screen.Feed), model.backStack.toList())
        assertEquals(PlayerPlace.CARD, model.place)
        val request = model.cardRequest
        assertEquals(item.id, request?.id)
        assertNull(request?.page)
        // while the list scrolls, a card half out of view keeps the player
        model.playerViewMoved(null, LIST)
        model.playerSlotMoved(item.id, THUMBNAIL.translate(0f, -400f))
        assertEquals(PlayerPlace.CARD, model.place)
        model.playerSlotMoved(item.id, THUMBNAIL)
        model.cardShown(request!!)
        assertEquals(PlayerPlace.CARD, model.place)
        assertNull(model.cardRequest)
    }

    @Test
    fun expandMinimizesAgainWhenTheListCouldNotShowTheCard() {
        val model = model()
        model.playFirst()
        model.selectTab(Screen.Settings)
        model.expandPlayer()
        model.cardShown(model.cardRequest!!)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun expandReturnsToTheChannelPageTheVideoWasStartedOn() {
        val model = model(screen = "channel")
        val item = model.playFirst()
        assertEquals("UCOne", model.playing?.page)
        model.selectTab(Screen.Feed)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        model.expandPlayer()
        assertEquals(Screen.ChannelPage("UCOne"), model.backStack.last())
        assertEquals(PlayerPlace.CARD, model.place)
        assertEquals("UCOne", model.cardRequest?.page)
        assertTrue(model.playsInCard(item.id, "UCOne"))
    }

    @Test
    fun expandStaysMinimizedWhenThePageNoLongerListsTheCard() {
        val model = model()
        val item = model.playFirst()
        model.selectTab(Screen.Channels)
        model.updateFilter(model.channels.getValue(item.channelId).copy(enabled = false))
        model.expandPlayer()
        assertEquals(listOf<Screen>(Screen.Feed), model.backStack.toList())
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        assertNull(model.cardRequest)
    }

    @Test
    fun aCardLeavingTheListMinimizes() {
        val model = model()
        val item = model.playFirst()
        model.updateFilter(model.channels.getValue(item.channelId).copy(enabled = false))
        assertEquals(item.id, model.playing?.item?.id)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
    }

    @Test
    fun theEndClosesAPlayerWithAutoPlayOff() {
        val model = model()
        val item = model.playFirst()
        model.playbackEnded(item.id)
        assertNull(model.playing)
    }

    @Test
    fun theEndPlaysTheNextCardAndAsksTheListForIt() {
        val model = model(autoplay = true)
        val first = model.playFirst()
        val second = model.feed.items[1]
        model.playerSlotMoved(first.id, THUMBNAIL)
        model.playbackEnded("another")
        assertEquals(first.id, model.playing?.item?.id)
        model.playbackEnded(first.id)
        assertEquals(second.id, model.playing?.item?.id)
        assertEquals(PlayerPlace.CARD, model.place)
        assertEquals(second.id, model.cardRequest?.id)
        assertNull(model.playerSlot)
    }

    @Test
    fun theEndPlaysTheNextOfTheListItStartedFromMinimizedOnAnotherPage() {
        val model = model(autoplay = true)
        val first = model.playFirst()
        val second = model.feed.items[1]
        model.selectTab(Screen.Settings)
        model.playbackEnded(first.id)
        assertEquals(second.id, model.playing?.item?.id)
        assertEquals(PlayerPlace.MINIMIZED, model.place)
        assertNull(model.cardRequest)
    }

    @Test
    fun closeRemovesThePlayerAndPressingAnotherCardReplacesIt() {
        val model = model()
        model.playFirst()
        model.minimizePlayer()
        val other = model.feed.items[2]
        model.play(other)
        assertEquals(other.id, model.playing?.item?.id)
        assertEquals(PlayerPlace.CARD, model.place)
        model.closePlayer()
        assertNull(model.playing)
    }

    @Test
    fun onlyTheMinimizedPlayerTakesTheFrameAndItGoesWhenThePlayerMoves() {
        val model = model()
        model.framePlayer(true)
        assertFalse(model.playerFramed)
        model.playFirst()
        model.framePlayer(true)
        assertFalse(model.playerFramed)
        model.minimizePlayer()
        model.framePlayer(true)
        assertTrue(model.playerFramed)
        model.expandPlayer()
        assertEquals(PlayerPlace.CARD, model.place)
        assertFalse(model.playerFramed)
    }

    @Test
    fun sheetsAndDialogsAreCounted() {
        val model = model()
        model.coverPlayer(true)
        model.coverPlayer(true)
        model.coverPlayer(false)
        assertEquals(1, model.playerCovers)
        model.coverPlayer(false)
        model.coverPlayer(false)
        assertEquals(0, model.playerCovers)
        assertNotNull(model.backStack.lastOrNull())
    }
}
