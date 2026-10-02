import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

/** Oldest first, the order the feed reads in. */
export function byOldest(left: FeedItem, right: FeedItem): number {
  return left.publishedAt.localeCompare(right.publishedAt);
}

/** Whether a list already reads oldest first. */
export function isOldestFirst(items: FeedItem[]): boolean {
  return items.every(
    (item, index) =>
      index === 0 || items[index - 1].publishedAt <= item.publishedAt,
  );
}

/**
 * Grow what is on screen without moving any of it: entries that no longer pass
 * are dropped, and arrivals join the end, oldest first among themselves.
 * Returns `order` itself when nothing changed.
 */
export function extendOrder(
  order: string[],
  passing: Map<string, FeedItem>,
  arrivals: FeedItem[],
): string[] {
  const kept = order.filter((id) => passing.has(id));
  const onScreen = new Set(kept);
  const added = arrivals
    .filter((item) => !onScreen.has(feedItemId(item)))
    .sort(byOldest)
    .map(feedItemId);
  if (kept.length === order.length && added.length === 0) {
    return order;
  } else {
    return [...kept, ...added];
  }
}
