package cc.hafa.subtube

import android.content.Intent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.ChannelSort
import cc.hafa.subtube.core.FeedSort
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.core.TimeChip
import cc.hafa.subtube.core.WatchedMode
import cc.hafa.subtube.ui.DemoData
import cc.hafa.subtube.ui.SetUpStep
import cc.hafa.subtube.ui.SubtubeViewModel
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureScreenRoboImage
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** How far into the shimmer the loading pictures are taken. */
private const val LOADING_SHOT_AT_MS = 2000L

/** A Pixel 8a's screen, before the night and density qualifiers. */
private const val PHONE = "w411dp-h914dp"

/** A screen too narrow for a 356dp player beside its margins. */
private const val NARROW_PHONE = "w360dp-h740dp"

/**
 * Draws every screen on the demo data into PNGs, on this machine, with no
 * device: `./gradlew :app:testDebugUnitTest -Pscreenshots=<folder>` (default
 * `app/build/screenshots`).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "$PHONE-420dpi")
class ScreenshotsTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: SubtubeApp = ApplicationProvider.getApplicationContext()
    private val folder = File(System.getProperty("subtube.screenshots") ?: "build/screenshots")

    // the view model of the activity a capture is showing
    private lateinit var model: SubtubeViewModel

    /** Show [data] in the real activity on a [screen] of that size, do [act] on it, and save the screen as [name]. */
    @OptIn(ExperimentalRoborazziApi::class)
    private fun capture(name: String, data: DemoData, dark: Boolean = false, screen: String = PHONE, act: () -> Unit = {}) {
        RuntimeEnvironment.setQualifiers(screen + (if (dark) "-night" else "-notnight") + "-420dpi")
        ActivityScenario.launch<MainActivity>(Intent(app, MainActivity::class.java)).use { scenario ->
            scenario.onActivity { activity ->
                model = ViewModelProvider(activity)[SubtubeViewModel::class.java]
                model.showDemo(data)
            }
            if (data.loading) {
                // the shimmer never comes to rest: stop the clock part-way through a sweep instead of waiting
                compose.mainClock.autoAdvance = false
                compose.mainClock.advanceTimeBy(LOADING_SHOT_AT_MS)
            } else {
                compose.waitForIdle()
                act()
                compose.waitForIdle()
            }
            folder.mkdirs()
            captureScreenRoboImage(File(folder, "$name.png").path)
        }
    }

    // a chip of a chip row, whose name the title above the row also shows while it is selected
    private fun chip(name: String): SemanticsNodeInteraction = compose.onNode(hasText(name) and hasClickAction())

    // drags the first card sideways by a share of its width and keeps the finger down
    private fun holdFirstCardSwiped(share: Float) {
        compose.onAllNodesWithText(model.feed.items.first().title)[0].performTouchInput {
            down(center)
            repeat(10) { moveBy(Offset(width * share / 10, 0f)) }
        }
    }

    private fun openMenu() {
        compose.onNodeWithContentDescription(app.getString(R.string.sort_and_filter)).performClick()
    }

    private fun openFilters() {
        compose.onNodeWithContentDescription(app.getString(R.string.filters)).performClick()
    }

    @Test
    fun setUp() {
        val names = listOf("intro", "sign-in", "channels", "shorts", "start", "done")
        SetUpStep.entries.forEachIndexed { index, step ->
            capture("%02d-setup-%s".format(index + 1, names[index]), demoData(screen = "setup", step = step))
        }
        capture("17-dark-setup-intro", demoData(screen = "setup"), dark = true)
        capture("24-dark-setup-start", demoData(screen = "setup", step = SetUpStep.START), dark = true)
        // no load runs on this screen in the app; this is the only place the logo's loading animation can be seen
        capture("53-setup-intro-loading", demoData(screen = "setup", loading = DemoLoading.RELOAD))
    }

    @Test
    fun feed() {
        val chosen = Settings(autoplay = true, feedSort = FeedSort.SHORTEST, topicChips = listOf("26"))
        capture("08-feed", demoData())
        capture("09-feed-with-chips-selected", demoData(settings = chosen))
        capture("10-feed-nothing-for-selection", demoData(settings = Settings(topicChips = listOf("10"))))
        capture("18-dark-feed", demoData(settings = chosen), dark = true)
        capture("31-feed-chips-scrolled-to-topics", demoData(settings = chosen)) {
            chip("Howto & Style").performScrollTo()
        }
        capture("49-feed-menu", demoData(), act = ::openMenu)
        capture("50-feed-menu-with-choices", demoData(watchedMode = WatchedMode.WATCHED, settings = Settings(autoplay = true, feedSort = FeedSort.SHORTEST, timeChip = TimeChip.WEEK))) {
            openMenu()
            compose.onNodeWithContentDescription("Sort: Shortest").performClick()
        }
        capture("51-dark-feed-menu", demoData(), dark = true, act = ::openMenu)
        capture("52-feed-menu-narrow-screen", demoData(), screen = NARROW_PHONE, act = ::openMenu)
        capture("46-feed-card-marked-watched", demoData()) {
            compose.onAllNodesWithContentDescription(app.getString(R.string.mark_watched))[0].performClick()
        }
        capture("47-feed-card-swiped", demoData()) { holdFirstCardSwiped(0.4f) }
        capture("48-dark-feed-card-swiped-back", demoData(watchedMode = WatchedMode.WATCHED), dark = true) { holdFirstCardSwiped(-0.4f) }
        capture("26-feed-short", demoData(settings = Settings(topicChips = listOf("27"))))
        capture("27-dark-feed-short", demoData(settings = Settings(topicChips = listOf("27"))), dark = true)
    }

    @Test
    fun loading() {
        capture("21-feed-first-load", demoData(loading = DemoLoading.FIRST))
        capture("22-feed-reload", demoData(loading = DemoLoading.RELOAD))
        capture("23-dark-feed-reload", demoData(loading = DemoLoading.RELOAD), dark = true)
    }

    @Test
    fun channels() {
        capture("11-channels", demoData(screen = "channels"))
        capture("25-dark-channels-by-unwatched", demoData(screen = "channels", settings = Settings(channelSort = ChannelSort.UNWATCHED)), dark = true)
        val chosen = Settings(channelTimeChip = TimeChip.MONTH, channelTopicChips = listOf("26"))
        capture("28-channels-time-and-topic-selected", demoData(screen = "channels", settings = chosen))
        capture("29-channels-nothing-for-selection", demoData(screen = "channels", settings = Settings(channelTopicChips = listOf("10"))))
        capture("30-dark-channels-time-and-topic-selected", demoData(screen = "channels", settings = chosen), dark = true)
    }

    @Test
    fun groups() {
        val group = Settings(channelGroupChips = listOf("Woodworking"))
        val groupAndTopic = Settings(channelGroupChips = listOf("Woodworking"), channelTopicChips = listOf("26"))
        val feedGroup = Settings(groupChips = listOf("Woodworking"))
        capture("32-channels-group-selected", demoData(screen = "channels", settings = group))
        capture("33-channels-group-and-topic-selected", demoData(screen = "channels", settings = groupAndTopic))
        capture("34-feed-group-selected", demoData(settings = feedGroup)) {
            chip("Woodworking").performScrollTo()
        }
        capture("35-group-editor-new", demoData(screen = "channels")) {
            compose.onNodeWithContentDescription(app.getString(R.string.new_group)).performClick()
        }
        capture("36-group-editor-existing", demoData(screen = "channels", settings = group)) {
            compose.onNodeWithContentDescription(app.getString(R.string.edit_group)).performClick()
        }
        capture("37-dark-channels-group-selected", demoData(screen = "channels", settings = group), dark = true)
        capture("38-dark-group-editor-existing", demoData(screen = "channels", settings = group), dark = true) {
            compose.onNodeWithContentDescription(app.getString(R.string.edit_group)).performClick()
        }
    }

    @Test
    fun channelPage() {
        capture("12-channel-page", demoData(screen = "channel"))
        capture("19-dark-channel-page", demoData(screen = "channel"), dark = true)
    }

    @Test
    fun filterSheet() {
        capture("13-filter-sheet", demoData(screen = "channel"), act = ::openFilters)
        capture("20-dark-filter-sheet", demoData(screen = "channel"), dark = true, act = ::openFilters)
    }

    @Test
    fun player() {
        capture("14-feed-card-playing", demoData(screen = "player"))
        capture("40-player-minimized", demoData(screen = "minimized"))
        capture("41-player-minimized-with-frame", demoData(screen = "minimized")) { model.framePlayer(true) }
        capture("42-dark-player-minimized-with-frame", demoData(screen = "minimized"), dark = true) { model.framePlayer(true) }
        capture("43-player-minimized-over-channels", demoData(screen = "minimized")) {
            compose.onNodeWithText(app.getString(R.string.channels)).performClick()
        }
        capture("44-player-minimized-narrow-screen", demoData(screen = "minimized"), screen = NARROW_PHONE)
        capture("45-player-in-card-narrow-screen", demoData(screen = "player"), screen = NARROW_PHONE)
    }

    @Test
    fun settings() {
        capture("15-settings", demoData(screen = "settings"))
        capture("16-settings-delete-confirmation", demoData(screen = "settings")) {
            compose.onNodeWithText(app.getString(R.string.delete_profile)).performClick()
        }
    }
}
