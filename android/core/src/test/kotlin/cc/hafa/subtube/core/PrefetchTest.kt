package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.plus
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest

private val CHANNELS: List<ChannelFilter> = List(8) { index -> defaultFilter(Subscription("UC$index", "Channel $index", "")) }

private fun uploads(channelId: String, shorts: Boolean = false): ChannelItems =
    ChannelItems(ContentMode.VIDEOS, shorts, listOf(Video("v$channelId", channelId, "", "", "", "2026-01-01T00:00:00Z", "", durationSeconds = 30)))

/** A prefetch whose requests end only when released. */
private class Held(scope: CoroutineScope) {
    val started = ArrayList<String>()
    val shortsAsked = ArrayList<String>()
    private val fetches = HashMap<String, CompletableDeferred<ChannelItems>>()
    private val shortsLists = HashMap<String, CompletableDeferred<ChannelItems>>()
    val prefetch = Prefetch(
        scope,
        fetchAll = { channel ->
            started.add(channel.channelId)
            fetches.getOrPut(channel.channelId) { CompletableDeferred() }.await()
        },
        addShorts = { channel, _ ->
            shortsAsked.add(channel.channelId)
            shortsLists.getOrPut(channel.channelId) { CompletableDeferred() }.await()
        },
    )

    /** End [channelId]'s fetch with [items], or with [failure]. */
    fun release(channelId: String, items: ChannelItems = uploads(channelId), failure: Exception? = null) {
        val fetch = fetches.getOrPut(channelId) { CompletableDeferred() }
        if (failure == null) fetch.complete(items) else fetch.completeExceptionally(failure)
    }

    /** End [channelId]'s Shorts list request, or fail it. */
    fun releaseShorts(channelId: String, failure: Exception? = null) {
        val request = shortsLists.getOrPut(channelId) { CompletableDeferred() }
        if (failure == null) request.complete(uploads(channelId, shorts = true)) else request.completeExceptionally(failure)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PrefetchTest {
    // unconfined, so a fetch starts the moment a slot is free
    private fun TestScope.held(): Held = Held(backgroundScope + UnconfinedTestDispatcher(testScheduler))

    private val hidesShorts = CHANNELS[0].copy(shortsFilter = ShortsFilter.NORMAL)

    @Test
    fun fetchesNothingUntilItIsToldWhichChannels() = runTest {
        val held = held()
        assertEquals(emptyList(), held.started)
        assertNull(held.prefetch.items("UC0"))
    }

    @Test
    fun startsOnSixChannelsAtOnceAndHandsOverEachOnesItems() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS)
        assertEquals(listOf("UC0", "UC1", "UC2", "UC3", "UC4", "UC5"), held.started)
        held.release("UC0")
        assertEquals(uploads("UC0"), held.prefetch.items("UC0"))
        assertEquals("UC6", held.started.last())
    }

    @Test
    fun hasNothingForAFailedFetchOrAChannelItWasNotGiven() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(2))
        held.release("UC1", failure = IllegalStateException("refused"))
        assertNull(held.prefetch.items("UC1"))
        assertNull(held.prefetch.items("UCother"))
    }

    @Test
    fun aSecondSetKeepsWhatIsFetchedStartsWhatIsNewAndNeverStartsWhatWasDropped() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(7))
        held.prefetch.fetchOnly(listOf(CHANNELS[0], CHANNELS[1], CHANNELS[7]))
        (0..5).forEach { index -> held.release("UC$index") }
        held.release("UC7")
        assertEquals(listOf("UC0", "UC1", "UC2", "UC3", "UC4", "UC5", "UC7"), held.started)
        assertEquals(uploads("UC0"), held.prefetch.items("UC0"))
        assertEquals(uploads("UC7"), held.prefetch.items("UC7"))
        assertNull(held.prefetch.items("UC6"))
    }

    @Test
    fun aChannelDroppedWhileBeingFetchedHasNothingAndIsNotFetchedAgainWhenItComesBack() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(2))
        held.prefetch.fetchOnly(CHANNELS.take(1))
        assertNull(held.prefetch.items("UC1"))
        held.prefetch.fetchOnly(CHANNELS.take(2))
        held.release("UC1")
        assertEquals(uploads("UC1"), held.prefetch.items("UC1"))
        assertEquals(listOf("UC0", "UC1"), held.started)
    }

    @Test
    fun aShortsChoiceMadeAfterTheFetchAddsOnlyTheShortsList() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(1))
        held.release("UC0")
        held.prefetch.fetchOnly(listOf(hidesShorts))
        held.releaseShorts("UC0")
        assertEquals(uploads("UC0", shorts = true), held.prefetch.items("UC0"))
        assertEquals(listOf("UC0"), held.started)
        assertEquals(listOf("UC0"), held.shortsAsked)
    }

    @Test
    fun aShortsChoiceMadeWhileAChannelWaitsIsFetchedInOneGo() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(7))
        held.prefetch.fetchOnly(CHANNELS.take(6) + CHANNELS[6].copy(shortsFilter = ShortsFilter.SHORTS))
        held.release("UC0")
        held.release("UC6", uploads("UC6", shorts = true))
        assertEquals(uploads("UC6", shorts = true), held.prefetch.items("UC6"))
        assertEquals(emptyList(), held.shortsAsked)
    }

    @Test
    fun aShortsListThatFailsLeavesTheUploadsForTheFeedToAddTo() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS.take(1))
        held.release("UC0")
        held.prefetch.fetchOnly(listOf(hidesShorts))
        held.releaseShorts("UC0", failure = IllegalStateException("refused"))
        assertEquals(uploads("UC0"), held.prefetch.items("UC0"))
    }

    @Test
    fun afterTheDailyLimitRefusesARequestNoWaitingChannelIsAskedFor() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS)
        held.release("UC0", failure = DailyLimitException())
        (1..5).forEach { index -> held.release("UC$index") }
        assertNull(held.prefetch.items("UC6"))
        assertNull(held.prefetch.items("UC7"))
        assertEquals(6, held.started.size)
    }

    @Test
    fun endsWithNothingWhenCancelled() = runTest {
        val held = held()
        held.prefetch.fetchOnly(CHANNELS)
        held.prefetch.cancel()
        assertNull(held.prefetch.items("UC0"))
        assertNull(held.prefetch.items("UC7"))
    }
}

