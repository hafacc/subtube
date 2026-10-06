package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals

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
}

class ChannelIdentityCacheTest {
    @Test
    fun asksAgainForIdentitiesMissingOrOverADayOld() {
        var now = 1_000L
        val storage = MapStorage()
        val cache = ChannelIdentityCache(storage, "UCme", clock = { now })
        assertEquals(listOf("UCa", "UCb"), cache.missingOrStale(listOf("UCa", "UCb")))

        cache.putAll(mapOf("UCa" to ChannelIdentity("A", "a.jpg")))
        assertEquals(listOf("UCb"), cache.missingOrStale(listOf("UCa", "UCb")))

        now += IDENTITY_MAX_AGE_MS
        val reopened = ChannelIdentityCache(storage, "UCme", clock = { now })
        assertEquals(ChannelIdentity("A", "a.jpg"), reopened.all()["UCa"])
        assertEquals(listOf("UCb"), reopened.missingOrStale(listOf("UCa", "UCb")))
        now += 1
        assertEquals(listOf("UCa", "UCb"), reopened.missingOrStale(listOf("UCa", "UCb")))
    }

    @Test
    fun treatsAnIdentitySavedWithoutAnAgeAsStale() {
        val storage = MapStorage()
        storage.values["subtube.channels.UCme"] = """{"UCa":{"title":"A","thumbnail":""}}"""
        val cache = ChannelIdentityCache(storage, "UCme", clock = { IDENTITY_MAX_AGE_MS + 1 })
        assertEquals("A", cache.all().getValue("UCa").title)
        assertEquals(listOf("UCa"), cache.missingOrStale(listOf("UCa")))
    }
}
