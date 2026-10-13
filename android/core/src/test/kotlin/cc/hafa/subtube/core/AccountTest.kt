package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AccountTest {
    private val channelId = "UC" + "a".repeat(22)

    private class MapStorage(val values: MutableMap<String, String> = HashMap()) : SyncStorage {
        override fun read(key: String): String? = values[key]

        override fun write(key: String, value: String) {
            values[key] = value
        }

        override fun remove(key: String) {
            values.remove(key)
        }
    }

    @Test
    fun anAccountNeedsDrivesId() {
        assertNull(DriveUser("Ada").toAccount())
        assertEquals(Account(id = "42", name = "Ada"), DriveUser("Ada", permissionId = "42").toAccount())
    }

    @Test
    fun onlyChannelIdsAreOldAccountIds() {
        assertTrue(isChannelId(channelId))
        assertFalse(isChannelId("108234567890123456789"))
        assertFalse(isChannelId("UCshort"))
        assertEquals(
            setOf(channelId),
            oldSyncAccountIds(listOf(syncKey(channelId), uploadedKey(channelId), syncKey("42"), uploadedKey("42"), "notes")),
        )
    }

    @Test
    fun entriesFiledUnderAChannelMoveToTheAccount() {
        val storage = MapStorage(hashMapOf(syncKey(channelId) to "edits", uploadedKey(channelId) to "file-1"))
        moveSyncEntries(storage, channelId, "42")
        assertEquals(mapOf(syncKey("42") to "edits", uploadedKey("42") to "file-1"), storage.values)
    }

    @Test
    fun whatTheAccountAlreadyHasStays() {
        val storage = MapStorage(hashMapOf(syncKey(channelId) to "old", syncKey("42") to "new"))
        moveSyncEntries(storage, channelId, "42")
        assertEquals(mapOf(syncKey("42") to "new"), storage.values)
    }
}
