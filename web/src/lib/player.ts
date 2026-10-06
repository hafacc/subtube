import { nextUnwatched } from "./autoplay";
import { feedItemId } from "./feed-item";
import type { RouteItem } from "./router";
import type { FeedItem } from "./types";
import { autoplayAdvances, type WatchedMode } from "./watched-mode";

/**
 * Where the one player is drawn: over the dimmed app, in place of its card's
 * thumbnail, or in the window's bottom right corner.
 */
export type PlayerPlace = "large" | "card" | "minimized";

/** The list a video was started from, as it was then. */
export interface PlayQueue {
  /** the page's items, in the order shown */
  items: readonly FeedItem[];
  /** the watched chip's choice */
  mode: WatchedMode;
}

/** What the one player is playing. */
export interface Playing {
  /** the video or playlist */
  item: RouteItem;
  /** where it is drawn */
  place: PlayerPlace;
  /** the page it was started from: a channel's id, or null for the feed */
  page: string | null;
  /** the list it was started from; null when it was opened from a link */
  queue: PlayQueue | null;
}

/** What happens when the playing item ends. */
export type EndOutcome =
  | { kind: "next"; item: FeedItem; place: PlayerPlace }
  | { kind: "stay" }
  | { kind: "close" };

/** The smallest player YouTube allows, in CSS pixels each way. */
export const MIN_PLAYER_SIDE = 200;
/** The height of the bar above the video, its hairline included. */
export const BAR_HEIGHT = 37;
/** The width of the minimized player where the window has room for it. */
export const MINIMIZED_WIDTH = 356;
/** The gap between the minimized player and the window's edges. */
export const MINIMIZED_MARGIN = 16;
/** The room a list keeps after its last row while the player is minimized: the player's height and its margin above and below. */
export const MINIMIZED_ROOM = MIN_PLAYER_SIDE + 2 * MINIMIZED_MARGIN;

/** A feed item as the player and the URL name it. */
export function routeItem(item: FeedItem): RouteItem {
  return { kind: item.kind, id: feedItemId(item) };
}

/**
 * What auto-play plays after `endedId`: the next unwatched item after it in
 * the list the video was started from, whatever page is showing now. Null
 * with auto-play off, when that list was the watched items only, at its end,
 * or when the ended item isn't in it.
 */
export function nextInQueue(
  queue: PlayQueue,
  endedId: string,
  watched: ReadonlySet<string>,
  autoplay: boolean,
): FeedItem | null {
  if (autoplay && autoplayAdvances(queue.mode)) {
    return nextUnwatched(queue.items, endedId, watched);
  } else {
    return null;
  }
}

/**
 * What the end of an item does to a player in `place`. The next item plays
 * where the player is, except that a card not on screen can't hold it. With
 * nothing next, the large and the minimized player stay on the ended video,
 * until the user closes or expands them, and a card's player closes.
 */
export function endOutcome(
  place: PlayerPlace,
  next: FeedItem | null,
  nextOnScreen: boolean,
): EndOutcome {
  if (next) {
    return {
      kind: "next",
      item: next,
      place: place === "card" && !nextOnScreen ? "minimized" : place,
    };
  } else if (place === "card") {
    return { kind: "close" };
  } else {
    return { kind: "stay" };
  }
}

/**
 * What the URL's item does to the player. The item is in the URL only while
 * the player is large, so losing it minimizes a large player, gaining the
 * playing one makes it large, and any other is a link: it plays large, with
 * no list behind it.
 */
export function afterRoute(
  playing: Playing | null,
  item: RouteItem | null,
  page: string | null,
): Playing | null {
  if (item === null) {
    return playing?.place === "large"
      ? { ...playing, place: "minimized" }
      : playing;
  } else if (
    playing &&
    playing.item.kind === item.kind &&
    playing.item.id === item.id
  ) {
    return playing.place === "large" ? playing : { ...playing, place: "large" };
  } else {
    return { item, place: "large", page, queue: null };
  }
}

/** A box on screen, in CSS pixels. */
export interface Box {
  /** its top edge */
  top: number;
  /** its left edge */
  left: number;
  /** its width */
  width: number;
  /** its height */
  height: number;
}

/** The part of `box` inside `view`; null when none of it is. */
export function clipped(box: Box, view: Box): Box | null {
  const left = Math.max(box.left, view.left);
  const top = Math.max(box.top, view.top);
  const right = Math.min(box.left + box.width, view.left + view.width);
  const bottom = Math.min(box.top + box.height, view.top + view.height);
  if (right <= left || bottom <= top) {
    return null;
  } else {
    return { top, left, width: right - left, height: bottom - top };
  }
}

/** How much of `box` lies inside `view`, from 0 to 1. */
export function visibleFraction(box: Box, view: Box): number {
  const shown = clipped(box, view);
  if (shown === null) {
    return 0;
  } else {
    return (shown.width * shown.height) / (box.width * box.height);
  }
}

/**
 * Whether a card's thumbnail box can hold the player: at least half of it
 * shows, and it is no smaller than YouTube allows.
 */
export function cardHolds(slot: Box, view: Box): boolean {
  return (
    slot.width >= MIN_PLAYER_SIDE &&
    slot.height >= MIN_PLAYER_SIDE &&
    visibleFraction(slot, view) >= 0.5
  );
}

/** A window's inner size, in CSS pixels. */
export interface ViewSize {
  /** its width */
  width: number;
  /** its height */
  height: number;
}

/**
 * The minimized player's box: 356 by 200 in the window's bottom right corner,
 * `beside` further left when a panel that wide is open at the right edge. A
 * window too narrow for that gets the width it has at 16:9, never under 200
 * high.
 */
export function minimizedBox(view: ViewSize, beside: number): Box {
  const width = Math.min(
    MINIMIZED_WIDTH,
    Math.max(MIN_PLAYER_SIDE, view.width - 2 * MINIMIZED_MARGIN),
  );
  const height = Math.max(MIN_PLAYER_SIDE, Math.round((width * 9) / 16));
  return {
    top: view.height - MINIMIZED_MARGIN - height,
    left: view.width - MINIMIZED_MARGIN - beside - width,
    width,
    height,
  };
}

/**
 * The large player's box: the widest 16:9 video that fits inside the margins
 * with the bar above it, the two centred together, never smaller than YouTube
 * allows.
 */
export function largeBox(view: ViewSize): Box {
  const margin = Math.min(48, Math.max(16, view.width * 0.04));
  const width = Math.max(
    (MIN_PLAYER_SIDE * 16) / 9,
    Math.min(
      view.width - 2 * margin,
      ((view.height - 2 * margin - BAR_HEIGHT) * 16) / 9,
    ),
  );
  const height = (width * 9) / 16;
  return {
    top: Math.round((view.height - height - BAR_HEIGHT) / 2) + BAR_HEIGHT,
    left: Math.round((view.width - width) / 2),
    width: Math.round(width),
    height: Math.round(height),
  };
}
