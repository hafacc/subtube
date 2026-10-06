package cc.hafa.subtube.core

import java.util.logging.Level
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** A channel's fetch in a [Prefetch], waiting its turn. */
private class PrefetchJob(
    // the newest filter asked for; read when the job starts
    var channel: ChannelFilter,
    // what an earlier job fetched or is fetching for the channel, to build on
    val before: Deferred<ChannelItems?>?,
) {
    val result = CompletableDeferred<ChannelItems?>()
}

/** A channel a [Prefetch] is waiting to fetch, is fetching or has fetched. */
private class PrefetchEntry(var channel: ChannelFilter, var result: Deferred<ChannelItems?>, var waiting: PrefetchJob?)

/**
 * Channels' entries fetched in the background before the feed opens, so first
 * run can fetch the channels left on while its later screens show.
 *
 * [fetchOnly] names the channels to have, with the filters they will be shown
 * under; at most [FETCH_CONCURRENCY] are fetched at a time, in [scope]. A
 * channel whose fetch fails has nothing here and is left to the feed load,
 * which takes the rest through [FeedLoader.load]. Once YouTube's daily limit
 * refuses a request, nothing more is requested.
 */
class Prefetch(
    private val scope: CoroutineScope,
    /** Fetches a channel's entries. */
    private val fetchAll: suspend (ChannelFilter) -> ChannelItems,
    /** Fetches the Shorts marks a channel's fetched uploads lack. */
    private val addShorts: suspend (ChannelFilter, ChannelItems) -> ChannelItems,
) {
    private val lock = Any()
    private val supervisor = SupervisorJob(scope.coroutineContext[Job])

    // guarded by lock: every channel waiting, being fetched or fetched, wanted or not
    private val entries = HashMap<String, PrefetchEntry>()
    private var wanted: Set<String> = emptySet()
    private val waiting = ArrayDeque<PrefetchJob>()
    private val jobs = ArrayList<PrefetchJob>()
    private var running = 0
    private var refused = false

    /**
     * Have exactly [channels]: what was fetched or is being fetched for them
     * is kept, and added to when a channel's filter now needs more (the Shorts
     * list, or its other content mode); the others among them are queued; and
     * a channel not among them is taken out of the queue and has nothing here.
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    fun fetchOnly(channels: List<ChannelFilter>) {
        synchronized(lock) {
            wanted = channels.mapTo(HashSet(), ChannelFilter::channelId)
            val (kept, dropped) = waiting.partition { job -> job.channel.channelId in wanted }
            for (job in dropped) {
                val channelId = job.channel.channelId
                val before = job.before
                if (before == null) {
                    entries.remove(channelId)
                    job.result.complete(null)
                } else {
                    entries[channelId]?.let { entry ->
                        entry.result = before
                        entry.waiting = null
                    }
                    before.invokeOnCompletion { job.result.complete(if (before.isCancelled) null else before.getCompleted()) }
                }
            }
            waiting.clear()
            waiting.addAll(kept)
            for (channel in channels) {
                val entry = entries[channel.channelId]
                val queued = entry?.waiting
                if (queued != null) {
                    queued.channel = channel
                    entry.channel = channel
                } else if (entry == null ||
                    (entry.channel.contentMode ?: ContentMode.VIDEOS) != (channel.contentMode ?: ContentMode.VIDEOS) ||
                    (needsShorts(channel) && !needsShorts(entry.channel))
                ) {
                    val job = PrefetchJob(channel, entry?.result)
                    entries[channel.channelId] = PrefetchEntry(channel, job.result, job)
                    waiting.addLast(job)
                    jobs.add(job)
                }
            }
        }
        startWaiting()
    }

    private fun startWaiting() {
        while (true) {
            val job = synchronized(lock) {
                if (running < FETCH_CONCURRENCY) waiting.removeFirstOrNull()?.also { started ->
                    entries[started.channel.channelId]?.waiting = null
                    running += 1
                } else {
                    null
                }
            } ?: break
            scope.launch(supervisor) {
                var fetched: ChannelItems? = null
                try {
                    fetched = run(job)
                } finally {
                    job.result.complete(fetched)
                    synchronized(lock) { running -= 1 }
                }
                startWaiting()
            }
        }
    }

    private suspend fun run(job: PrefetchJob): ChannelItems? {
        val have = job.before?.await()
        return if (synchronized(lock) { refused }) {
            have
        } else {
            try {
                completeItems(job.channel, have, fetchAll, addShorts)
            } catch (caught: CancellationException) {
                throw caught
            } catch (caught: Exception) {
                if (caught is DailyLimitException) {
                    synchronized(lock) { refused = true }
                }
                logger.log(Level.WARNING, "fetch ahead of the feed failed", caught)
                have
            }
        }
    }

    /** What was fetched for a channel, once its fetches end; null when there is nothing. */
    suspend fun items(channelId: String): ChannelItems? =
        synchronized(lock) { if (channelId in wanted) entries[channelId]?.result else null }?.await()

    /** Stop fetching; channels still waiting or in flight end with nothing more. */
    fun cancel() {
        supervisor.cancel()
        synchronized(lock) {
            // a fetch that never got to start would leave its waiters hanging
            jobs.forEach { job -> job.result.complete(null) }
            waiting.clear()
        }
    }
}
