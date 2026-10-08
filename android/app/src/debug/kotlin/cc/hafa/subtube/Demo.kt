package cc.hafa.subtube

import android.content.Intent
import cc.hafa.subtube.core.ChannelFilter
import cc.hafa.subtube.core.ChannelSummary
import cc.hafa.subtube.core.ContentMode
import cc.hafa.subtube.core.DriveUser
import cc.hafa.subtube.core.FeedItem
import cc.hafa.subtube.core.FilterMode
import cc.hafa.subtube.core.LiveFilter
import cc.hafa.subtube.core.LiveStatus
import cc.hafa.subtube.core.Playlist
import cc.hafa.subtube.core.Settings
import cc.hafa.subtube.core.ShortsFilter
import cc.hafa.subtube.core.Subscription
import cc.hafa.subtube.core.Video
import cc.hafa.subtube.core.STARTING_WATCHED_MODE
import cc.hafa.subtube.core.WATCHED_CHIP_MODES
import cc.hafa.subtube.core.WatchedMode
import cc.hafa.subtube.core.defaultFilter
import cc.hafa.subtube.core.phrasesToPattern
import cc.hafa.subtube.ui.DemoData
import cc.hafa.subtube.ui.Screen
import cc.hafa.subtube.ui.SetUpStep
import cc.hafa.subtube.ui.SubtubeViewModel
import java.time.LocalDate

private const val EXTRA_DEMO = "demo"
private const val EXTRA_SCREEN = "screen"
private const val EXTRA_STEP = "step"
private const val EXTRA_CHANNEL = "channel"
private const val EXTRA_LOADING = "loading"
private const val EXTRA_WATCHED = "watched"

private enum class DemoKind { VIDEO, SHORT, PLAYLIST }

/**
 * One demo entry: title, channel, seconds (or a playlist's video count), day counted from 1 September 2026, watched, kind,
 * YouTube category id, and how many seconds of it have been played.
 */
private data class DemoRow(
    val title: String,
    val channel: String,
    val size: Int,
    val day: Long,
    val watched: Boolean = false,
    val kind: DemoKind = DemoKind.VIDEO,
    val category: String? = "26",
    val played: Long? = null,
)

// the same channels and entries as the Apple apps' `-demo`, so screenshots compare
private val CHANNEL_NAMES = listOf("One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight")

private val ROWS = listOf(
    DemoRow("Woodworking Basics — Episode 12", "One", 1122, 24, watched = true),
    DemoRow("Weekly Q&A, September (replay)", "Two", 3735, 25, watched = true),
    DemoRow("Building a Shop Cart", "Three", 1450, 26, played = 1100),
    DemoRow("Woodworking Basics — Episode 13", "One", 1267, 27),
    DemoRow("Garden Projects 2026", "Four", 14, 28, kind = DemoKind.PLAYLIST),
    DemoRow("Sharpening Without a Jig", "Five", 598, 29, category = "27"),
    DemoRow("Quick tip: clamping odd shapes", "Two", 48, 30, kind = DemoKind.SHORT),
    DemoRow("Kitchen Remodel, Part 4", "Six", 1964, 31),
    DemoRow("Trip Notes: Lake Day", "Three", 920, 32, category = "19"),
    DemoRow("Woodworking Basics — Episode 14", "One", 1195, 33, played = 420),
    DemoRow("Tool Review: Block Planes", "Five", 1651, 34, category = "28", played = 200),
    DemoRow("Night Sky, October", "Seven", 668, 35, category = "28"),
    DemoRow("Shop update and Q&A", "One", 4360, 20),
)

// the groups of the approved mockups
private val GROUPS = mapOf("Woodworking" to setOf("One", "Three", "Five"), "Evenings" to setOf("Two", "Six"))

private fun demoChannel(name: String): ChannelFilter {
    val channel = defaultFilter(Subscription("UC$name", "Channel $name", ""))
        .copy(groups = GROUPS.filterValues { members -> name in members }.keys.toList())
    return when (name) {
        "One" -> channel.copy(regex = phrasesToPattern(listOf("Episode", "Q&A")), mode = FilterMode.INCLUDE, topics = listOf("26"))
        "Two" -> channel.copy(shortsFilter = ShortsFilter.NORMAL)
        "Four" -> channel.copy(contentMode = ContentMode.PLAYLISTS)
        "Five" -> channel.copy(minDurationSeconds = 60)
        "Six" -> channel.copy(liveFilter = LiveFilter.NORMAL)
        "Seven" -> channel.copy(enabled = false)
        "Eight" -> channel.copy(followed = true)
        else -> channel
    }
}

