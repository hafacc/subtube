package cc.hafa.subtube

import androidx.test.core.app.ApplicationProvider
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.ContentMode
import cc.hafa.subtube.core.FilterMode
import cc.hafa.subtube.core.FilterScope
import cc.hafa.subtube.core.LiveFilter
import cc.hafa.subtube.core.ShortsFilter
import cc.hafa.subtube.core.phrasesToPattern
import cc.hafa.subtube.ui.filterSummary
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The one line under a channel's name that says what its filter does. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FilterSummaryTest {
    private val app: SubtubeApp = ApplicationProvider.getApplicationContext()
    private val plain = ChannelFilter(channelId = "UC1", title = "One", thumbnail = "", enabled = true, regex = "", mode = FilterMode.INCLUDE)

    private fun summary(filter: ChannelFilter): String = filterSummary(app, filter)

    @Test
    fun aFilterThatKeepsEverythingIsAllVideos() {
        assertEquals("All videos", summary(plain))
        assertEquals("Off", summary(plain.copy(enabled = false, topics = listOf("10"))))
    }

    @Test
    fun topicsAloneAreNamed() {
        assertEquals("Only Music", summary(plain.copy(topics = listOf("10"))))
    }

    @Test
    fun topicsGoLastByNameAndUnknownIdsAreDropped() {
        assertEquals("No Shorts · Only Gaming, Music", summary(plain.copy(shortsFilter = ShortsFilter.NORMAL, topics = listOf("10", "999", "20"))))
        assertEquals("All videos", summary(plain.copy(topics = listOf("999"))))
    }

    @Test
    fun oneSecondIsSingular() {
        assertEquals("Hides videos under 1 second", summary(plain.copy(minDurationSeconds = 1)))
        assertEquals("Hides videos under 60 seconds", summary(plain.copy(minDurationSeconds = 60)))
    }

    @Test
    fun liveReadsLikeShorts() {
        assertEquals("No live", summary(plain.copy(liveFilter = LiveFilter.NORMAL)))
        assertEquals("Shorts only · Live only", summary(plain.copy(shortsFilter = ShortsFilter.SHORTS, liveFilter = LiveFilter.VOD)))
    }

    @Test
    fun everyPartInTheEditorsOrder() {
        val full = plain.copy(
            followed = true,
            regex = phrasesToPattern(listOf("podcast", "live")),
            mode = FilterMode.EXCLUDE,
            searchScope = FilterScope.BOTH,
            shortsFilter = ShortsFilter.NORMAL,
            liveFilter = LiveFilter.NORMAL,
            minDurationSeconds = 90,
            topics = listOf("20", "1"),
        )
        assertEquals(
            "Followed in SubTube · Hides titles or descriptions matching podcast, live · No Shorts · No live · " +
                "Hides videos under 90 seconds · Only Film & Animation, Gaming",
            summary(full),
        )
    }

    @Test
    fun playlistsLeaveOutWhatTheirEditorHides() {
        val playlists = plain.copy(contentMode = ContentMode.PLAYLISTS, shortsFilter = ShortsFilter.NORMAL, minDurationSeconds = 60, topics = listOf("10"))
        assertEquals("Playlists", summary(playlists))
    }
}
