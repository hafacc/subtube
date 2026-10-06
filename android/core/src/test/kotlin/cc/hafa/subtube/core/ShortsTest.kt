package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlinx.coroutines.test.runTest

private fun short(videoId: String, durationSeconds: Int): Video =
    video(videoId = videoId, title = videoId, durationSeconds = durationSeconds, liveStatus = null)

private fun verdicts(videos: List<Video>): Map<String, Boolean?> = videos.associate { item -> item.videoId to item.isShort }

class ClassifyShortsTest {
    @Test
    fun skipsTheShortsListWhenNothingIsShortEnough() = runTest {
        var asked = false
        val result = classifyShorts(listOf(short("long", 600)), {
            asked = true
            emptySet()
        })
        assertFalse(asked)
        assertEquals(mapOf<String, Boolean?>("long" to false), verdicts(result))
    }

    @Test
    fun judgesCandidatesByTheShortsList() = runTest {
        val result = classifyShorts(
            listOf(short("short", 30), short("clip", 90), short("long", 600)),
            { setOf("short", "long") },
        )
        assertEquals(mapOf<String, Boolean?>("short" to true, "clip" to false, "long" to false), verdicts(result))
    }

    @Test
    fun aChannelWithNoShortsListHasNoShorts() = runTest {
        val result = classifyShorts(listOf(short("clip", 90)), { null })
        assertEquals(mapOf<String, Boolean?>("clip" to false), verdicts(result))
    }

    @Test
    fun probesInsteadWhenThereIsNoListAndThePlatformCan() = runTest {
        val result = classifyShorts(
            listOf(short("short", 30), short("unsure", 40), short("long", 600)),
            { null },
            { videoId -> if (videoId == "short") true else null },
        )
        assertEquals(mapOf("short" to true, "unsure" to null, "long" to false), verdicts(result))
    }

    @Test
    fun aFailedProbeIsInconclusive() = runTest {
        val result = classifyShorts(listOf(short("clip", 30)), { null }, { throw IllegalStateException("offline") })
        assertEquals(mapOf<String, Boolean?>("clip" to null), verdicts(result))
    }
}
