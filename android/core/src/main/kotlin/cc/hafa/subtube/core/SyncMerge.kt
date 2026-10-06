package cc.hafa.subtube.core

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/** The only device-file format there is; a file with any other version is skipped. */
const val DEVICE_FILE_VERSION: Int = 1

/** A watched entry neither saved nor loaded for this long is dropped when its device next saves. */
const val WATCHED_RETENTION_MS: Long = 30L * 24 * 60 * 60 * 1000

/** How old an entry's `seen` gets before a load writes a new one. */
const val SEEN_REFRESH_MS: Long = 24L * 60 * 60 * 1000

/** A Drive file name a device writes, capturing its device id. */
private val DEVICE_FILE_NAME = Regex("^device-([A-Za-z0-9_-]+)\\.json$")

/** The device id in a Drive file name, or null when the name isn't a device file's. */
fun deviceIdOf(fileName: String): String? = DEVICE_FILE_NAME.matchEntire(fileName)?.groupValues?.get(1)

/**
 * Whether an app folder holding [fileNames] is an account already set up: another device has written its file.
 * This device's own ([ownName]) doesn't count, since setup writes it before it is through.
 */
fun isAlreadySetUp(fileNames: Collection<String>, ownName: String): Boolean =
    fileNames.any { name -> name != ownName && deviceIdOf(name) != null }

/**
 * Whether the profile was deleted from another device: this device uploaded
 * its file before ([uploadedBefore]), and a folder listing ([fileNames]) no
 * longer holds it ([ownName]).
 */
fun wasDeletedElsewhere(uploadedBefore: Boolean, fileNames: Collection<String>, ownName: String): Boolean =
    uploadedBefore && ownName !in fileNames

/** The Drive file name a device writes to. */
fun deviceFileName(deviceId: String): String = "device-$deviceId.json"

/**
 * One device's `device-<id>.json`, as shared/schema/device-file.schema.json
 * describes it. Entries are kept as the JSON objects they were read as, so
 * fields this version doesn't know survive a rewrite.
 */
data class DeviceFile(
    /** Channel entries (`{at, filter}`), by channel id. */
    val channels: Map<String, JsonObject> = emptyMap(),
    /** Watched entries (`{at, watched}`, with a video's `position` in seconds and the device's `seen`), by video or playlist id. */
    val watched: Map<String, JsonObject> = emptyMap(),
    /** Setting entries (`{at, value}`), by setting name; null when the file has no `settings`, which then isn't written. */
    val settings: Map<String, JsonObject>? = null,
    /** Top-level fields other than version, channels, watched and settings. */
    val extra: Map<String, JsonElement> = emptyMap(),
)

