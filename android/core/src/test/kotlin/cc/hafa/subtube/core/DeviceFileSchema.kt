package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

private val FILTER_ENUMS = mapOf(
    "mode" to FilterMode.entries.map(FilterMode::wire),
    "searchScope" to FilterScope.entries.map(FilterScope::wire),
    "liveFilter" to LiveFilter.entries.map(LiveFilter::wire),
    "shortsFilter" to ShortsFilter.entries.map(ShortsFilter::wire),
    "contentMode" to ContentMode.entries.map(ContentMode::wire),
)

private fun JsonElement?.isWholeNumber(min: Long, max: Long): Boolean =
    (this as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.longOrNull?.let { number -> number in min..max } == true

private fun filterProblems(path: String, filter: JsonElement?): List<String> {
    if (filter !is JsonObject) {
        return listOf("$path is not an object")
    }
    val problems = ArrayList<String>()
    for (required in listOf("enabled", "regex", "mode")) {
        if (required !in filter) problems.add("$path.$required is missing")
    }
    for (identity in listOf("channelId", "title", "thumbnail")) {
        if (identity in filter) problems.add("$path.$identity must not be stored")
    }
    for (flag in listOf("enabled", "caseSensitive", "followed")) {
        if (flag in filter && filter[flag].booleanValue() == null) problems.add("$path.$flag is not a boolean")
    }
    val regex = filter["regex"]
    if (regex != null && (regex !is JsonPrimitive || !regex.isString || !isValidPattern(regex.content))) {
        problems.add("$path.regex is not a valid pattern")
    }
    for ((key, allowed) in FILTER_ENUMS) {
        val value = filter[key] ?: continue
        if (value !is JsonPrimitive || !value.isString || value.content !in allowed) problems.add("$path.$key is not one of $allowed")
    }
    if ("minDurationSeconds" in filter && !filter["minDurationSeconds"].isWholeNumber(0, Long.MAX_VALUE)) {
        problems.add("$path.minDurationSeconds is not a whole number of seconds")
    }
    val topics = filter["topics"]
    if (topics != null) {
        val ids = topics.stringsOrNull()
        if (ids == null || ids.distinct().size != ids.size) {
            problems.add("$path.topics is not a list of different strings")
        }
    }
    val groups = filter["groups"]
    if (groups != null) {
        val names = groups.stringsOrNull()
        if (names == null || names.any { name -> groupName(name) != name } || names.distinct().size != names.size) {
            problems.add("$path.groups is not a list of different group names")
        }
    }
    return problems
}

private fun watchedProblems(path: String, entry: JsonElement): List<String> = entryProblems(path, entry, "watched") { watched ->
    val problems = ArrayList<String>()
    if (watched.booleanValue() == null) problems.add("$path.watched is not a boolean")
    val position = (entry as JsonObject)["position"]
    val seconds = (position as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.doubleOrNull
    if (position != null && (seconds == null || seconds < 0)) problems.add("$path.position is not a number of seconds")
    if ("seen" in entry && !entry["seen"].isWholeNumber(0, MAX_SAFE_INTEGER)) problems.add("$path.seen is not a whole number from 0 to 2^53-1")
    problems
}

private fun entryProblems(path: String, entry: JsonElement, valueKey: String, check: (JsonElement?) -> List<String>): List<String> {
    if (entry !is JsonObject) {
        return listOf("$path is not an object")
    }
    val problems = ArrayList<String>()
    if (!entry["at"].isWholeNumber(0, MAX_SAFE_INTEGER)) problems.add("$path.at is not a whole number from 0 to 2^53-1")
    if (valueKey !in entry) problems.add("$path.$valueKey is missing") else problems.addAll(check(entry[valueKey]))
    return problems
}

/**
 * What makes [file] break shared/schema/device-file.schema.json, the rules a
 * writer must follow; empty when it is valid. Readers are more forgiving
 * ([readDeviceFile]).
 */
fun deviceFileProblems(file: JsonElement): List<String> {
    if (file !is JsonObject) {
        return listOf("the file is not an object")
    }
    val problems = ArrayList<String>()
    val version = file["version"] as? JsonPrimitive
    if (version == null || version.isString || version.doubleOrNull != DEVICE_FILE_VERSION.toDouble()) {
        problems.add("version is not $DEVICE_FILE_VERSION")
    }
    for (section in listOf("channels", "watched")) {
        val entries = file[section]
        if (entries !is JsonObject) {
            problems.add("$section is not an object")
            continue
        }
        for ((key, entry) in entries) {
            val path = "$section[$key]"
            if (key.isEmpty()) problems.add("$section has an empty key")
            problems.addAll(
                if (section == "channels") {
                    entryProblems(path, entry, "filter") { filter -> filterProblems("$path.filter", filter) }
                } else {
                    watchedProblems(path, entry)
                },
            )
        }
    }
    val settings = file["settings"]
    if (settings != null && settings !is JsonObject) {
        problems.add("settings is not an object")
    }
    for ((name, entry) in (settings as? JsonObject).orEmpty()) {
        if (name.isEmpty()) problems.add("settings has an empty key")
        problems.addAll(entryProblems("settings[$name]", entry, "value") { emptyList() })
    }
    return problems
}
