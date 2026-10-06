package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** The names the synced settings are saved under in a device file's `settings`. */
object SettingName {
    /** A [FeedSort]. */
    const val FEED_SORT: String = "feedSort"

    /** A [ChannelSort]. */
    const val CHANNEL_SORT: String = "channelSort"

    /** A boolean. */
    const val AUTOPLAY: String = "autoplay"

    /** A [TimeChip]. */
    const val TIME_CHIP: String = "timeChip"

    /** An array of YouTube category ids. */
    const val TOPIC_CHIPS: String = "topicChips"

    /** A [TimeChip], the channel list's. */
    const val CHANNEL_TIME_CHIP: String = "channelTimeChip"

    /** An array of YouTube category ids, the channel list's. */
    const val CHANNEL_TOPIC_CHIPS: String = "channelTopicChips"

    /** An array of group names. */
    const val GROUP_CHIPS: String = "groupChips"

    /** An array of group names, the channel list's. */
    const val CHANNEL_GROUP_CHIPS: String = "channelGroupChips"
}

/** The settings synced through the Drive file, as this version reads them; the defaults are what a missing or unknown value reads as. */
data class Settings(
    /** The feed's order. */
    val feedSort: FeedSort = FeedSort.NEWEST,
    /** The channel list's order. */
    val channelSort: ChannelSort = ChannelSort.NEWEST,
    /** Whether the next unwatched entry plays when one ends. */
    val autoplay: Boolean = false,
    /** The selected time chip. */
    val timeChip: TimeChip = TimeChip.NONE,
    /** The selected topic chips' category ids, as written: unsorted, repeats kept. */
    val topicChips: List<String> = emptyList(),
    /** The channel list's selected time chip. */
    val channelTimeChip: TimeChip = TimeChip.NONE,
    /** The channel list's selected topic chips' category ids, as written. */
    val channelTopicChips: List<String> = emptyList(),
    /** The selected group chips' names, as written. */
    val groupChips: List<String> = emptyList(),
    /** The channel list's selected group chips' names, as written. */
    val channelGroupChips: List<String> = emptyList(),
)

private inline fun <reified Choice> choiceOrNull(value: JsonElement?): Choice? where Choice : Enum<Choice>, Choice : WireValue {
    val wire = value.stringOrNull()
    return enumValues<Choice>().firstOrNull { choice -> choice.wire == wire }
}

/**
 * The settings in a merged view's `settings` map (shared/fixtures/settings.json).
 *
 * [entries] are whole entries (`{at, value}`) by setting name. A setting that
 * is missing, or whose value is anything but what the setting allows, reads as
 * its default; names not in [SettingName] are ignored.
 */
fun readSettings(entries: Map<String, JsonObject>): Settings {
    fun value(name: String): JsonElement? = entries[name]?.get("value")
    val defaults = Settings()
    val autoplay = value(SettingName.AUTOPLAY).booleanValue()
    return Settings(
        feedSort = choiceOrNull<FeedSort>(value(SettingName.FEED_SORT)) ?: defaults.feedSort,
        channelSort = choiceOrNull<ChannelSort>(value(SettingName.CHANNEL_SORT)) ?: defaults.channelSort,
        autoplay = autoplay ?: defaults.autoplay,
        timeChip = choiceOrNull<TimeChip>(value(SettingName.TIME_CHIP)) ?: defaults.timeChip,
        topicChips = value(SettingName.TOPIC_CHIPS).stringsOrNull() ?: defaults.topicChips,
        channelTimeChip = choiceOrNull<TimeChip>(value(SettingName.CHANNEL_TIME_CHIP)) ?: defaults.channelTimeChip,
        channelTopicChips = value(SettingName.CHANNEL_TOPIC_CHIPS).stringsOrNull() ?: defaults.channelTopicChips,
        groupChips = value(SettingName.GROUP_CHIPS).stringsOrNull() ?: defaults.groupChips,
        channelGroupChips = value(SettingName.CHANNEL_GROUP_CHIPS).stringsOrNull() ?: defaults.channelGroupChips,
    )
}
