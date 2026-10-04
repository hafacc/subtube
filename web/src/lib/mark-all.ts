import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

/** What a channel's "Mark all" button does when pressed. */
export interface MarkAll {
  /** the mark the button sets: watched, or unwatched when all are watched already */
  watched: boolean;
  /** the ids it sets it on; empty disables the button */
  ids: string[];
}

/**
 * What a channel's "Mark all" button does, over the cards shown on its page:
 * mark the unwatched ones watched; or, when every one is watched already, mark
 * exactly those unwatched; with none shown, nothing.
 */
export function markAllChoice(
  shown: readonly FeedItem[],
  watched: ReadonlySet<string>,
): MarkAll {
  const ids = shown.map(feedItemId);
  const unwatched = ids.filter((id) => !watched.has(id));
  if (unwatched.length === 0 && ids.length > 0) {
    return { watched: false, ids };
  } else {
    return { watched: true, ids: unwatched };
  }
}
