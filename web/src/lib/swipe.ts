/*
 * The rules of the sideways swipe that marks a card in the narrow layout:
 * when a touch that moves becomes a swipe, and when a released swipe counts.
 */

/** How far a pointer moves, in pixels, before it is read as a swipe or a scroll. */
export const SWIPE_SLOP = 10;

/** How many times further sideways than up or down a movement goes to be a swipe. */
export const SWIPE_SIDEWAYS_RATIO = 2;

/** The share of a card's width a swipe covers to count when released. */
export const SWIPE_THRESHOLD = 0.25;

/** What a pointer's movement since it went down is. */
export type SwipeIntent = "undecided" | "swipe" | "scroll";

/**
 * What a movement of `deltaX` and `deltaY` pixels is: nothing yet under
 * {@link SWIPE_SLOP}, a swipe when clearly sideways, a scroll otherwise.
 */
export function swipeIntent(deltaX: number, deltaY: number): SwipeIntent {
  const sideways = Math.abs(deltaX);
  const upright = Math.abs(deltaY);
  if (Math.max(sideways, upright) < SWIPE_SLOP) {
    return "undecided";
  } else if (sideways >= upright * SWIPE_SIDEWAYS_RATIO) {
    return "swipe";
  } else {
    return "scroll";
  }
}

/** Where a card dragged `distance` pixels is drawn: never further than its width. */
export function swipeOffset(distance: number, width: number): number {
  return Math.max(-width, Math.min(width, distance));
}

/** Whether a swipe released `offset` pixels to either side of a card `width` wide marks it. */
export function swipePasses(offset: number, width: number): boolean {
  return width > 0 && Math.abs(offset) >= width * SWIPE_THRESHOLD;
}
