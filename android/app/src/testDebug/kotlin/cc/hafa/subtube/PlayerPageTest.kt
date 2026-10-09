package cc.hafa.subtube

import android.os.Looper
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.Playback
import cc.hafa.subtube.core.PlaybackFeed
import cc.hafa.subtube.core.PlayerState
import cc.hafa.subtube.core.ProgressUpload
import cc.hafa.subtube.ui.PlayerBridge
import cc.hafa.subtube.ui.PlayerPage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** What a played video's saves were, and nothing else of a feed. */
private class Saves : PlaybackFeed {
    val uploads: MutableList<ProgressUpload> = mutableListOf()

    override fun recordProgress(id: String, position: Double, playerDuration: Double, ended: Boolean, upload: ProgressUpload) {
        uploads.add(upload)
    }

    override fun setWatched(id: String, watched: Boolean) = Unit

    override fun findItem(id: String): FeedItem? = null
}

/** The player page's reports and what may play: the token, a sheet over the player, and the app off the screen. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlayerPageTest {
    private val saves = Saves()
    private val page = PlayerPage()
    private var pauses = 0
    private var resumes = 0
    private var ended = 0

    private fun load(): String {
        page.pause = { pauses += 1 }
        page.resume = { resumes += 1 }
        return page.load(Playback("video", isPlaylist = false, saves) { ended += 1 })
    }

    private fun send(message: String) {
        PlayerBridge(page).postMessage(message)
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun aReportWithAnotherPagesTokenIsDropped() {
        val first = load()
        val second = load()
        assertFalse(first == second)
        send("""{"token":"$first","kind":"failed"}""")
        send("""{"token":"","kind":"failed"}""")
        assertFalse(page.failed)
        send("""{"token":"$first","kind":"state","code":0,"time":90,"duration":90,"last":true}""")
        assertEquals(0, ended)
        send("""{"token":"$second","kind":"state","code":0,"time":90,"duration":90,"last":true}""")
        assertEquals(1, ended)
        send("""{"token":"$second","kind":"failed"}""")
        assertTrue(page.failed)
    }

    @Test
    fun aVideoThePlayerCannotPlayEndsAndNothingIsSaved() {
        val token = load()
        send("""{"token":"other","kind":"error","code":150}""")
        assertEquals(0, ended)
        send("""{"token":"$token","kind":"error","code":150}""")
        assertEquals(1, ended)
        assertTrue(saves.uploads.isEmpty())
    }

    @Test
    fun whatIsNotAReportIsDropped() {
        val token = load()
        send("not a report")
        send("""{"kind":"failed"}""")
        send("""{"token":"$token","kind":"something else"}""")
        assertFalse(page.failed)
    }

    @Test
    fun noReportIsTakenOnceThePageIsClosed() {
        val token = load()
        page.close()
        send("""{"token":"$token","kind":"failed"}""")
        assertFalse(page.failed)
    }

    @Test
    fun aCoveredVideoPausesAndPlaysAgainOnceClear() {
        val token = load()
        page.stateChanged(token, PlayerState.PLAYING, 10.0, 90.0, last = true)
        page.cover(true)
        assertEquals(1, pauses)
        page.stateChanged(token, PlayerState.PAUSED, 10.0, 90.0, last = true)
        page.cover(false)
        assertEquals(1, resumes)
    }

    @Test
    fun aVideoTheUserPausedStaysPausedWhenASheetCloses() {
        val token = load()
        page.stateChanged(token, PlayerState.PAUSED, 10.0, 90.0, last = true)
        page.cover(true)
        page.cover(false)
        assertEquals(0, pauses)
        assertEquals(0, resumes)
    }

    @Test
    fun aVideoThatStartsUnderASheetIsPausedUntilItCloses() {
        val token = load()
        page.cover(true)
        assertEquals(0, pauses)
        send("""{"token":"$token","kind":"state","code":1,"time":0,"duration":90,"last":true}""")
        assertEquals(1, pauses)
        page.cover(false)
        assertEquals(1, resumes)
    }

    @Test
    fun leavingTheScreenSavesAtOnceAndPausesAndComingBackDoesNotPlay() {
        val token = load()
        page.stateChanged(token, PlayerState.PLAYING, 10.0, 90.0, last = true)
        page.stop()
        assertEquals(listOf(ProgressUpload.NOW), saves.uploads)
        assertEquals(1, pauses)
        page.start()
        assertEquals(0, resumes)
    }

    @Test
    fun aPageThatStartsPlayingOffTheScreenIsPaused() {
        val token = load()
        page.stop()
        assertEquals(1, pauses)
        // the page finished loading after the app left, and its player started
        send("""{"token":"$token","kind":"state","code":1,"time":0,"duration":90,"last":true}""")
        assertEquals(2, pauses)
        page.start()
        assertEquals(0, resumes)
        page.stateChanged(token, PlayerState.PLAYING, 0.0, 90.0, last = true)
        assertEquals(2, pauses)
    }

    @Test
    fun aSheetClosedOffTheScreenDoesNotPlay() {
        val token = load()
        page.stateChanged(token, PlayerState.PLAYING, 10.0, 90.0, last = true)
        page.cover(true)
        page.stop()
        page.cover(false)
        assertEquals(0, resumes)
    }
}
