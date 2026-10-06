import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/feed-order.json";
import { feedItemId } from "./feed-item";
import {
  byNewest,
  type FeedSort,
  newShuffleSeed,
  shuffleKey,
  sortFeed,
} from "./feed-order";
import type { FeedItem } from "./types";

interface FixtureItem {
  id: string;
  kind?: string;
  title?: string;
  publishedAt?: string;
  durationSeconds?: number;
}

function feedItem(raw: FixtureItem): FeedItem {
  const common = {
    channelId: "UC1",
    channelTitle: "Chan",
    title: raw.title ?? raw.id,
    description: "",
    publishedAt: raw.publishedAt ?? "",
    thumbnail: "",
  };
  if (raw.kind === "playlist") {
    return { ...common, kind: "playlist", playlistId: raw.id, itemCount: 1 };
  } else {
    return {
      ...common,
      kind: "video",
      videoId: raw.id,
      durationSeconds: raw.durationSeconds,
    };
  }
}

describe("shared feed order fixtures", () => {
  for (const testCase of fixture.cases) {
    const items: FixtureItem[] = testCase.items;
    const seed = "seed" in testCase ? (testCase.seed ?? 0) : 0;
    test(testCase.name, () => {
      if (testCase.op === "hash") {
        expect(items.map(({ id }) => shuffleKey(seed, id))).toEqual(
          testCase.expected as number[],
        );
      } else {
        expect(testCase.op).toBe("sort");
        const sort = (
          "sort" in testCase ? testCase.sort : "newest"
        ) as FeedSort;
        for (const given of [items, items.toReversed()]) {
          expect(
            sortFeed(given.map(feedItem), sort, seed).map(feedItemId),
          ).toEqual(testCase.expected as string[]);
        }
      }
    });
  }
});

describe("sortFeed", () => {
  const items = ["c", "a", "b"].map((id) =>
    feedItem({
      id,
      publishedAt: `2026-01-0${id.charCodeAt(0) - 96}T00:00:00Z`,
    }),
  );

  test("newest is the tie-break order alone", () => {
    expect(sortFeed(items, "newest", 0)).toEqual(items.toSorted(byNewest));
  });

  test("leaves the list it was given as it was", () => {
    sortFeed(items, "title", 0);
    expect(items.map(feedItemId)).toEqual(["c", "a", "b"]);
  });

  test("a seed is a whole number below 2^32", () => {
    const seed = newShuffleSeed();
    expect(Number.isInteger(seed)).toBe(true);
    expect(seed).toBeGreaterThanOrEqual(0);
    expect(seed).toBeLessThan(2 ** 32);
  });
});
