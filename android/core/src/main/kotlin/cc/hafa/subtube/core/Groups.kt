package cc.hafa.subtube.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** The most code points a group's name has. */
const val GROUP_NAME_MAX: Int = 24

// Unicode's White_Space code points, spelled out so every client trims alike
private const val SPACE = "\\u0009-\\u000d\\u0020\\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000"
private val OUTER_SPACE = Regex("^[$SPACE]+|[$SPACE]+$")

/**
 * Typed text as a group's name (shared/fixtures/groups.json): white space at
 * either end removed; null unless 1 to [GROUP_NAME_MAX] code points are left.
 */
fun groupName(text: String): String? {
    val name = OUTER_SPACE.replace(text, "")
    return name.takeIf { name.codePointCount(0, name.length) in 1..GROUP_NAME_MAX }
}

/**
 * The groups a stored filter's `groups` value puts its channel in, each once,
 * in the order written: its strings that are a name as they stand. A value
 * that is not an array, or holds anything but strings, is none.
 */
fun groupsFromJson(stored: JsonElement?): List<String> {
    val names = (stored as? JsonArray)?.map { element -> (element as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content }
    return if (names == null || null in names) {
        emptyList()
    } else {
        names.filterNotNull().filter { name -> groupName(name) == name }.distinct()
    }
}

/** Order group names as their chips go: ignoring case, then by code point. */
val groupNameOrder: Comparator<String> = ignoringCase.thenComparing(::compareCodePoints)

/** The groups that exist, in chip order: every name one of [listed], the listed channels' filters, has. */
fun groupNames(listed: Collection<ChannelFilter>): List<String> =
    listed.flatMapTo(LinkedHashSet(), ChannelFilter::groups).sortedWith(groupNameOrder)

/** The names of [selected] that are among [existing], in [existing]'s order. */
fun selectedGroups(existing: List<String>, selected: Collection<String>): List<String> = existing.filter { name -> name in selected }

/** What stands in a chip row's title while it has groups or topics selected. */
data class ChipTitle(
    /** The selected groups' names, then the selected topics' labels; empty for the usual title. */
    val names: List<String>,
    /** The group the title's "Edit group" button opens: the only selected one, else null. */
    val edit: String?,
)

/**
 * A chip row's title: its selected existing groups, then its selected topics,
 * each in chip order. [groups] and [topics] are the row's group and topic
 * chips in order, [groupChips] and [topicChips] its two settings.
 */
fun chipTitle(groups: List<String>, groupChips: Collection<String>, topics: List<String>, topicChips: Collection<String>): ChipTitle {
    val selected = selectedGroups(groups, groupChips)
    return ChipTitle(
        names = selected + topics.filter { categoryId -> categoryId in topicChips }.mapNotNull(::topicLabel),
        edit = selected.singleOrNull(),
    )
}

/**
 * The channels the selected groups keep, by id: those of [listed] in any
 * existing group among [selected]. Null when none is selected, which keeps
 * every channel.
 */
fun groupKeptChannels(listed: Collection<ChannelFilter>, selected: Collection<String>): Set<String>? {
    val wanted = selectedGroups(groupNames(listed), selected).toSet()
    return if (wanted.isEmpty()) {
        null
    } else {
        listed.filter { filter -> filter.groups.any { name -> name in wanted } }.mapTo(LinkedHashSet(), ChannelFilter::channelId)
    }
}

/** The ids two sets of kept channels both keep; null, which keeps all, when both are. */
fun keptByBoth(left: Set<String>?, right: Set<String>?): Set<String>? =
    if (left == null || right == null) {
        left ?: right
    } else {
        left.filterTo(LinkedHashSet()) { channelId -> channelId in right }
    }

/** The selected group chips of both rows, as the settings hold them. */
data class GroupSelections(
    /** The feed's row. */
    val groupChips: List<String> = emptyList(),
    /** The channel list's row. */
    val channelGroupChips: List<String> = emptyList(),
)

/** What a group edit saves. */
data class GroupEdit(
    /** Each changed channel's whole filter, by channel id. */
    val channels: Map<String, ChannelFilter> = emptyMap(),
    /** Each changed setting's new value, by [SettingName]. */
    val settings: Map<String, List<String>> = emptyMap(),
)

/** Every filter of [saved] that [change] gives other groups, with the groups it gives. */
private fun regrouped(saved: Map<String, ChannelFilter>, change: (List<String>) -> List<String>): Map<String, ChannelFilter> {
    val changed = LinkedHashMap<String, ChannelFilter>()
    for ((channelId, filter) in saved) {
        val next = change(filter.groups)
        if (next != filter.groups) {
            changed[channelId] = filter.copy(groups = next)
        }
    }
    return changed
}

private fun reselected(selections: GroupSelections, change: (List<String>) -> List<String>): Map<String, List<String>> {
    val changed = LinkedHashMap<String, List<String>>()
    for ((setting, selected) in listOf(SettingName.GROUP_CHIPS to selections.groupChips, SettingName.CHANNEL_GROUP_CHIPS to selections.channelGroupChips)) {
        val next = change(selected)
        if (next != selected) {
            changed[setting] = next
        }
    }
    return changed
}

/**
 * Delete a group: its name leaves every saved filter that has it and both
 * settings. [saved] is every saved filter by channel id, listed or not.
 */
fun deleteGroup(saved: Map<String, ChannelFilter>, selections: GroupSelections, group: String): GroupEdit {
    val without = { names: List<String> -> names.filter { name -> name != group } }
    return GroupEdit(regrouped(saved, without), reselected(selections, without))
}

/**
 * Rename a group on every saved filter that has it and in both settings; a
 * filter or setting that already has the new name keeps it once, where it
 * came first. Nothing changes unless [to] is a name other than [from].
 */
fun renameGroup(saved: Map<String, ChannelFilter>, selections: GroupSelections, from: String, to: String): GroupEdit =
    if (groupName(to) != to || from == to) {
        GroupEdit()
    } else {
        val renamed = { names: List<String> ->
            if (from in names) {
                val moved = names.map { name -> if (name == from) to else name }
                val first = moved.indexOf(to)
                moved.filterIndexed { index, name -> name != to || index == first }
            } else {
                names
            }
        }
        GroupEdit(regrouped(saved, renamed), reselected(selections, renamed))
    }

/**
 * Put channels in a group, or take them out. A channel with no saved filter
 * gets the default one; a new name goes last in the filter's groups. Taking
 * out the last of the [listed] channels in the group deletes it
 * ([deleteGroup]).
 */
fun setMembers(
    saved: Map<String, ChannelFilter>,
    listed: Collection<String>,
    selections: GroupSelections,
    channelIds: Collection<String>,
    group: String,
    member: Boolean,
): GroupEdit =
    if (groupName(group) != group) {
        GroupEdit()
    } else {
        val channels = LinkedHashMap<String, ChannelFilter>()
        for (channelId in channelIds) {
            val filter = saved[channelId] ?: defaultFilter(Subscription(channelId, channelId, ""))
            if ((group in filter.groups) != member) {
                channels[channelId] = filter.copy(groups = if (member) filter.groups + group else filter.groups - group)
            }
        }
        val after = saved + channels
        if (member || listed.any { channelId -> group in after[channelId]?.groups.orEmpty() }) {
            GroupEdit(channels)
        } else {
            val deleted = deleteGroup(after, selections, group)
            GroupEdit(channels + deleted.channels, deleted.settings)
        }
    }

/**
 * What the group editor's "Save" writes, as one edit: the [listed] channels
 * in the group become exactly [members], then the group takes [name]
 * ([renameGroup], which merges into a group that has it already). [group] is
 * the edited group, or null for a new one, whose members are put in [name].
 * Nothing changes unless [name] is a name and [members] has a channel.
 */
fun saveGroup(
    saved: Map<String, ChannelFilter>,
    listed: Collection<String>,
    selections: GroupSelections,
    group: String?,
    name: String,
    members: Collection<String>,
): GroupEdit =
    if (groupName(name) != name || members.isEmpty()) {
        GroupEdit()
    } else if (group == null) {
        setMembers(saved, listed, selections, members, name, member = true)
    } else {
        val added = setMembers(saved, listed, selections, members, group, member = true)
        val withAdded = saved + added.channels
        val removed = setMembers(withAdded, listed, selections, listed.filter { channelId -> channelId !in members }, group, member = false)
        val renamed = renameGroup(withAdded + removed.channels, selections, group, name)
        GroupEdit(added.channels + removed.channels + renamed.channels, renamed.settings)
    }
