package cc.hafa.subtube.core

/** Which of watched and unwatched entries a page lists, in the order the watched chip moves through them. */
enum class WatchedMode { UNWATCHED, WATCHED, ALL }

/** The watched mode every visit starts on. */
val STARTING_WATCHED_MODE: WatchedMode = WatchedMode.UNWATCHED

/** The modes the watched chip offers, in the order it moves through them; nothing in the app reaches [WatchedMode.ALL]. */
val WATCHED_CHIP_MODES: List<WatchedMode> = listOf(WatchedMode.UNWATCHED, WatchedMode.WATCHED)

/** Whether the time or watched chip is off where it starts, which is when the menu holding them is drawn selected. */
fun menuNarrows(mode: WatchedMode, timeChip: TimeChip): Boolean = mode != STARTING_WATCHED_MODE || timeChip != TimeChip.NONE

/**
 * The entries a watched mode lists, in the order given. An entry in [staying],
 * one that changed sides while it was on screen, is listed in every mode.
 */
fun modeFiltered(items: Collection<FeedItem>, mode: WatchedMode, watched: Set<String>, staying: Set<String>): List<FeedItem> =
    items.filter { item ->
        mode == WatchedMode.ALL || (item.id in watched) == (mode == WatchedMode.WATCHED) || item.id in staying
    }

/** Whether auto-play moves on in [mode]: not among watched entries only. */
fun autoplayAdvances(mode: WatchedMode): Boolean = mode != WatchedMode.WATCHED

/**
 * Whether an empty list is empty because of what is selected, rather than
 * because nothing is left to watch: any mode but unwatched, a time chip, a
 * topic chip, or ([grouped]) an existing group's chip.
 */
fun emptiedBySelection(mode: WatchedMode, timeChip: TimeChip, topicChips: Collection<String>, grouped: Boolean = false): Boolean =
    mode != WatchedMode.UNWATCHED || timeChip != TimeChip.NONE || knownTopics(topicChips).isNotEmpty() || grouped
