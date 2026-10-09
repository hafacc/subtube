package cc.hafa.subtube.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

private val subscription = Subscription(channelId = "UCone", title = "One", thumbnail = "one.jpg")

private fun json(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject

private fun entry(filter: String, at: Long = 1): JsonObject = json("""{"at":$at,"filter":$filter}""")

class IsAlreadySetUpTest {
    @Test
    fun anEmptyFolderIsNotSetUp() {
        assertFalse(isAlreadySetUp(emptyList(), "device-me.json"))
    }

    @Test
    fun anyDevicesFileMeansSetUp() {
        assertTrue(isAlreadySetUp(listOf("notes.txt", "device-abc_1.json"), "device-me.json"))
    }

    @Test
    fun otherFilesDoNotCount() {
        assertFalse(isAlreadySetUp(listOf("device-.json", "device-a b.json", "backup-device-a.json", "device-a.json.bak"), "device-me.json"))
    }

    @Test
    fun thisDevicesOwnFileDoesNotCount() {
        assertFalse(isAlreadySetUp(listOf("device-me.json"), "device-me.json"))
        assertTrue(isAlreadySetUp(listOf("device-me.json", "device-other.json"), "device-me.json"))
    }
}

class WasDeletedElsewhereTest {
    @Test
    fun aMissingOwnFileAfterAnUploadMeansDeleted() {
        assertTrue(wasDeletedElsewhere(uploadedBefore = true, fileNames = emptyList(), ownName = "device-me.json"))
        assertTrue(wasDeletedElsewhere(uploadedBefore = true, fileNames = listOf("device-other.json"), ownName = "device-me.json"))
    }

    @Test
    fun anOwnFileStillThereMeansNotDeleted() {
        assertFalse(wasDeletedElsewhere(uploadedBefore = true, fileNames = listOf("device-me.json"), ownName = "device-me.json"))
    }

    @Test
    fun aDeviceThatNeverUploadedIsNotDeleted() {
        assertFalse(wasDeletedElsewhere(uploadedBefore = false, fileNames = emptyList(), ownName = "device-me.json"))
    }
}

class FilterJsonTest {
    @Test
    fun writesSettingsButNeverTheChannelsIdentity() {
        val filter = defaultFilter(subscription).copy(regex = "Ep", mode = FilterMode.EXCLUDE, minDurationSeconds = 60)
        assertEquals(json("""{"enabled":true,"regex":"Ep","mode":"exclude","minDurationSeconds":60}"""), filterToJson(filter))
    }

    @Test
    fun keepsUnknownFieldsAndValuesItDidNotChange() {
        val stored = json("""{"enabled":true,"regex":"","mode":"include","liveFilter":"premieres","sortOrder":"newest","title":"old"}""")
        val read = filterFromJson("UCone", "One", "", stored)
        assertNull(read.liveFilter)
        val written = filterToJson(read.copy(regex = "x"))
        assertEquals(JsonPrimitive("premieres"), written["liveFilter"])
        assertEquals(JsonPrimitive("newest"), written["sortOrder"])
        assertEquals(JsonPrimitive("x"), written["regex"])
        assertFalse("title" in written)
    }

    @Test
    fun clearingASettingRemovesItsKey() {
        val read = filterFromJson("UCone", "One", "", json("""{"enabled":true,"regex":"","mode":"include","shortsFilter":"normal"}"""))
        assertFalse("shortsFilter" in filterToJson(read.copy(shortsFilter = null)))
    }
}

class DeviceFileTest {
    @Test
    fun skipsWhatItCannotRead() {
        assertNull(parseDeviceFile("""{"version":2,"channels":{},"watched":{}}"""))
        assertNull(parseDeviceFile("null"))
        assertNull(parseDeviceFile(null))
        assertNull(parseDeviceFile("not json"))
    }

    @Test
    fun onlyDeviceFilesNameADevice() {
        assertEquals("a-b_9", deviceIdOf("device-a-b_9.json"))
        assertNull(deviceIdOf("device-.json"))
        assertNull(deviceIdOf("device-a b.json"))
        assertNull(deviceIdOf("settings.json"))
    }

    @Test
    fun writesWhatTheSchemaAllows() {
        val filter = filterToJson(defaultFilter(subscription).copy(regex = "(ep|episode) ?\\d+"))
        val file = DeviceFile(
            channels = mapOf("UCone" to JsonObject(mapOf("at" to JsonPrimitive(1), "filter" to filter))),
            watched = mapOf("v" to json("""{"at":2,"watched":false}""")),
        )
        assertEquals(emptyList(), deviceFileProblems(Json.parseToJsonElement(encodeDeviceFile(file))))
        assertEquals(file, parseDeviceFile(encodeDeviceFile(file)))
    }
}

class ChannelsForTest {
    @Test
    fun defaultsNewSubscriptionsAndTakesIdentityFromYouTube() {
        val merged = DeviceFile(channels = mapOf("UCone" to entry("""{"enabled":true,"regex":"x","mode":"include"}""")))
        val channels = channelsFor(merged, listOf(subscription, Subscription("UCtwo", "Two", "two.jpg")))
        assertEquals("One", channels.getValue("UCone").title)
        assertEquals("x", channels.getValue("UCone").regex)
        assertTrue(channels.getValue("UCtwo").enabled)
        assertEquals("", channels.getValue("UCtwo").regex)
    }

    @Test
    fun listsOnlySubscriptionsWhateverElseIsSaved() {
        val merged = DeviceFile(
            channels = mapOf(
                "UCgone" to entry("""{"enabled":true,"regex":"","mode":"include"}"""),
                "UCone" to entry("""{"enabled":false,"regex":"","mode":"include"}"""),
            ),
        )
        val channels = channelsFor(merged, listOf(subscription))
        assertEquals(listOf("UCone"), channels.keys.toList())
        assertEquals(false, channels.getValue("UCone").enabled)
    }
}
