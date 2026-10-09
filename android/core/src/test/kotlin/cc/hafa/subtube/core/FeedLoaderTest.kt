package cc.hafa.subtube.core

import java.util.concurrent.Executors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient

private class MapStorage : SyncStorage {
    val values = HashMap<String, String>()

    override fun read(key: String): String? = values[key]

    override fun write(key: String, value: String) {
        values[key] = value
    }

    override fun remove(key: String) {
        values.remove(key)
    }
}

class KeptAfterLoadTest {
    private val uploads = "UCone" to ContentMode.VIDEOS
    private val playlists = "UCone" to ContentMode.PLAYLISTS
    private val other = "UCtwo" to ContentMode.PLAYLISTS

    @Test
    fun dropsALoadedChannelsOtherKind() {
        assertEquals(emptySet(), keptAfterLoad(held = setOf(uploads, playlists), loaded = setOf(uploads), current = setOf(uploads)))
    }

    @Test
    fun keepsTheKindSwitchedToWhileTheLoadRan() {
        assertEquals(setOf(playlists), keptAfterLoad(held = setOf(uploads, playlists), loaded = setOf(uploads), current = setOf(playlists)))
    }

    @Test
    fun keepsEverythingOfChannelsTheLoadDidNotBring() {
        assertEquals(setOf(other), keptAfterLoad(held = setOf(uploads, other), loaded = setOf(uploads), current = setOf(uploads)))
    }

    @Test
    fun dropsEverythingOfAChannelNoLoadBrings() {
        val third = "UCthree" to ContentMode.VIDEOS
        assertEquals(
            setOf(third),
            keptAfterLoad(held = setOf(uploads, other, third), loaded = setOf(uploads), current = setOf(uploads, other, third), lapsed = setOf("UCtwo")),
        )
    }
}

class FeedLoaderThreadTest {
    @Test
    fun aLoadReadsItsAnswersAndReportsOffTheCallersThread() {
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.url.encodedPath) {
                "/drive/v3/files" -> MockResponse.Builder().body("""{"files":[]}""").build()
                "/youtube/v3/subscriptions" -> MockResponse.Builder()
                    .body("""{"items":[{"snippet":{"title":"One","resourceId":{"channelId":"UCone"}}}]}""")
                    .build()
                "/youtube/v3/playlistItems" -> MockResponse.Builder()
                    .body("""{"items":[{"snippet":{"title":"Video","publishedAt":"2026-01-01T00:00:00Z"},"contentDetails":{"videoId":"v1"}}]}""")
                    .build()
                "/youtube/v3/videos" -> MockResponse.Builder().body("""{"items":[{"id":"v1","contentDetails":{"duration":"PT10M"}}]}""").build()
                else -> MockResponse.Builder().code(404).build()
            }
        }
        server.start()
        val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "loader") }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val http = OkHttpClient()
            val storage = MapStorage()
            val store = SyncStore("UCme", "device", { "token" }, DriveClient(http, server.url("/")), storage, scope)
            val loader = FeedLoader(
                YouTubeClient(http, server.url("/youtube/v3/")),
                store,
                probe = null,
                compute = executor.asCoroutineDispatcher(),
            )
            val threads = HashSet<String>()
            val data = runBlocking {
                loader.load(
                    "token",
                    onProgress = { _, _ -> synchronized(threads) { threads.add(Thread.currentThread().name.substringBefore(' ')) } },
                    onChannels = { _, _ -> synchronized(threads) { threads.add(Thread.currentThread().name.substringBefore(' ')) } },
                )
            }
            assertEquals(setOf("loader"), threads)
            assertEquals(listOf("v1" to 600), data.items.map { item -> item.id to (item as Video).durationSeconds })
        } finally {
            scope.cancel()
            executor.shutdown()
            server.close()
        }
    }
}