private fun entryTime(entry: JsonObject, key: String): Long? =
    (entry[key] as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.longOrNull?.takeIf { time -> time in 0..MAX_SAFE_INTEGER }

/** An entry's `at`: a whole number from 0 to 2^53-1, or null when it has none. */
fun entryAt(entry: JsonObject): Long? = entryTime(entry, "at")

/** When a watched entry's device last had it among a full load's items; null when missing or not a time. */
fun entrySeen(entry: JsonObject): Long? = entryTime(entry, "seen")

private fun validChannelEntry(entry: JsonElement): Boolean =
    entry is JsonObject && entryAt(entry) != null && entry["filter"] is JsonObject

private fun validWatchedEntry(entry: JsonElement): Boolean =
    entry is JsonObject && entryAt(entry) != null && entry["watched"].booleanValue() != null

private fun validSettingEntry(entry: JsonElement): Boolean =
    entry is JsonObject && entryAt(entry) != null && "value" in entry

/** A whole channel entry's filter object. */
fun entryFilter(entry: JsonObject): JsonObject = entry["filter"] as? JsonObject ?: JsonObject(emptyMap())

/** A whole watched entry's mark. */
fun entryWatched(entry: JsonObject): Boolean = (entry["watched"] as? JsonPrimitive)?.booleanOrNull ?: false

/**
 * A watched entry after a mark made at [at]: marking watched keeps its
 * position, unmarking drops it, or a position near the end would read as
 * watched again. Fields this version doesn't know are kept.
 */
fun markedEntry(prior: JsonObject?, at: Long, watched: Boolean): JsonObject {
    val edited = prior.orEmpty() + mapOf("at" to JsonPrimitive(at), "watched" to JsonPrimitive(watched))
    return JsonObject(if (watched) edited else edited - "position")
}

/**
 * A watched entry after its video played to [position] seconds, saved at
 * [at]; [ended] when the player reported the end, which alone marks it
 * watched here.
 */
fun playedEntry(prior: JsonObject?, at: Long, position: Long, ended: Boolean): JsonObject =
    JsonObject(prior.orEmpty() + mapOf("at" to JsonPrimitive(at), "watched" to JsonPrimitive(ended), "position" to JsonPrimitive(position)))

/**
 * Read a downloaded file the forgiving way (shared/fixtures/merge.json): null
 * when it isn't an object or its version isn't 1; sections that aren't
 * objects read as empty; malformed entries are dropped. `settings` is read
 * only when the file has one.
 */
fun readDeviceFile(content: JsonElement?): DeviceFile? {
    val root = content as? JsonObject ?: return null
    val version = root["version"] as? JsonPrimitive
    if (version == null || version.isString || version.longOrNull != DEVICE_FILE_VERSION.toLong() || version.content != "1") {
        return null
    }
    fun section(key: String, valid: (JsonElement) -> Boolean): Map<String, JsonObject> =
        (root[key] as? JsonObject).orEmpty().filterValues(valid).mapValues { (_, entry) -> entry as JsonObject }
    return DeviceFile(
        channels = section("channels", ::validChannelEntry),
        watched = section("watched", ::validWatchedEntry),
        settings = if ("settings" in root) section("settings", ::validSettingEntry) else null,
        extra = root.filterKeys { key -> key !in setOf("version", "channels", "watched", "settings") },
    )
}

/** Parse and read downloaded text; null when it isn't JSON or isn't a readable device file. */
fun parseDeviceFile(raw: String?): DeviceFile? =
    if (raw == null) {
        null
    } else {
        try {
            readDeviceFile(Json.parseToJsonElement(raw))
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

/** A device file as the JSON object it is written as. */
fun deviceFileJson(file: DeviceFile): JsonObject = JsonObject(
    linkedMapOf<String, JsonElement>("version" to JsonPrimitive(DEVICE_FILE_VERSION)) +
        file.extra +
        mapOf("channels" to JsonObject(file.channels), "watched" to JsonObject(file.watched)) +
        file.settings?.let { settings -> mapOf("settings" to JsonObject(settings)) }.orEmpty(),
)

/** Serialize a device file. */
fun encodeDeviceFile(file: DeviceFile): String = deviceFileJson(file).toString()

private fun newest(records: List<Pair<String, Map<String, JsonObject>>>): Map<String, JsonObject> {
    val merged = LinkedHashMap<String, Pair<String, JsonObject>>()
    for ((deviceId, record) in records) {
        for ((key, entry) in record) {
            val prior = merged[key]
            val at = entryAt(entry) ?: continue
            val priorAt = prior?.let { (_, priorEntry) -> entryAt(priorEntry) }
            if (prior == null || priorAt == null || at > priorAt || (at == priorAt && deviceId > prior.first)) {
                merged[key] = deviceId to entry
            }
        }
    }
    return merged.mapValues { (_, winner) -> winner.second }
}

/**
 * Every device's file, by device id, merged into one view: per key the
 * greatest `at` wins, and on equal `at` the greater device id (ASCII order).
 * The winning entry is kept whole. The view always has `settings`, empty when
 * no file has any. Each file has one writer, so nothing here ever conflicts;
 * the files only disagree about time.
 */
fun mergeDeviceFiles(files: Map<String, DeviceFile>): DeviceFile {
    val ordered = files.entries.map { (deviceId, file) -> deviceId to file }
    return DeviceFile(
        channels = newest(ordered.map { (deviceId, file) -> deviceId to file.channels }),
        watched = newest(ordered.map { (deviceId, file) -> deviceId to file.watched }),
        settings = newest(ordered.map { (deviceId, file) -> deviceId to file.settings.orEmpty() }),
    )
}

/**
 * A device's own file after a full load whose items were [loadedIds]: each of
 * its watched entries among them gets `seen` set to [now], unless its `seen`
 * is younger than [SEEN_REFRESH_MS]. `at` is never changed.
 */
fun refreshSeen(file: DeviceFile, loadedIds: Set<String>, now: Long): DeviceFile {
    val refreshed = file.watched.filter { (id, entry) ->
        id in loadedIds && entrySeen(entry).let { seen -> seen == null || now - seen >= SEEN_REFRESH_MS }
    }
    return if (refreshed.isEmpty()) {
        file
    } else {
        file.copy(watched = file.watched + refreshed.mapValues { (_, entry) -> JsonObject(entry + ("seen" to JsonPrimitive(now))) })
    }
}

/**
 * A device's own file without the watched entries neither saved nor among a
 * load's items within [WATCHED_RETENTION_MS]; everything else unchanged.
 */
fun pruneDeviceFile(file: DeviceFile, now: Long): DeviceFile =
    file.copy(
        watched = file.watched.filterValues { entry ->
            now - maxOf(entryAt(entry) ?: 0, entrySeen(entry) ?: 0) < WATCHED_RETENTION_MS
        },
    )

/** A channel's name and avatar, which YouTube owns and the device files never hold. */
data class ChannelIdentity(
    /** The channel's name. */
    val title: String,
    /** The channel's avatar URL; empty when there is none. */
    val thumbnail: String,
)

/** The filter a subscription has until someone edits it. */
fun defaultFilter(subscription: Subscription): ChannelFilter =
    filterFromJson(subscription.channelId, subscription.title, subscription.thumbnail, JsonObject(emptyMap()))

/**
 * The channels the feed reads: every YouTube subscription with its saved filter
 * (or the default), plus the channels followed in subtube, named from
 * [followedIdentities] (looked up on YouTube, since the files don't hold
 * names). A filter saved for a channel since unsubscribed is kept, so
 * subscribing again restores it.
 */
fun channelsFor(
    merged: DeviceFile,
    subscriptions: List<Subscription>,
    followedIdentities: Map<String, ChannelIdentity> = emptyMap(),
): Map<String, ChannelFilter> {
    val channels = LinkedHashMap<String, ChannelFilter>()
    for (subscription in subscriptions) {
        val saved = merged.channels[subscription.channelId]?.let(::entryFilter) ?: JsonObject(emptyMap())
        channels[subscription.channelId] = filterFromJson(subscription.channelId, subscription.title, subscription.thumbnail, saved)
    }
    for ((channelId, entry) in merged.channels) {
        if (channelId in channels) {
            continue
        }
        val identity = followedIdentities[channelId]
        val filter = filterFromJson(channelId, identity?.title ?: channelId, identity?.thumbnail.orEmpty(), entryFilter(entry))
        if (filter.followed == true) {
            channels[channelId] = filter
        }
    }
    return channels
}

/** The channels followed in subtube but not subscribed to on YouTube. */
fun followedChannelIds(merged: DeviceFile, subscriptions: List<Subscription>): List<String> {
    val subscribed = subscriptions.mapTo(HashSet(), Subscription::channelId)
    return merged.channels.filter { (channelId, entry) ->
        channelId !in subscribed && entryFilter(entry)["followed"].booleanValue() == true
    }.keys.toList()
}
