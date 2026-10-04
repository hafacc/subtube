import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

function compareCodeUnits(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

/** Newest first, the order the feed reads in; equal times go by id ascending. */
export function byNewest(left: FeedItem, right: FeedItem): number {
  return (
    compareCodeUnits(right.publishedAt, left.publishedAt) ||
    compareCodeUnits(feedItemId(left), feedItemId(right))
  );
}