class CompleteItemsTest {
    private val plain = CHANNELS[0]
    private val hidesShorts = plain.copy(shortsFilter = ShortsFilter.NORMAL)
    private val playlists = plain.copy(contentMode = ContentMode.PLAYLISTS, shortsFilter = ShortsFilter.NORMAL)

    private suspend fun asked(channel: ChannelFilter, have: ChannelItems?): String {
        var asked = "nothing"
        completeItems(
            channel,
            have,
            fetchAll = { wanted ->
                asked = "everything"
                uploads(wanted.channelId, needsShorts(wanted))
            },
            addShorts = { wanted, _ ->
                asked = "shorts"
                uploads(wanted.channelId, shorts = true)
            },
        )
        return asked
    }

    @Test
    fun onlyUploadsWithShortsHiddenOrAloneNeedTheShortsList() {
        assertEquals(listOf(false, true, false), listOf(plain, hidesShorts, playlists).map(::needsShorts))
    }

    @Test
    fun asksForNothingWhenWhatIsFetchedIsEnough() = runTest {
        assertEquals("nothing", asked(plain, uploads("UC0")))
        assertEquals("nothing", asked(plain, uploads("UC0", shorts = true)))
        assertEquals("nothing", asked(hidesShorts, uploads("UC0", shorts = true)))
    }

    @Test
    fun asksOnlyForTheShortsListWhenUploadsLackIt() = runTest {
        assertEquals("shorts", asked(hidesShorts, uploads("UC0")))
    }

    @Test
    fun fetchesEverythingWithNothingFetchedOrTheOtherMode() = runTest {
        assertEquals("everything", asked(plain, null))
        assertEquals("everything", asked(playlists, uploads("UC0")))
        assertEquals("everything", asked(hidesShorts, ChannelItems(ContentMode.PLAYLISTS, shorts = false, emptyList())))
    }
}

class FetchChannelsTest {
    @Test
    fun aFailedChannelMakesTheLoadPartialAndTheRestGoOn() = runTest {
        val result = fetchChannels(CHANNELS.take(3)) { channel ->
            if (channel.channelId == "UC1") throw IllegalStateException("refused") else uploads(channel.channelId)
        }
        assertEquals(listOf("UC0", "UC2"), result.fetched.keys.toList())
        assertEquals(setOf("UC1"), result.failed)
        assertEquals(false, result.dailyLimit)
    }

    @Test
    fun theDailyLimitStopsTheRequestsNotYetSentAndKeepsWhatWasFetched() = runTest {
        val asked = ArrayList<String>()
        val result = fetchChannels(CHANNELS) { channel ->
            asked.add(channel.channelId)
            if (channel.channelId == "UC1") throw DailyLimitException() else uploads(channel.channelId)
        }
        assertEquals(listOf("UC0", "UC1"), asked)
        assertEquals(listOf("UC0"), result.fetched.keys.toList())
        assertEquals(CHANNELS.drop(1).mapTo(HashSet(), ChannelFilter::channelId), result.failed)
        assertEquals(true, result.dailyLimit)
    }

    @Test
    fun aRefusedTokenEndsTheFetch() = runTest {
        kotlin.test.assertFailsWith<TokenExpiredException> { fetchChannels(CHANNELS.take(2)) { throw TokenExpiredException() } }
    }

    @Test
    fun countsEveryChannelThatIsThroughFetchedFailedOrSkipped() = runTest {
        val counts = ArrayList<Int>()
        fetchChannels(CHANNELS, onFinished = counts::add) { channel ->
            when (channel.channelId) {
                "UC1" -> throw IllegalStateException("refused")
                "UC3" -> throw DailyLimitException()
                else -> uploads(channel.channelId)
            }
        }
        assertEquals((1..CHANNELS.size).toList(), counts)
    }
}

class LoadProgressTest {
    @Test
    fun startsAboveNothingAndEndsFull() {
        assertEquals(LOAD_PROGRESS_START, loadProgress(finished = 0, total = null))
        assertEquals(LOAD_PROGRESS_START, loadProgress(finished = 0, total = 8))
        assertEquals(LOAD_PROGRESS_START + (1 - LOAD_PROGRESS_START) / 2, loadProgress(finished = 4, total = 8), 1e-9)
        assertEquals(1.0, loadProgress(finished = 8, total = 8))
        assertEquals(1.0, loadProgress(finished = 0, total = 0))
    }

    @Test
    fun neverGoesBackAsChannelsFinish() {
        val steps = (0..8).map { finished -> loadProgress(finished, 8) }
        assertEquals(steps.sorted(), steps)
        assertEquals(steps.distinct(), steps)
    }
}
