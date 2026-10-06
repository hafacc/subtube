import { feedItemId } from "./feed-item";
import { compareIgnoringCase } from "./text-order";
import type { FeedItem } from "./types";

/** The topics: YouTube's fifteen video categories by `snippet.categoryId`, with their labels. */
export const CATEGORY_NAMES: Readonly<Record<string, string>> = {
  "1": "Film & Animation",
  "2": "Autos & Vehicles",
  "10": "Music",
  "15": "Pets & Animals",
  "17": "Sports",
  "19": "Travel & Events",
  "20": "Gaming",
  "22": "People & Blogs",
  "23": "Comedy",
  "24": "Entertainment",
  "25": "News & Politics",
  "26": "Howto & Style",
  "27": "Education",
  "28": "Science & Technology",
  "29": "Nonprofits & Activism",
};

/** A category id's label; null for an id that is not one of YouTube's fifteen. */
export function topicLabel(categoryId: string | undefined): string | null {
  return categoryId !== undefined && Object.hasOwn(CATEGORY_NAMES, categoryId)
    ? CATEGORY_NAMES[categoryId]
    : null;
}

/** A feed item's topic: its category id when that is one of the fifteen; a playlist has none. */
export function itemTopic(item: FeedItem): string | null {
  return item.kind === "video" && topicLabel(item.categoryId) !== null
    ? (item.categoryId ?? null)
    : null;
}

/** The ids among `categoryIds` that are topics, each once. */
export function knownTopics(categoryIds: readonly string[]): Set<string> {
  return new Set(categoryIds.filter((id) => topicLabel(id) !== null));
}

/** The time chips: how far back the feed reaches. */
export type TimeChip = "none" | "day" | "week" | "month";

/** The length of each time span, in milliseconds; a month is 30 days. */
export const SPAN_MS = {
  day: 86_400_000,
  week: 7 * 86_400_000,
  month: 30 * 86_400_000,
} as const;

/** The time chip's choices, in the order it moves through them. */
export const TIME_CHIP_OPTIONS = [
  { value: "none", label: "All time" },
  { value: "day", label: "Past day" },
  { value: "week", label: "Past week" },
  { value: "month", label: "Past month" },
] as const satisfies readonly { value: TimeChip; label: string }[];

/** Whether `publishedAt` is at or after `now` less the span. */
export function publishedWithin(
  publishedAt: string,
  span: keyof typeof SPAN_MS,
  now: number,
): boolean {
  return now - Date.parse(publishedAt) <= SPAN_MS[span];
}

function byCountThenLabel(counts: ReadonlyMap<string, number>): string[] {
  return Array.from(counts)
    .sort(
      ([leftId, leftCount], [rightId, rightCount]) =>
        rightCount - leftCount ||
        compareIgnoringCase(CATEGORY_NAMES[leftId], CATEGORY_NAMES[rightId]),
    )
    .map(([categoryId]) => categoryId);
}

function countTopics(
  items: readonly FeedItem[],
  counts: Map<string, number>,
): Map<string, number> {
  for (const item of items) {
    const topic = itemTopic(item);
    if (topic !== null) {
      counts.set(topic, (counts.get(topic) ?? 0) + 1);
    }
  }
  return counts;
}

/**
 * The topic chips for a list, as category ids in row order: every topic an
 * item has plus every selected one, by how many items have it, most first,
 * then by label ignoring case.
 */
export function chipRow(
  items: readonly FeedItem[],
  selected: readonly string[],
): string[] {
  return byCountThenLabel(
    countTopics(
      items,
      new Map(Array.from(knownTopics(selected), (id) => [id, 0])),
    ),
  );
}

/** All fifteen topics for a channel's filter editor: by how many of its fetched videos have each, most first, then by label. */
export function editorTopics(items: readonly FeedItem[]): string[] {
  return byCountThenLabel(
    countTopics(
      items,
      new Map(Object.keys(CATEGORY_NAMES).map((id) => [id, 0])),
    ),
  );
}

/** The items the chips keep: inside the time chip's span, and in a selected topic when any is selected. */
export function chipFiltered(
  items: readonly FeedItem[],
  timeChip: TimeChip,
  selected: readonly string[],
  now: number,
): FeedItem[] {
  const wanted = knownTopics(selected);
  return items.filter((item) => {
    const topic = itemTopic(item);
    return (
      (timeChip === "none" ||
        publishedWithin(item.publishedAt, timeChip, now)) &&
      (wanted.size === 0 || (topic !== null && wanted.has(topic)))
    );
  });
}

/** Where setup starts the feed: everything older is marked watched. */
export type StartFrom = "day" | "week" | "all";

/** Setup's starting points, in order. */
export const START_OPTIONS = [
  { value: "day", label: "Past day" },
  { value: "week", label: "Past week" },
  { value: "all", label: "All time" },
] as const satisfies readonly { value: StartFrom; label: string }[];

/** The ids setup's starting point marks watched: every item published before `now` less the span. */
export function startMarks(
  items: readonly FeedItem[],
  start: StartFrom,
  now: number,
): string[] {
  if (start === "all") {
    return [];
  } else {
    return items
      .filter((item) => !publishedWithin(item.publishedAt, start, now))
      .map(feedItemId);
  }
}

const PENDING_START_PREFIX = "subtube.startFrom.";

/** Keep setup's starting point for the account's next feed load. */
export function keepPendingStart(accountId: string, start: StartFrom): void {
  try {
    if (start === "all") {
      localStorage.removeItem(PENDING_START_PREFIX + accountId);
    } else {
      localStorage.setItem(PENDING_START_PREFIX + accountId, start);
    }
  } catch {
    // nothing is marked then
  }
}

/** Setup's starting point for the account, handed over once. */
export function takePendingStart(accountId: string): StartFrom {
  try {
    const kept = localStorage.getItem(PENDING_START_PREFIX + accountId);
    localStorage.removeItem(PENDING_START_PREFIX + accountId);
    return kept === "day" || kept === "week" ? kept : "all";
  } catch {
    return "all";
  }
}
