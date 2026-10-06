import { feedItemId } from "./feed-item";
import { compareIgnoringCase } from "./text-order";
import type { FeedItem } from "./types";

/** The orders the feed can be read in. */
export type FeedSort = "newest" | "shortest" | "title" | "random";

/** The feed orders, in the order their chip moves through them. */
export const FEED_SORT_OPTIONS = [
  { value: "newest", label: "Latest" },
  { value: "shortest", label: "Shortest" },
  { value: "title", label: "Title" },
  { value: "random", label: "Random" },
] as const satisfies readonly { value: FeedSort; label: string }[];

function compareCodeUnits(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

/** Newest first; equal times go by id ascending. Every other order ends in this one. */
export function byNewest(left: FeedItem, right: FeedItem): number {
  return (
    compareCodeUnits(right.publishedAt, left.publishedAt) ||
    compareCodeUnits(feedItemId(left), feedItemId(right))
  );
}

const UTF8 = new TextEncoder();

/**
 * Where the random order puts an item: the 32-bit FNV-1a hash of the UTF-8
 * bytes of the seed in decimal, a colon, and the item's id; smaller first.
 */
export function shuffleKey(seed: number, id: string): number {
  let hash = 0x811c9dc5;
  for (const byte of UTF8.encode(`${seed}:${id}`)) {
    hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  }
  return hash;
}

/** A seed for the random order: a whole number below 2^32. */
export function newShuffleSeed(): number {
  return Math.floor(Math.random() * 2 ** 32);
}

/** A video's length in seconds; undefined for a playlist or a video without one. */
function duration(item: FeedItem): number | undefined {
  return item.kind === "video" && item.durationSeconds
    ? item.durationSeconds
    : undefined;
}

/** Shortest first; items without a length go last, tying with each other. */
function byShortest(left: FeedItem, right: FeedItem): number {
  const leftSeconds = duration(left);
  const rightSeconds = duration(right);
  if (leftSeconds === undefined || rightSeconds === undefined) {
    return (
      Number(leftSeconds === undefined) - Number(rightSeconds === undefined)
    );
  } else {
    return leftSeconds - rightSeconds;
  }
}

/**
 * The items in one of the feed's orders (shared/fixtures/feed-order.json);
 * ties in any order go newest first, then by id. `seed` fixes the random one.
 */
export function sortFeed(
  items: readonly FeedItem[],
  sort: FeedSort,
  seed: number,
): FeedItem[] {
  let primary: (left: FeedItem, right: FeedItem) => number;
  if (sort === "title") {
    primary = (left, right) => compareIgnoringCase(left.title, right.title);
  } else if (sort === "shortest") {
    primary = byShortest;
  } else if (sort === "random") {
    const keys = new Map(
      items.map((item) => [item, shuffleKey(seed, feedItemId(item))]),
    );
    primary = (left, right) => (keys.get(left) ?? 0) - (keys.get(right) ?? 0);
  } else {
    primary = () => 0;
  }
  return items.toSorted(
    (left, right) => primary(left, right) || byNewest(left, right),
  );
}
