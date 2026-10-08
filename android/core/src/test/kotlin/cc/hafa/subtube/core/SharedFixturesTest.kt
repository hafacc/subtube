package cc.hafa.subtube.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/** The shared/ folder, passed in by Gradle (see core/build.gradle.kts). */
private val shared: File = File(
    checkNotNull(System.getProperty("subtube.shared")) { "run through Gradle: the subtube.shared property names ../shared" },
)

private fun fixture(name: String): List<JsonObject> {
    val root = Json.parseToJsonElement(File(shared, "fixtures/$name").readText()).jsonObject
    return root.getValue("cases").jsonArray.map(JsonElement::jsonObject)
}

private fun cases(name: String, check: (JsonObject) -> Unit): List<DynamicTest> =
    fixture(name).map { case -> DynamicTest.dynamicTest(case.getValue("name").jsonPrimitive.content) { check(case) } }

private val JsonObject.name: String get() = getValue("name").jsonPrimitive.content

private fun JsonElement?.text(): String = (this as? JsonPrimitive)?.content.orEmpty()

private fun JsonElement?.intOrNull(): Int? = (this as? JsonPrimitive)?.intOrNull

/** A feed item from a fixture: only the fields a filter reads; absent means unknown. */
private fun feedItem(item: JsonObject): FeedItem {
    val title = item["title"].text()
    val description = item["description"].text()
    return if (item["kind"].text() == "playlist") {
        Playlist("PL", "UC", "", title, description, "", "", itemCount = 0)
    } else {
        Video(
            videoId = "v",
            channelId = "UC",
            channelTitle = "",
            title = title,
            description = description,
            publishedAt = "",
            thumbnail = "",
            durationSeconds = item["durationSeconds"].intOrNull(),
            liveStatus = item["liveStatus"]?.text()?.let { status -> LiveStatus.valueOf(status.uppercase()) },
            isShort = (item["isShort"] as? JsonPrimitive)?.booleanOrNull,
            categoryId = (item["categoryId"] as? JsonPrimitive)?.content,
        )
    }
}

/** A feed item from an ordering or chips fixture; an absent title is the id, and other absent fields are unknown. */
private fun listed(element: JsonElement): FeedItem {
    val item = element.jsonObject
    val id = item["id"].text()
    val title = (item["title"] as? JsonPrimitive)?.content ?: id
    val publishedAt = item["publishedAt"].text()
    val channelId = (item["channelId"] as? JsonPrimitive)?.content ?: "UC"
    return if (item["kind"].text() == "playlist") {
        Playlist(id, channelId, "", title, "", publishedAt, "", itemCount = 0)
    } else {
        Video(
            videoId = id,
            channelId = channelId,
            channelTitle = "",
            title = title,
            description = "",
            publishedAt = publishedAt,
            thumbnail = "",
            durationSeconds = item["durationSeconds"].intOrNull(),
            categoryId = (item["categoryId"] as? JsonPrimitive)?.content,
        )
    }
}

private fun JsonElement?.texts(): List<String> = (this as? JsonArray).orEmpty().map { element -> element.text() }

private inline fun <reified Choice> JsonElement?.choice(): Choice where Choice : Enum<Choice>, Choice : WireValue {
    val wire = text()
    return enumValues<Choice>().first { choice -> choice.wire == wire }
}

/** Saved filters from a fixture, by channel id. */
private fun savedFilters(filters: JsonElement?): Map<String, ChannelFilter> =
    (filters as? JsonObject).orEmpty().mapValues { (channelId, filter) -> filterFromJson(channelId, "", "", filter.jsonObject) }

/** Listed channels from a fixture's map of each one's groups. */
private fun groupedChannels(channelGroups: JsonElement?): List<ChannelFilter> =
    (channelGroups as? JsonObject).orEmpty().map { (channelId, names) ->
        defaultFilter(Subscription(channelId, channelId, "")).copy(groups = names.texts())
    }

class SharedFixturesTest {
    @Test
    fun metaRegexMatchesTheSharedFile() {
        assertEquals(File(shared, "patterns/meta-regex.txt").readText().trimEnd(), PATTERN_META_REGEX)
    }

