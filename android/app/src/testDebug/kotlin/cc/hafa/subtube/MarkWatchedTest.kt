package cc.hafa.subtube

import android.content.Intent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.ui.SubtubeViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Pressing a card's progress bar, or swiping the card sideways, marks its entry watched or unwatched, on the demo feed in the real activity. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h914dp-420dpi")
class MarkWatchedTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: SubtubeApp = ApplicationProvider.getApplicationContext()
    private lateinit var model: SubtubeViewModel

    private fun onFeed(check: () -> Unit) {
        ActivityScenario.launch<MainActivity>(Intent(app, MainActivity::class.java)).use { scenario ->
            scenario.onActivity { activity ->
                model = ViewModelProvider(activity)[SubtubeViewModel::class.java]
                model.showDemo(demoData())
            }
            compose.waitForIdle()
            check()
        }
    }

    /** The first card's title, which a swipe is started on. */
    private fun firstTitle(): SemanticsNodeInteraction = compose.onAllNodesWithText(model.feed.items.first().title)[0]

    /** Drags [this] sideways by [share] of its width (negative for towards the start) and lets go. */
    private fun SemanticsNodeInteraction.swipeBy(share: Float) {
        performTouchInput {
            down(center)
            repeat(10) { moveBy(Offset(width * share / 10, 0f)) }
            up()
        }
        compose.waitForIdle()
    }

    @Test
    fun swipingACardPastAQuarterMarksWatchedAndTheCardStaysWithoutPlaying() = onFeed {
        val first = model.feed.items.first()
        val listed = model.feed.items
        firstTitle().swipeBy(0.5f)
        assertTrue(first.id in model.watched)
        assertEquals(1.0, model.bars[first.id])
        assertEquals(listed, model.feed.items)
        assertNull(model.playing)
        firstTitle().assertIsDisplayed()
    }

    @Test
    fun swipingTheOtherWayMarksTooAndASecondSwipeUnmarks() = onFeed {
        val first = model.feed.items.first()
        firstTitle().swipeBy(-0.5f)
        assertTrue(first.id in model.watched)
        firstTitle().swipeBy(-0.5f)
        assertFalse(first.id in model.watched)
        firstTitle().swipeBy(0.5f)
        assertTrue(first.id in model.watched)
    }

    @Test
    fun aSwipeShortOfAQuarterChangesNothing() = onFeed {
        val first = model.feed.items.first()
        firstTitle().swipeBy(0.15f)
        firstTitle().swipeBy(-0.15f)
        assertFalse(first.id in model.watched)
        assertNull(model.playing)
    }

    @Test
    fun aSwipeTakenBackBeforeLettingGoChangesNothing() = onFeed {
        val first = model.feed.items.first()
        firstTitle().performTouchInput {
            down(center)
            repeat(10) { moveBy(Offset(width * 0.05f, 0f)) }
            repeat(10) { moveBy(Offset(-width * 0.04f, 0f)) }
            up()
        }
        compose.waitForIdle()
        assertFalse(first.id in model.watched)
    }

    @Test
    fun aDragDownTheListMarksNothing() = onFeed {
        val first = model.feed.items.first()
        firstTitle().performTouchInput {
            down(center)
            repeat(10) { moveBy(Offset(width * 0.05f, -height * 2f)) }
            up()
        }
        compose.waitForIdle()
        assertFalse(first.id in model.watched)
    }

    @Test
    fun theCardOfWhatPlaysInTheCornerCannotBeSwiped() = onFeed {
        val first = model.feed.items.first()
        model.play(first)
        model.minimizePlayer()
        compose.waitForIdle()
        firstTitle().swipeBy(0.5f)
        assertFalse(first.id in model.watched)
    }

    @Test
    fun theCardOffersTheMarkAsAnActionToScreenReaders() = onFeed {
        val first = model.feed.items.first()
        val picture = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.CustomActions) and hasClickAction())[0]
        val action = picture.fetchSemanticsNode().config[SemanticsActions.CustomActions].single()
        assertEquals(app.getString(R.string.mark_watched), action.label)
        compose.runOnUiThread { action.action() }
        compose.waitForIdle()
        assertTrue(first.id in model.watched)
    }

    @Test
    fun pressingTheBarMarksWatchedAndTheCardStaysWithoutPlaying() = onFeed {
        val first = model.feed.items.first()
        val listed = model.feed.items
        val counted = model.unwatchedByChannel[first.channelId]
        compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched))[0].performClick()
        compose.waitForIdle()
        assertTrue(first.id in model.watched)
        assertEquals(1.0, model.bars[first.id])
        assertEquals(listed, model.feed.items)
        assertNull(model.playing)
        assertEquals((counted ?: 0) - 1, model.unwatchedByChannel[first.channelId] ?: 0)
    }

    @Test
    fun pressingTheBarAgainUnmarksAndForgetsThePosition() = onFeed {
        val first = model.feed.items.first()
        compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched))[0].performClick()
        compose.onNodeWithContentDescription(app.getString(R.string.mark_unwatched)).performClick()
        compose.waitForIdle()
        assertFalse(first.id in model.watched)
        assertNull(model.bars[first.id])
        compose.onAllNodesWithContentDescription(app.getString(R.string.mark_unwatched)).assertCountEquals(0)
    }

    @Test
    fun theStripReachesOverThePictureAndOverTheTextAndNeitherPlays() = onFeed {
        val first = model.feed.items.first()
        val strip = compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched))[0]
        strip.performTouchInput { click(Offset(centerX, 2f)) }
        compose.waitForIdle()
        assertTrue(first.id in model.watched)
        compose.onNodeWithContentDescription(app.getString(R.string.mark_unwatched)).performTouchInput { click(Offset(centerX, height - 2f)) }
        compose.waitForIdle()
        assertFalse(first.id in model.watched)
        assertNull(model.playing)
    }

    @Test
    fun pressingTheTitleNeitherPlaysNorMarks() = onFeed {
        val first = model.feed.items.first()
        compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched))[0].performTouchInput { click(Offset(centerX, height + 14.dp.toPx())) }
        firstTitle().performClick()
        compose.waitForIdle()
        assertFalse(first.id in model.watched)
        assertNull(model.playing)
    }

    @Test
    fun theCardOfWhatPlaysInTheCornerHasNoBarToPress() = onFeed {
        val before = compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched)).fetchSemanticsNodes().size
        model.play(model.feed.items.first())
        model.minimizePlayer()
        compose.waitForIdle()
        val after = compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched)).fetchSemanticsNodes().size
        assertEquals(before - 1, after)
    }

    @Test
    fun aCardHoldingThePlayerHasNoBarToPress() = onFeed {
        val before = compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched)).fetchSemanticsNodes().size
        model.play(model.feed.items.first())
        compose.waitForIdle()
        val after = compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched)).fetchSemanticsNodes().size
        assertEquals(before - 1, after)
    }
}
