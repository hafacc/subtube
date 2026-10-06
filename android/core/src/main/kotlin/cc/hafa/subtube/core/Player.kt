package cc.hafa.subtube.core

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Where the one player is drawn. */
enum class PlayerPlace(override val wire: String) : WireValue {
    /** Over the dimmed app. This app never puts the player there; it is kept for shared/fixtures/player.json. */
    LARGE("large"),

    /** In place of its card's thumbnail. */
    CARD("card"),

    /** In the screen's bottom corner. */
    MINIMIZED("minimized"),
}

/** The list a video was started from, as it was then. */
data class PlayQueue(
    /** The page's entries, in the order shown. */
    val items: List<FeedItem>,
    /** The watched chip's choice. */
    val mode: WatchedMode,
)

/** What the one player is playing. */
data class Playing(
    /** The video or playlist. */
    val item: FeedItem,
    /** Where it is drawn. */
    val place: PlayerPlace,
    /** The page it was started from: a channel's id, or null for the feed. */
    val page: String?,
    /** The list it was started from. */
    val queue: PlayQueue,
)

/** The smallest player YouTube allows, in dp each way. */
const val MIN_PLAYER_SIDE: Int = 200

/** The width of the minimized player where the screen has room for it, in dp. */
const val MINIMIZED_WIDTH: Int = 356

/** The gap between the minimized player and the screen's edges, in dp. */
const val MINIMIZED_MARGIN: Int = 16

/**
 * What auto-play plays after [endedId] (shared/fixtures/player.json, `next`):
 * the next unwatched entry after it in the list the video was started from,
 * whatever page is showing now. Null with [autoplay] off, when that list was
 * the watched entries only, at its end, or when the ended entry isn't in it.
 */
fun nextInQueue(queue: PlayQueue, endedId: String, watched: Set<String>, autoplay: Boolean): FeedItem? =
    if (autoplay && autoplayAdvances(queue.mode)) nextUnwatched(queue.items, endedId, watched) else null

/** What the end of the playing entry does to the player. */
sealed interface EndOutcome {
    /** [item] plays next, in [place]. */
    data class Next(val item: FeedItem, val place: PlayerPlace) : EndOutcome

    /** The player stays where it is, stopped on the ended entry, until it is closed or expanded. */
    data object Stay : EndOutcome

    /** The player is removed. */
    data object Close : EndOutcome
}

/**
 * What the end of an entry does to a player in [place]
 * (shared/fixtures/player.json, `end`). [next] plays where the player is,
 * except that a card not on the page showing ([nextCardShowing] false) can't
 * hold it. With nothing next, a card's player closes and any other stays.
 */
fun endOutcome(place: PlayerPlace, next: FeedItem?, nextCardShowing: Boolean): EndOutcome =
    if (next != null) {
        EndOutcome.Next(next, if (place == PlayerPlace.CARD && !nextCardShowing) PlayerPlace.MINIMIZED else place)
    } else if (place == PlayerPlace.CARD) {
        EndOutcome.Close
    } else {
        EndOutcome.Stay
    }

/** A size in dp. */
data class PlayerSize(
    /** How wide. */
    val width: Int,
    /** How high. */
    val height: Int,
)

/**
 * The minimized player's video in a screen [viewWidth] dp wide
 * (shared/fixtures/player.json, `minimizedSize`): 356 by 200, or as wide as
 * the screen less its margins when that is less, never under 200 either way.
 */
fun minimizedSize(viewWidth: Int): PlayerSize {
    val width = min(MINIMIZED_WIDTH, max(MIN_PLAYER_SIDE, viewWidth - 2 * MINIMIZED_MARGIN))
    return PlayerSize(width, max(MIN_PLAYER_SIDE, (width * 9 / 16.0).roundToInt()))
}

/** A box on screen. */
data class ScreenBox(
    /** Its left edge. */
    val left: Float,
    /** Its top edge. */
    val top: Float,
    /** How wide. */
    val width: Float,
    /** How high. */
    val height: Float,
)

/** How much of [box] lies inside [view], from 0 to 1. */
fun visibleFraction(box: ScreenBox, view: ScreenBox): Float {
    val across = min(box.left + box.width, view.left + view.width) - max(box.left, view.left)
    val down = min(box.top + box.height, view.top + view.height) - max(box.top, view.top)
    val area = box.width * box.height
    return if (area <= 0 || across <= 0 || down <= 0) 0f else across * down / area
}

/**
 * Whether a card's thumbnail box can hold the player: at least half of it
 * shows inside [view], the list's box, and it is no smaller than YouTube
 * allows. Both boxes are in dp.
 */
fun cardHolds(slot: ScreenBox, view: ScreenBox): Boolean =
    slot.width >= MIN_PLAYER_SIDE && slot.height >= MIN_PLAYER_SIDE && visibleFraction(slot, view) >= 0.5f

private fun List<FeedItem>.lists(id: String): Boolean = any { item -> item.id == id }

/** A card of the page showing was pressed: it plays in that card, with the page's list as it is now. */
fun played(item: FeedItem, page: String?, shown: List<FeedItem>, mode: WatchedMode): Playing =
    Playing(item, PlayerPlace.CARD, page, PlayQueue(shown, mode))

/** [playing] sent to the corner. */
fun minimized(playing: Playing): Playing = playing.copy(place = PlayerPlace.MINIMIZED)

/**
 * [playing] after the page or its list changed: a card on another page than
 * [page], the one showing, or no longer in [shown], that page's list, gives
 * the player to the corner. It never comes back by itself.
 */
fun afterPageChange(playing: Playing, page: String?, shown: List<FeedItem>): Playing =
    if (playing.place == PlayerPlace.CARD && (page != playing.page || !shown.lists(playing.item.id))) minimized(playing) else playing

/**
 * [playing] after the card of the entry [id] was measured or left its list:
 * a card that can't hold the player ([holds] false, see [cardHolds]) gives it
 * to the corner. Another entry's card changes nothing.
 */
fun afterCardMeasured(playing: Playing, id: String, holds: Boolean): Playing =
    if (playing.place == PlayerPlace.CARD && playing.item.id == id && !holds) minimized(playing) else playing

/**
 * A minimized [playing] brought back to its card, once [page], the page it
 * was started from, is showing with the list [shown]. It stays minimized when
 * another page is showing or the list no longer has the card.
 */
fun expanded(playing: Playing, page: String?, shown: List<FeedItem>): Playing =
    if (playing.place == PlayerPlace.MINIMIZED && page == playing.page && shown.lists(playing.item.id)) {
        playing.copy(place = PlayerPlace.CARD)
    } else {
        playing
    }

/**
 * What is playing after [playing]'s entry ended: the next of its list
 * ([nextInQueue]) where [endOutcome] puts it, the same when the player
 * stays, or null when it closes. [watched] and [autoplay] are as they are
 * now; [page] and [shown] are the page showing and its list.
 */
fun afterEnd(playing: Playing, watched: Set<String>, autoplay: Boolean, page: String?, shown: List<FeedItem>): Playing? {
    val next = nextInQueue(playing.queue, playing.item.id, watched, autoplay)
    val showing = next != null && page == playing.page && shown.lists(next.id)
    return when (val outcome = endOutcome(playing.place, next, showing)) {
        is EndOutcome.Next -> playing.copy(item = outcome.item, place = outcome.place)
        EndOutcome.Stay -> playing
        EndOutcome.Close -> null
    }
}
