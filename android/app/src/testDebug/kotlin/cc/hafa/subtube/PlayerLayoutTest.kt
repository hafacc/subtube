package cc.hafa.subtube

import android.content.Intent
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.performSemanticsAction
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.PlayerPlace
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.ui.Screen
import cc.hafa.subtube.ui.SubtubeViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The test screen's pixels to a dp. */
private const val DENSITY = 2.625f

/** The player and the feed's real list, laid out in the real activity on the demo feed. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h914dp-420dpi")
class PlayerLayoutTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: SubtubeApp = ApplicationProvider.getApplicationContext()
    private lateinit var model: SubtubeViewModel

    private fun onFeed(autoplay: Boolean = false, check: () -> Unit) {
        ActivityScenario.launch<MainActivity>(Intent(app, MainActivity::class.java)).use { scenario ->
            scenario.onActivity { activity ->
                model = ViewModelProvider(activity)[SubtubeViewModel::class.java]
                model.showDemo(demoData(settings = Settings(autoplay = autoplay)))
            }
            compose.waitForIdle()
            check()
        }
    }

    private fun scrollListBy(dp: Float) {
        compose.onNode(hasScrollToIndexAction()).performSemanticsAction(SemanticsActions.ScrollBy) { scroll -> scroll(0f, dp * DENSITY) }
        compose.waitForIdle()
    }

    @Test
    fun aCardPartlyUnderTheListsEdgeReportsItsWholeBoxAndKeepsThePlayerUntilHalfIsHidden() = onFeed {
        model.play(model.feed.items.first())
        compose.waitForIdle()
        val whole = model.playerSlot?.box
        assertNotNull(whole)
        assertEquals(PlayerPlace.CARD, model.playing?.place)
        scrollListBy(100f)
        val cut = model.playerSlot?.box
        val list = model.playerView
        assertEquals(PlayerPlace.CARD, model.playing?.place)
        assertEquals(whole!!.height, cut!!.height, 1f)
        assertTrue(cut.top < list!!.top)
        assertTrue(cut.bottom > list.top)
        // the first scroll also folds the top bar away; this one hides most of the thumbnail
        scrollListBy(150f)
        assertEquals(PlayerPlace.MINIMIZED, model.playing?.place)
    }

    @Test
    fun aScrollToTheNextCardThatIsCutShortStillEndsTheRequest() = onFeed(autoplay = true) {
        val playing = model.feed.items[1]
        // the next unwatched card is far enough down that its list has to scroll to it
        model.feed.items.subList(2, 5).forEach { between -> model.setWatched(between.id, true) }
        model.play(playing)
        compose.waitForIdle()
        assertEquals(PlayerPlace.CARD, model.playing?.place)
        compose.mainClock.autoAdvance = false
        model.playbackEnded(playing.id)
        repeat(3) {
            compose.waitForIdle()
            compose.mainClock.advanceTimeByFrame()
        }
        // the next card is being scrolled into view
        assertNotNull(model.cardRequest)
        // the Feed tab pressed on the feed scrolls to the top, which stops that scroll
        model.selectTab(Screen.Feed)
        compose.mainClock.autoAdvance = true
        compose.waitForIdle()
        assertNull(model.cardRequest)
        scrollListBy(2000f)
        assertEquals(PlayerPlace.MINIMIZED, model.playing?.place)
    }
}
