import { feedItemId } from "./feed-item";
import { compareIgnoringCase } from "./text-order";
import type { FeedItem } from "./types";

/** The orders the feed can be read in. */
export type FeedSort =
  | "newest"
  | "oldest"
  | "shortest"
  | "longest"
  | "title"
  | "titleReversed"
  | "random";

/** One order as a sort chip shows it. */
export interface FeedSortOption {
  /** the `feedSort` setting's value */
  value: FeedSort;
  /** the chip's text */
  label: string;
}

/**
 * The sort chips, in row order: each holds an order and, after it, its
 * reverse. Random has none.
 */
export const FEED_SORT_CHIPS: readonly (readonly FeedSortOption[])[] = [
  [
    { value: "newest", label: "Latest" },
    { value: "oldest", label: "Oldest" },
  ],
  [
    { value: "shortest", label: "Shortest" },
    { value: "longest", label: "Longest" },
  ],
  [
    { value: "title", label: "Title A–Z" },
    { value: "titleReversed", label: "Title Z–A" },
  ],
  [{ value: "random", label: "Random" }],
];

/** Every order, as the `feedSort` setting may hold it. */
export const FEED_SORTS: readonly FeedSort[] = FEED_SORT_CHIPS.flatMap(
  (options) => options.map((option) => option.value),
);

/** The primary key of each reversed order: the order it reverses. */
const REVERSES: Partial<Record<FeedSort, FeedSort>> = {
  oldest: "newest",
  longest: "shortest",
  titleReversed: "title",
};

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

/**
 * By length, shortest first or, with `direction` -1, longest first; items
 * without a length go last either way, tying with each other.
 */
function byLength(left: FeedItem, right: FeedItem, direction: 1 | -1): number {
  const leftSeconds = duration(left);
  const rightSeconds = duration(right);
  if (leftSeconds === undefined || rightSeconds === undefined) {
    return (
      Number(leftSeconds === undefined) - Number(rightSeconds === undefined)
    );
  } else {
    return direction * (leftSeconds - rightSeconds);
  }
}

/**
 * The items in one of the feed's orders (shared/fixtures/feed-order.json).
 *
 * A reversed order turns its first key round and nothing else: ties in every
 * order go newest first, then by id, and items without a length stay last.
 * `seed` fixes the random one.
 */
export function sortFeed(
  items: readonly FeedItem[],
  sort: FeedSort,
  seed: number,
): FeedItem[] {
  const forward = REVERSES[sort] ?? sort;
  const direction = forward === sort ? 1 : -1;
  let primary: (left: FeedItem, right: FeedItem) => number;
  if (forward === "title") {
    primary = (left, right) =>
      direction * compareIgnoringCase(left.title, right.title);
  } else if (forward === "shortest") {
    primary = (left, right) => byLength(left, right, direction);
  } else if (forward === "random") {
    const keys = new Map(
      items.map((item) => [item, shuffleKey(seed, feedItemId(item))]),
    );
    primary = (left, right) => (keys.get(left) ?? 0) - (keys.get(right) ?? 0);
  } else if (sort === "oldest") {
    primary = (left, right) =>
      compareCodeUnits(left.publishedAt, right.publishedAt);
  } else {
    primary = () => 0;
  }
  return items.toSorted(
    (left, right) => primary(left, right) || byNewest(left, right),
  );
}
