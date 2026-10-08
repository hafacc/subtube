package cc.hafa.subtube.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/** A dot of radius [radius] at ([centerX], [centerY]), as path data. */
private fun circle(centerX: Float, centerY: Float, radius: Float): String =
    "M${centerX - radius},$centerY a$radius,$radius 0 1,0 ${radius * 2},0 a$radius,$radius 0 1,0 ${-radius * 2},0"

/** A 24dp outline icon from SVG path data, stroked like the mockups' Material Symbols. */
private fun strokeIcon(name: String, vararg paths: String, filled: List<String> = emptyList()): ImageVector =
    ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
        for (data in paths) {
            addPath(
                pathData = addPathNodes(data),
                stroke = SolidColor(Color.Black),
                strokeLineWidth = 1.75f,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
        for (data in filled) {
            addPath(pathData = addPathNodes(data), fill = SolidColor(Color.Black))
        }
    }.build()

/** The icons the mockups draw, tinted by `Icon` like any Material icon. */
object SubtubeIcons {
    /** Clear a selection. */
    val Close: ImageVector = strokeIcon("Close", "M6 6l12 12", "M18 6 6 18")

    /** Channel filters. */
    val Filters: ImageVector = strokeIcon("Filters", "M4 7h16", "M7 12h10", "M10 17h4")

    /** Watched state. */
    val Eye: ImageVector = strokeIcon("Eye", "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z", circle(12f, 12f, 3f))

    /** Not watched: the eye struck through. */
    val EyeOff: ImageVector = strokeIcon("EyeOff", "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z", circle(12f, 12f, 3f), "M4 4l16 16")

    /** A playlist. */
    val PlaylistPlay: ImageVector = strokeIcon("PlaylistPlay", "M3 6h13", "M3 12h9", "M3 18h7", "M16 13v8l6-4z")

    /** The Feed tab. */
    val Feed: ImageVector = strokeIcon("Feed", "M5 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z", "M6 4h12", "m10.5 10.5 4 3-4 3z")

    /** The Channels tab. */
    val Channels: ImageVector = strokeIcon(
        "Channels",
        "M9 3h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z",
        "M3 7v12a2 2 0 0 0 2 2h12",
        "m12.5 7.5 3.5 2.5-3.5 2.5z",
    )

    /** The Settings tab. */
    val Settings: ImageVector = strokeIcon(
        "Settings",
        "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z",
        circle(12f, 12f, 3f),
    )

    /** Back. */
    val ArrowBack: ImageVector = strokeIcon("ArrowBack", "M19 12H5", "m12 19-7-7 7-7")

    /** Search. */
    val Search: ImageVector = strokeIcon("Search", circle(11f, 11f, 7f), "m20 20-3.5-3.5")

    /** A selected option or a done state. */
    val Check: ImageVector = strokeIcon("Check", "M20 6 9 17l-5-5")


    /** Synced to the cloud. */
    val CloudDone: ImageVector = strokeIcon("CloudDone", "M17.5 19H7a5 5 0 1 1 1.1-9.9A6 6 0 0 1 19.5 11a4 4 0 0 1-2 8z", "m9 14 2 2 4-4")

    /** Sign out. */
    val Logout: ImageVector = strokeIcon("Logout", "M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3", "m10 17 5-5-5-5", "M15 12H3")

    /** YouTube subscriptions. */
    val Subscriptions: ImageVector = strokeIcon("Subscriptions", "M4 7h16a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z", "m17 2-5 5-5-5")

    /** A Drive folder. */
    val Folder: ImageVector = strokeIcon(
        "Folder",
        "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z",
    )

    /** The feed's sort and filter menu: three sliders. */
    val Sliders: ImageVector = strokeIcon(
        "Sliders",
        "M21 4h-7", "M10 4H3", "M21 12h-9", "M8 12H3", "M21 20h-5", "M12 20H3", "M14 2v4", "M8 10v4", "M16 18v4",
    )

    /** A new group. */
    val Add: ImageVector = strokeIcon("Add", "M12 5v14", "M5 12h14")

    /** Edit a group. */
    val Edit: ImageVector = strokeIcon("Edit", "M4 20h4L19 9l-4-4L4 16v4z", "M13 7l4 4")

    /** Return the minimized player to its card: an arrow leaving the small screen in a large one's corner. */
    val Expand: ImageVector = strokeIcon(
        "Expand",
        "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z", "M12 12 7.5 8.5", "M7.5 12V8.5H11",
        filled = listOf("M14 12.5h4a1 1 0 0 1 1 1V16a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-2.5a1 1 0 0 1 1-1z"),
    )

    /** The player's play glyph, filled. */
    val PlayFilled: ImageVector = strokeIcon("PlayFilled", filled = listOf("M8 5.5v13l10.5-6.5z"))
}
