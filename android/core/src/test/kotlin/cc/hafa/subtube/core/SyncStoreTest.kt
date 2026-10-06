package cc.hafa.subtube.core

import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient

private class MemoryStorage : SyncStorage {
    val values = java.util.concurrent.ConcurrentHashMap<String, String>()

    override fun read(key: String): String? = values[key]

    override fun write(key: String, value: String) {
        values[key] = value
    }

    override fun remove(key: String) {
        values.remove(key)
    }
}

class SyncStoreTest {
    private val server = MockWebServer()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val otherDevice = """{"version":1,"channels":{},"watched":{"seen":{"at":1,"watched":true}}}"""
    private val uploads = java.util.concurrent.LinkedBlockingQueue<RecordedRequest>()
    private val deletes = java.util.concurrent.ConcurrentLinkedQueue<String>()

    // whether Drive still has this device's file when asked for it by id, whatever the listing says
    @Volatile
    private var ownFileThere = false

    // a file id whose delete Drive refuses
    @Volatile
    private var undeletable: String? = null

    @BeforeTest
    fun start() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.url.encodedPath
                return when {
                    request.headers["Authorization"] == "Bearer refused" -> MockResponse.Builder().code(401).build()
                    request.method == "GET" && path == "/drive/v3/files/mine" && ownFileThere -> MockResponse.Builder()
                        .body("""{"id":"mine"}""")
                        .build()
                    request.method == "GET" && path == "/drive/v3/files" -> MockResponse.Builder()
                        .body(
                            """{"files":[{"id":"other","name":"device-other.json","modifiedTime":"t1"},""" +
                                """{"id":"stray","name":"notes.json","modifiedTime":"t1"}]}""",
                        )
                        .build()
                    request.method == "GET" && path == "/drive/v3/files/other" -> MockResponse.Builder()
                        .body(otherDevice)
                        .build()
                    request.method == "DELETE" && path.startsWith("/drive/v3/files/") -> {
                        val fileId = path.substringAfterLast('/')
                        if (fileId == undeletable) {
                            MockResponse.Builder().code(500).build()
                        } else {
                            deletes.add(fileId)
                            MockResponse.Builder().code(204).build()
                        }
                    }
                    path.startsWith("/upload/drive/v3/files") -> {
                        uploads.add(request)
                        MockResponse.Builder().body("""{"id":"mine","name":"device-me.json","modifiedTime":"t2"}""").build()
                    }
                    else -> MockResponse.Builder().code(404).build()
                }
            }
        }
        server.start()
    }

    @AfterTest
    fun stop() {
        scope.cancel()
        server.close()
    }

    private fun store(storage: SyncStorage, token: String = "token", clock: () -> Long = System::currentTimeMillis): SyncStore = SyncStore(
        accountId = "UCme",
        deviceId = "me",
        getToken = { token },
        replaceToken = { "token" },
        drive = DriveClient(OkHttpClient(), server.url("/")),
        storage = storage,
        scope = scope,
        clock = clock,
        saveDelayMs = 100,
    )

    @Test
    fun aLoadKeepsItsEntriesAndDropsTheOldOnesOnce() = runBlocking {
        val day = 24L * 60 * 60 * 1000
        var now = 100 * day
        val storage = MemoryStorage()
        val store = store(storage) { now }
        store.setWatched(listOf("loaded", "gone"), true)
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))

        now += 29 * day
        store.noteLoaded(listOf("loaded", "never-marked"))
        val seen = assertNotNull(store.watchedEntry("loaded"))
        assertEquals(now, entrySeen(seen))
        assertEquals(100 * day, entryAt(seen))
        assertNotNull(store.watchedEntry("gone"))
        assertNull(store.watchedEntry("never-marked"))
        val refreshed = assertNotNull(uploads.poll(5, TimeUnit.SECONDS)).body!!.utf8()
        assertEquals(emptyList(), deviceFileProblems(Json.parseToJsonElement(refreshed)))

        store.noteLoaded(listOf("loaded"))
        assertNull(uploads.poll(400, TimeUnit.MILLISECONDS))

        now += day
        store.noteLoaded(listOf("loaded"))
        assertNull(store.watchedEntry("gone"))
        assertEquals(now, entrySeen(assertNotNull(store.watchedEntry("loaded"))))
        assertFalse("\"gone\"" in assertNotNull(uploads.poll(5, TimeUnit.SECONDS)).body!!.utf8())
    }

    @Test
    fun mergesOtherDevicesAndUploadsABurstOfEditsOnce() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.load()
        assertTrue(isWatchedEntry(store.watchedEntry("seen")))

        store.setWatched("a", true)
        store.setWatched("b", true)
        store.awaitWrites()
        assertTrue(storage.values.getValue("subtube.sync.UCme").contains("\"b\""))

        val upload = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertEquals("POST", upload.method)
        val body = upload.body!!.utf8()
        assertTrue("device-me.json" in body && "appDataFolder" in body && "\"a\"" in body && "\"b\"" in body)
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))

        store.setWatched("c", false)
        val update = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertEquals("PATCH", update.method)
        assertEquals("/upload/drive/v3/files/mine", update.url.encodedPath)
        assertEquals(emptyList(), deviceFileProblems(Json.parseToJsonElement(update.body!!.utf8())))
    }

    @Test
    fun marksSeveralAsOneEdit() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.setWatched(listOf("a", "b"), true)
        assertEquals(listOf(true, true, false), listOf("a", "b", "c").map { id -> isWatchedEntry(store.watchedEntry(id)) })
        store.awaitWrites()
        assertEquals(emptyList(), deviceFileProblems(Json.parseToJsonElement(storage.values.getValue("subtube.sync.UCme"))))

        store.setWatched(emptyList(), true)
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun keepsAPositionOnTheDeviceAndUploadsItOnlyWhenTold() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.load()
        store.setProgress("a", 42, ended = false, upload = false)
        assertEquals(42.0, entryPosition(store.watchedEntry("a")))
        store.awaitWrites()
        assertEquals(42.0, entryPosition(store(storage).watchedEntry("a")))
        assertNull(uploads.poll(400, TimeUnit.MILLISECONDS))

        store.setProgress("a", 50, ended = false, upload = true)
        val upload = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertEquals(50.0, entryPosition(store.watchedEntry("a")))
        assertFalse(isWatchedEntry(store.watchedEntry("a")))
        assertTrue("\"position\":50" in upload.body!!.utf8())
    }

    @Test
    fun markingKeepsAPositionAndUnmarkingDropsIt() = runBlocking {
        val store = store(MemoryStorage())
        store.setProgress("a", 42, ended = false, upload = false)
        store.setWatched("a", true)
        assertEquals(42.0, entryPosition(store.watchedEntry("a")))
        store.setWatched("a", false)
        assertNull(entryPosition(store.watchedEntry("a")))
        store.setProgress("b", 600, ended = true, upload = false)
        assertTrue(isWatchedEntry(store.watchedEntry("b")))
    }

    @Test
    fun savingAFilterDropsAPatternThatIsNotPhrases() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        val channel = defaultFilter(Subscription("UCone", "One", ""))
        store.setFilters(listOf(channel.copy(regex = "(ep|episode) ?\\d+"), channel.copy(channelId = "UCtwo", regex = "\\btrailer\\b")))
        val saved = store.channels(listOf(Subscription("UCone", "One", ""), Subscription("UCtwo", "Two", "")))
        assertEquals("", saved.getValue("UCone").regex)
        assertEquals("\\btrailer\\b", saved.getValue("UCtwo").regex)
    }

    @Test
    fun savesSeveralFiltersAsOneEdit() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        val subscriptions = listOf(Subscription("UCone", "One", ""), Subscription("UCtwo", "Two", ""))
        store.setFilters(subscriptions.map { subscription -> defaultFilter(subscription).copy(enabled = false) })
        assertEquals(listOf(false, false), store.channels(subscriptions).values.map(ChannelFilter::enabled))
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun savesASettingKeepingWhatItsEntryHeldAndReadsItBack() = runBlocking {
        val storage = MemoryStorage()
        storage.values["subtube.sync.UCme"] =
            """{"version":1,"channels":{},"watched":{},"settings":{"feedSort":{"at":1,"value":"by-channel","setOn":"tv"},"mystery":{"at":2,"value":null}}}"""
        val store = store(storage)
        assertEquals(Settings(), store.settings())

        store.setSetting(SettingName.FEED_SORT, JsonPrimitive(FeedSort.TITLE.wire))
        store.setSetting(SettingName.TOPIC_CHIPS, JsonArray(listOf(JsonPrimitive("Music"))))
        assertEquals(Settings(feedSort = FeedSort.TITLE, topicChips = listOf("Music")), store.settings())

        val upload = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        val body = upload.body!!.utf8()
        val saved = Json.parseToJsonElement(body.substring(body.indexOf("{\"version\""), body.lastIndexOf('}') + 1)).jsonObject
        assertEquals(emptyList(), deviceFileProblems(saved))
        val entries = saved.getValue("settings").jsonObject
        assertEquals(JsonPrimitive("tv"), entries.getValue("feedSort").jsonObject["setOn"])
        assertEquals(JsonPrimitive("title"), entries.getValue("feedSort").jsonObject["value"])
        assertEquals(Json.parseToJsonElement("""{"at":2,"value":null}"""), entries["mystery"])
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun aFileWithoutSettingsIsNotUploadedAgainJustToAddThem() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.setWatched("a", true)
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        store.awaitWrites()
        assertFalse("settings" in storage.values.getValue("subtube.sync.UCme"))
        assertEquals(emptyMap(), store.settingEntries())
    }

    @Test
    fun aLoadUploadsEditsTheLastRunNeverSent() = runBlocking {
        val storage = MemoryStorage()
        storage.values["subtube.sync.UCme"] =
            """{"version":1,"channels":{},"watched":{"unsent":{"at":${System.currentTimeMillis()},"watched":true}}}"""
        store(storage).load()
        val upload = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertTrue("\"unsent\"" in upload.body!!.utf8())
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun savesUnsentEditsAtOnceWhenAsked() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.load()
        store.saveUnsent()
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))

        store.setWatched("a", true)
        store.saveUnsent()
        assertNotNull(uploads.poll(0, TimeUnit.MILLISECONDS))
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun aDeleteThatFailsPartWayLeavesTheProfileToBeSavedAgain() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.setWatched("a", true)
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        undeletable = "stray"
        assertFailsWith<GoogleApiException> { store.deleteProfile() }
        assertTrue(isWatchedEntry(store.watchedEntry("a")))

        store.save()
        val upload = assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        assertEquals("POST", upload.method)
    }

    @Test
    fun keepsUnuploadedEditsAcrossRestarts() = runBlocking {
        val storage = MemoryStorage()
        val first = store(storage)
        first.setWatched("a", true)
        first.setWatched("b", true)
        first.awaitWrites()
        val second = store(storage)
        assertTrue(isWatchedEntry(second.watchedEntry("a")))
        assertTrue(isWatchedEntry(second.watchedEntry("b")))
    }

    @Test
    fun twoSavesAskedForTogetherUploadOnce() = runBlocking {
        val store = store(MemoryStorage())
        store.load()
        store.setProgress("a", 12, ended = false, upload = false)
        listOf(async { store.saveUnsent() }, async { store.saveUnsent() }).awaitAll()
        assertNotNull(uploads.poll(0, TimeUnit.MILLISECONDS))
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun aRefusedTokenIsReplacedOnceAndTheSaveMadeAgain() = runBlocking {
        val store = store(MemoryStorage(), token = "refused")
        store.setWatched("a", true)
        store.save()
        val upload = assertNotNull(uploads.poll(0, TimeUnit.MILLISECONDS))
        assertEquals("Bearer token", upload.headers["Authorization"])
    }

    @Test
    fun aListingThatTrailsThisDevicesUploadDoesNotDropTheProfile() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.setWatched("a", true)
        assertNotNull(uploads.poll(5, TimeUnit.SECONDS))
        ownFileThere = true
        store.load()
        assertFalse(store.deletedElsewhere.value)
        assertTrue(isWatchedEntry(store.watchedEntry("a")))
    }

    @Test
    fun deletingTheProfileEmptiesTheFolderAndThisDevice() = runBlocking {
        val storage = MemoryStorage()
        val store = store(storage)
        store.setWatched("a", true)
        store.deleteProfile()
        store.awaitWrites()
        assertEquals(listOf("other", "stray"), deletes.toList())
        assertTrue(storage.values.isEmpty())
        assertFalse(isWatchedEntry(store.watchedEntry("a")))
        store.setWatched("b", true)
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }

    @Test
    fun aLoadThatFindsTheUploadedFileGoneDropsEverything() = runBlocking {
        val storage = MemoryStorage()
        storage.values["subtube.uploaded.UCme"] = "true"
        val store = store(storage)
        store.setWatched("a", true)
        assertFailsWith<ProfileDeletedException> { store.load() }
        assertTrue(store.deletedElsewhere.value)
        store.awaitWrites()
        assertTrue(storage.values.isEmpty())
        assertFalse(isWatchedEntry(store.watchedEntry("a")))
        assertNull(uploads.poll(300, TimeUnit.MILLISECONDS))
    }
}