    @TestFactory
    fun patterns(): List<DynamicTest> = cases("patterns.json") { case ->
        val pattern = case["pattern"].text()
        val valid = case.getValue("valid").jsonPrimitive.booleanOrNull!!
        assertEquals(valid, isValidPattern(pattern), "valid: ${case.name}")
        for (element in case["matches"]?.jsonArray.orEmpty()) {
            val check = element.jsonObject
            val text = check["text"].text()
            val caseSensitive = check.getValue("caseSensitive").jsonPrimitive.booleanOrNull!!
            val regex = checkNotNull(compilePattern(pattern, caseSensitive))
            assertEquals(check.getValue("matches").jsonPrimitive.booleanOrNull, regex.containsMatchIn(text), "“$pattern” in “$text”, caseSensitive $caseSensitive")
        }
    }

    @TestFactory
    fun filters(): List<DynamicTest> = cases("filters.json") { case ->
        val filter = filterFromJson("UC", "", "", case.getValue("filter").jsonObject)
        val kept = passesFilter(feedItem(case.getValue("item").jsonObject), compileFilter(filter))
        assertEquals(case.getValue("kept").jsonPrimitive.booleanOrNull, kept)
    }

    @TestFactory
    fun merge(): List<DynamicTest> = cases("merge.json") { case ->
        val files = LinkedHashMap<String, DeviceFile>()
        for (element in case.getValue("files").jsonArray) {
            val entry = element.jsonObject
            readDeviceFile(entry["content"] ?: JsonNull)?.let { file -> files[entry["deviceId"].text()] = file }
        }
        assertEquals(case.getValue("expected"), deviceFileJson(mergeDeviceFiles(files)))
    }

    @TestFactory
    fun prune(): List<DynamicTest> = cases("prune.json") { case ->
        val file = checkNotNull(readDeviceFile(case.getValue("file")))
        val now = case.getValue("now").jsonPrimitive.long
        val refreshed = (case["loaded"] as? JsonArray)?.let { loaded -> refreshSeen(file, loaded.texts().toSet(), now) } ?: file
        assertEquals(case.getValue("expected"), deviceFileJson(pruneDeviceFile(refreshed, now)))
    }

    @TestFactory
    fun shorts(): List<DynamicTest> = cases("shorts.json") { case ->
        val videos = case.getValue("videos").jsonArray.map { element ->
            val video = element.jsonObject
            Video(video["videoId"].text(), "UC", "", "", "", "", "", durationSeconds = video["durationSeconds"].intOrNull())
        }
        // a list YouTube says doesn't exist is a channel without Shorts; only one that couldn't be read is unknown
        val failed = (case["shortsListFailed"] as? JsonPrimitive)?.booleanOrNull == true
        val list = if (failed) null else case["shortsList"]?.takeUnless { it is JsonNull }?.jsonArray.orEmpty().mapTo(HashSet()) { id -> id.text() }
        val probeAnswers = case["probe"] as? JsonObject
        var readList = false
        val probed = ArrayList<String>()
        val probe: (suspend (String) -> Boolean?)? = probeAnswers?.let { answers ->
            { videoId ->
                synchronized(probed) { probed.add(videoId) }
                val answer = answers[videoId] ?: throw IllegalStateException("probe failed")
                (answer as? JsonPrimitive)?.booleanOrNull
            }
        }
        val result = runTestResult {
            classifyShorts(videos, {
                readList = true
                list
            }, probe)
        }
        val expected = case.getValue("expected").jsonObject.mapValues { (_, verdict) -> (verdict as? JsonPrimitive)?.booleanOrNull }
        assertEquals(expected, result.associate { video -> video.videoId to video.isShort })
        assertEquals(case.getValue("readsShortsList").jsonPrimitive.booleanOrNull, readList)
        assertEquals(case.getValue("probes").jsonArray.map { id -> id.text() }.sorted(), probed.sorted())
    }

