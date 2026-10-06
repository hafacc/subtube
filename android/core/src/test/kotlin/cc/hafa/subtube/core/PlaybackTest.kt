package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals

/** A feed that writes down what a [Playback] saves. */
private class RecordingFeed(private val item: FeedItem?) : PlaybackFeed {
    val saved = ArrayList<String>()

    override fun recordProgress(id: String, position: Double, playerDuration: Double, ended: Boolean, upload: ProgressUpload) {
        saved.add("$id ${position.toInt()}/${playerDuration.toInt()} ${if (ended) "ended " else ""}${upload.name.lowercase()}")
    }

    override fun setWatched(id: String, watched: Boolean) {
        saved.add("$id watched=$watched")
    }

    override fun findItem(id: String): FeedItem? = item
}

class PlaybackTest {
    private var ended = 0

    private fun of(feed: RecordingFeed, isPlaylist: Boolean = false): Playback =
        Playback(if (isPlaylist) "PL1" else "v1", isPlaylist, feed) { ended += 1 }

    @Test
    fun savesNothingBeforeItHasPlayed() {
        val feed = RecordingFeed(video())
        val playback = of(feed)
        playback.tick()
        playback.save(ProgressUpload.SOON)
        playback.stateChanged(PlayerState.PAUSED, 0.0, 600.0)
        assertEquals(emptyList(), feed.saved)
    }

    @Test
    fun savesOnThisDeviceWhilePlayingAndUploadsOnPauseAndOnLeaving() {
        val feed = RecordingFeed(video())
        val playback = of(feed)
        playback.stateChanged(PlayerState.PLAYING, 0.0, 600.0)
        playback.positionChanged(5.0, 600.0)
        playback.tick()
        playback.stateChanged(PlayerState.PAUSED, 7.5, 600.0)
        playback.tick()
        playback.save(ProgressUpload.NOW)
        assertEquals(listOf("v1 5/600 later", "v1 7/600 soon", "v1 7/600 now"), feed.saved)
    }

    @Test
    fun theEndMarksItRunsOnEndedAndStopsLaterSaves() {
        val feed = RecordingFeed(video())
        val playback = of(feed)
        playback.stateChanged(PlayerState.PLAYING, 590.0, 600.0)
        playback.stateChanged(PlayerState.ENDED, 600.0, 600.0)
        playback.save(ProgressUpload.SOON)
        assertEquals(listOf("v1 600/600 ended soon"), feed.saved)
        assertEquals(1, ended)
    }

    @Test
    fun playingAgainAfterTheEndSavesAgain() {
        val feed = RecordingFeed(video())
        val playback = of(feed)
        playback.stateChanged(PlayerState.PLAYING, 590.0, 600.0)
        playback.stateChanged(PlayerState.ENDED, 600.0, 600.0)
        playback.stateChanged(PlayerState.PLAYING, 30.0, 600.0)
        playback.save(ProgressUpload.SOON)
        assertEquals("v1 30/600 soon", feed.saved.last())
    }

    @Test
    fun aLiveBroadcastSavesNoPositionAndIsMarkedAtItsEnd() {
        val feed = RecordingFeed(video(liveStatus = LiveStatus.LIVE))
        val playback = of(feed)
        playback.stateChanged(PlayerState.PLAYING, 10.0, 0.0)
        playback.tick()
        playback.stateChanged(PlayerState.PAUSED, 20.0, 0.0)
        playback.stateChanged(PlayerState.ENDED, 30.0, 0.0)
        assertEquals(listOf("v1 watched=true"), feed.saved)
    }

    @Test
    fun aPlaylistSavesNoPositionAndIsMarkedOnlyWhenItsLastVideoEnds() {
        val feed = RecordingFeed(playlist())
        val playback = of(feed, isPlaylist = true)
        playback.stateChanged(PlayerState.PLAYING, 0.0, 100.0)
        playback.tick()
        playback.stateChanged(PlayerState.ENDED, 100.0, 100.0, lastOfPlaylist = false)
        assertEquals(emptyList(), feed.saved)
        assertEquals(0, ended)
        playback.stateChanged(PlayerState.ENDED, 100.0, 100.0, lastOfPlaylist = true)
        assertEquals(listOf("PL1 watched=true"), feed.saved)
        assertEquals(1, ended)
    }
}