private fun demoItem(index: Int, row: DemoRow): FeedItem {
    val publishedAt = "${LocalDate.of(2026, 9, 1).plusDays(row.day - 1)}T00:00:00Z"
    return if (row.kind == DemoKind.PLAYLIST) {
        Playlist(
            playlistId = "demo$index",
            channelId = "UC${row.channel}",
            channelTitle = "Channel ${row.channel}",
            title = row.title,
            description = "",
            publishedAt = publishedAt,
            thumbnail = "",
            itemCount = row.size,
        )
    } else {
        Video(
            videoId = "demo$index",
            channelId = "UC${row.channel}",
            channelTitle = "Channel ${row.channel}",
            title = row.title,
            description = "",
            publishedAt = publishedAt,
            thumbnail = "",
            durationSeconds = row.size,
            liveStatus = LiveStatus.NORMAL,
            isShort = row.kind == DemoKind.SHORT,
            categoryId = row.category,
        )
    }
}

/**
 * Show the app on made-up data when the launch asks for it, with no sign-in
 * and nothing loaded or synced (debug builds only).
 *
 * `adb shell am start -S -n cc.hafa.subtube/.MainActivity --ez demo true`
 * opens the feed. `--es screen` picks `feed`, `channels`, `settings`,
 * `channel` (with `--es channel UCOne` … `UCEight`), `player` (the feed with
 * its first unwatched card playing in place), `minimized` (the same with the
 * player in the corner) or `setup` (with `--es step`
 * naming a [SetUpStep] in lower case: `intro`, `sign_in`, `channels`,
 * `shorts`, `start`, `done`). `--es loading first` or `reload` shows a load
 * running: skeleton cards, or the feed greyed out. `--es watched watched` sets
 * the watched chip.
 */
internal fun showDemoIfAsked(intent: Intent, viewModel: SubtubeViewModel) {
    if (intent.getBooleanExtra(EXTRA_DEMO, false)) {
        val step = SetUpStep.entries.firstOrNull { entry -> entry.name.equals(intent.getStringExtra(EXTRA_STEP), ignoreCase = true) }
        viewModel.showDemo(
            demoData(
                screen = intent.getStringExtra(EXTRA_SCREEN) ?: "feed",
                step = step ?: SetUpStep.INTRO,
                channelId = intent.getStringExtra(EXTRA_CHANNEL) ?: "UCOne",
                loading = DemoLoading.entries.firstOrNull { entry -> entry.name.equals(intent.getStringExtra(EXTRA_LOADING), ignoreCase = true) }
                    ?: DemoLoading.NONE,
                watchedMode = WATCHED_CHIP_MODES.firstOrNull { entry -> entry.name.equals(intent.getStringExtra(EXTRA_WATCHED), ignoreCase = true) }
                    ?: STARTING_WATCHED_MODE,
            ),
        )
    }
}

/** Which load the demo shows running. */
internal enum class DemoLoading {
    NONE,

    /** The first load: nothing to show yet. */
    FIRST,

    /** A reload over the feed already shown. */
    RELOAD,
}

/**
 * The made-up data opened on [screen] (see [showDemoIfAsked] for the names),
 * at [step] of first run or on [channelId]'s page, with [loading] shown
 * running, the watched chip on [watchedMode] and the chips showing [settings].
 */
internal fun demoData(
    screen: String = "feed",
    step: SetUpStep = SetUpStep.INTRO,
    channelId: String = "UCOne",
    loading: DemoLoading = DemoLoading.NONE,
    watchedMode: WatchedMode = STARTING_WATCHED_MODE,
    settings: Settings = Settings(),
): DemoData {
    val signedOut = screen == "setup" && step <= SetUpStep.SIGN_IN
    return DemoData(
        account = if (signedOut) null else ChannelSummary(channelId = "UCdemo", title = "Your Name", thumbnail = "", handle = null),
        user = DriveUser("Your Name", "you@example.com"),
        subscriptions = CHANNEL_NAMES.filter { name -> name != "Eight" }.map { name -> Subscription("UC$name", "Channel $name", "") },
        channels = CHANNEL_NAMES.map(::demoChannel),
        items = if (loading == DemoLoading.FIRST) emptyList() else ROWS.mapIndexed(::demoItem),
        watched = ROWS.indices.filter { index -> ROWS[index].watched }.mapTo(HashSet()) { index -> "demo$index" },
        positions = ROWS.withIndex().mapNotNull { (index, row) -> row.played?.let { seconds -> "demo$index" to seconds } }.toMap(),
        settings = settings,
        watchedMode = watchedMode,
        step = step.takeIf { screen == "setup" },
        screens = when (screen) {
            "channels" -> listOf(Screen.Feed, Screen.Channels)
            "settings" -> listOf(Screen.Feed, Screen.Settings)
            "channel" -> listOf(Screen.Feed, Screen.ChannelPage(channelId))
            else -> listOf(Screen.Feed)
        },
        play = screen == "player" || screen == "minimized",
        minimized = screen == "minimized",
        loading = loading != DemoLoading.NONE,
    )
}