    @TestFactory
    fun setUpStart(): List<DynamicTest> = cases("setup-start.json") { case ->
        fun record(element: JsonElement?): PendingStart? = (element as? JsonObject)?.let { fields ->
            PendingStart(fields["start"].choice(), fields.getValue("cutoff").jsonPrimitive.long, fields["channels"].texts())
        }
        when (case["op"].text()) {
            "keep" -> assertEquals(
                record(case["expected"]),
                pendingStart(case["start"].choice(), case.getValue("cutoff").jsonPrimitive.long, case["channels"].texts()),
            )
            "apply" -> {
                val expected = case.getValue("expected").jsonObject
                val applied = applyStart(record(case["pending"]), case["fetched"].texts(), case.getValue("items").jsonArray.map(::listed))
                assertEquals(expected["marks"].texts(), applied.marks)
                assertEquals(record(expected["pending"]), applied.pending)
            }
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun feedOrder(): List<DynamicTest> = cases("feed-order.json") { case ->
        val expected = case.getValue("expected").jsonArray
        val seed = (case["seed"] as? JsonPrimitive)?.long?.toUInt() ?: 0u
        when (case["op"].text()) {
            "sort" -> {
                val sort = if ("sort" in case) case["sort"].choice<FeedSort>() else FeedSort.NEWEST
                val items = case.getValue("items").jsonArray.map(::listed)
                assertEquals(expected.map { id -> id.text() }, sortFeed(items, sort, seed).map(FeedItem::id))
                assertEquals(expected.map { id -> id.text() }, sortFeed(items.reversed(), sort, seed).map(FeedItem::id), "whatever order they arrive in")
            }
            "hash" -> assertEquals(
                expected.map { hash -> hash.jsonPrimitive.long.toUInt() },
                case.getValue("items").jsonArray.map { item -> shuffleKey(seed, item.jsonObject["id"].text()) },
            )
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun channelOrder(): List<DynamicTest> = cases("channel-order.json") { case ->
        val listed = case.getValue("channels").jsonArray.map(JsonElement::jsonObject)
        val channels = listed.map { channel ->
            defaultFilter(Subscription(channel["id"].text(), channel["title"].text(), ""))
                .copy(enabled = channel.getValue("enabled").jsonPrimitive.booleanOrNull!!)
        }
        val newest = listed.filter { channel -> "newest" in channel }
            .associate { channel -> channel["id"].text() to channel["newest"].text() }
        val unwatched = listed.filter { channel -> "unwatched" in channel }
            .associate { channel -> channel["id"].text() to channel["unwatched"].intOrNull()!! }
        val newestUnwatched = listed.filter { channel -> "newestUnwatched" in channel }
            .associate { channel -> channel["id"].text() to channel["newestUnwatched"].text() }
        val sort = if ("sort" in case) case["sort"].choice<ChannelListOrder>() else ChannelListOrder.NEWEST
        val expected = case.getValue("expected").jsonArray.map { id -> id.text() }
        assertEquals(expected, orderChannels(channels, newest, sort, unwatched, newestUnwatched).map(ChannelFilter::channelId))
        assertEquals(
            expected,
            orderChannels(channels.reversed(), newest, sort, unwatched, newestUnwatched).map(ChannelFilter::channelId),
            "whatever order they arrive in",
        )
    }

    @TestFactory
    fun settings(): List<DynamicTest> = cases("settings.json") { case ->
        val entries = case.getValue("settings").jsonObject.mapValues { (_, entry) -> entry.jsonObject }
        val expected = case.getValue("expected").jsonObject
        assertEquals(
            Settings(
                feedSort = expected["feedSort"].choice(),
                channelSort = expected["channelSort"].choice(),
                autoplay = expected.getValue("autoplay").jsonPrimitive.booleanOrNull!!,
                timeChip = expected["timeChip"].choice(),
                topicChips = expected["topicChips"].texts(),
                channelTimeChip = expected["channelTimeChip"].choice(),
                channelTopicChips = expected["channelTopicChips"].texts(),
                groupChips = expected["groupChips"].texts(),
                channelGroupChips = expected["channelGroupChips"].texts(),
            ),
            readSettings(entries),
        )
        // reading goes through the merge, which must hand every entry on untouched
        val merged = mergeDeviceFiles(mapOf("a" to DeviceFile(settings = entries)))
        assertEquals(entries, merged.settings)
    }

    @TestFactory
    fun feedChips(): List<DynamicTest> = cases("feed-chips.json") { case ->
        val expected = case["expected"].texts()
        val items = case["items"]?.jsonArray.orEmpty().map(::listed)
        val now = (case["now"] as? JsonPrimitive)?.long ?: 0
        when (case["op"].text()) {
            "label" -> assertEquals(
                (case["expected"] as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content,
                topicLabel((case["categoryId"] as? JsonPrimitive)?.content),
            )
            "editor" -> assertEquals(expected, editorTopics(items))
            "chips" -> assertEquals(expected, chipRow(items, case["selected"].texts()))
            "filter" -> assertEquals(
                expected,
                chipFiltered(items, case["timeChip"].choice(), case["topicChips"].texts(), now).map(FeedItem::id),
            )
            "start" -> assertEquals(expected, startMarks(items, case["start"].choice(), now))
            "groupFilter" -> {
                val kept = groupKeptChannels(groupedChannels(case["channelGroups"]), case["groupChips"].texts())
                val grouped = items.filter { item -> kept == null || item.channelId in kept }
                assertEquals(expected, chipFiltered(grouped, case["timeChip"].choice(), case["topicChips"].texts(), now).map(FeedItem::id))
            }
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun channelChips(): List<DynamicTest> = cases("channel-chips.json") { case ->
        val expected = case["expected"].texts()
        val items = case.getValue("items").jsonArray.map(::listed)
        when (case["op"].text()) {
            "chips" -> assertEquals(expected, chipRow(items, case["selected"].texts()))
            "channels" -> {
                val kept = keptByBoth(
                    groupKeptChannels(groupedChannels(case["channelGroups"]), case["groupChips"].texts()),
                    chipKeptChannels(items, case["timeChip"].choice(), case["topicChips"].texts(), case.getValue("now").jsonPrimitive.long),
                )
                assertEquals(expected, listedOrder(case["channels"].texts(), kept))
            }
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun groups(): List<DynamicTest> = cases("groups.json") { case ->
        val selections = (case["settings"] as? JsonObject).let { settings ->
            GroupSelections(settings?.get("groupChips").texts(), settings?.get("channelGroupChips").texts())
        }
        val saved = savedFilters(case["saved"])
        val listed = case["listed"].texts()
        fun assertEdit(edit: GroupEdit) {
            val expected = case.getValue("expected").jsonObject
            assertEquals(expected.getValue("channels"), JsonObject(edit.channels.mapValues { (_, filter) -> filterToJson(filter) }))
            assertEquals(
                expected.getValue("settings"),
                JsonObject(edit.settings.mapValues { (_, names) -> JsonArray(names.map(::JsonPrimitive)) }),
            )
        }
        when (case["op"].text()) {
            "name" -> assertEquals((case["expected"] as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content, groupName(case["text"].text()))
            "groups" -> assertEquals(case["expected"].texts(), groupNames(savedFilters(case["channels"]).values))
            "title" -> {
                val title = chipTitle(case["groups"].texts(), case["groupChips"].texts(), case["topics"].texts(), case["topicChips"].texts())
                val expected = case.getValue("expected").jsonObject
                assertEquals(expected["names"].texts(), title.names)
                assertEquals((expected["edit"] as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content, title.edit)
            }
            "members" -> assertEdit(
                setMembers(saved, listed, selections, case["channelIds"].texts(), case["group"].text(), case.getValue("member").jsonPrimitive.booleanOrNull!!),
            )
            "rename" -> assertEdit(renameGroup(saved, selections, case["from"].text(), case["to"].text()))
            "delete" -> assertEdit(deleteGroup(saved, selections, case["group"].text()))
            "save" -> assertEdit(
                saveGroup(
                    saved,
                    listed,
                    selections,
                    (case["group"] as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content,
                    case["to"].text(),
                    case["members"].texts(),
                ),
            )
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun player(): List<DynamicTest> = cases("player.json") { case ->
        fun entry(id: String): FeedItem = Video(id, "UC", "", id, "", "", "")
        when (case["op"].text()) {
            "next" -> {
                val mode = WatchedMode.valueOf(case["mode"].text().uppercase())
                val next = nextInQueue(
                    PlayQueue(case["items"].texts().map(::entry), mode),
                    case["ended"].text(),
                    case["watched"].texts().toSet(),
                    case.getValue("autoplay").jsonPrimitive.booleanOrNull!!,
                )
                assertEquals((case["expected"] as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content, next?.id)
            }
            "end" -> {
                val outcome = endOutcome(
                    case["place"].choice(),
                    entry("next").takeIf { case.getValue("next").jsonPrimitive.booleanOrNull!! },
                    case.getValue("nextCardShowing").jsonPrimitive.booleanOrNull!!,
                )
                val expected = case.getValue("expected").jsonObject
                val shown = when (outcome) {
                    is EndOutcome.Next -> mapOf("kind" to "next", "place" to outcome.place.wire)
                    EndOutcome.Stay -> mapOf("kind" to "stay")
                    EndOutcome.Close -> mapOf("kind" to "close")
                }
                assertEquals(expected.mapValues { (_, value) -> value.text() }, shown)
            }
            "minimizedSize" -> {
                val expected = case.getValue("expected").jsonObject
                assertEquals(
                    PlayerSize(expected["width"].intOrNull()!!, expected["height"].intOrNull()!!),
                    minimizedSize(case["viewWidth"].intOrNull()!!),
                )
            }
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun watchProgress(): List<DynamicTest> = cases("watch-progress.json") { case ->
        val entry = case["entry"] as? JsonObject
        val duration = (case["duration"] as? JsonPrimitive)?.content?.toDouble() ?: 0.0
        val expected = (case["expected"] as? JsonPrimitive)?.takeUnless { it is JsonNull }
        when (case["op"].text()) {
            "watched" -> assertEquals(expected?.booleanOrNull, isWatchedEntry(entry, duration))
            "resume" -> assertEquals(expected?.content?.toDouble(), resumePosition(entry, duration))
            "bar" -> assertEquals(expected?.content?.toDouble(), progressFraction(entry, duration))
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun phrases(): List<DynamicTest> = cases("phrases.json") { case ->
        val pattern = case["pattern"].text()
        when (case["op"].text()) {
            "build" -> {
                assertEquals(pattern, phrasesToPattern(case["phrases"].texts()))
                assertTrue(isValidPattern(pattern), "valid")
                assertEquals(case["canonical"].texts(), patternToPhrases(pattern))
                for (element in case["matches"]?.jsonArray.orEmpty()) {
                    val check = element.jsonObject
                    val regex = checkNotNull(compilePattern(pattern, check.getValue("caseSensitive").jsonPrimitive.booleanOrNull!!))
                    assertEquals(check.getValue("matches").jsonPrimitive.booleanOrNull, regex.containsMatchIn(check["text"].text()), check["text"].text())
                }
            }
            "parse" -> assertEquals((case["expected"] as? JsonArray)?.map { phrase -> phrase.text() }, patternToPhrases(pattern))
            else -> error("unknown op in ${case.name}")
        }
    }

    @TestFactory
    fun deviceFiles(): List<DynamicTest> =
        File(shared, "fixtures/device-files").listFiles { file -> file.extension == "json" }.orEmpty().sortedBy(File::getName).map { file ->
            DynamicTest.dynamicTest(file.name) {
                val problems = deviceFileProblems(Json.parseToJsonElement(file.readText()))
                if (file.name.startsWith("valid-")) {
                    assertEquals(emptyList(), problems)
                    // a reader keeps every field when it writes the file back
                    val read = checkNotNull(readDeviceFile(Json.parseToJsonElement(file.readText())))
                    assertEquals(Json.parseToJsonElement(file.readText()), deviceFileJson(read))
                } else {
                    assertTrue(problems.isNotEmpty(), "${file.name} should break the schema")
                }
            }
        }
}

private fun <Result> runTestResult(block: suspend () -> Result): Result {
    var result: Result? = null
    runTest { result = block() }
    @Suppress("UNCHECKED_CAST")
    return result as Result
}
