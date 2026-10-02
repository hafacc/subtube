import { describe, expect, test } from "bun:test";
import { feedItemId } from "./feed-item";
import { extendOrder, isOldestFirst } from "./feed-order";
import type { FeedItem, Video } from "./types";

function video(id: string, day: number): Video {
  return {
    kind: "video",
    videoId: id,
    channelId: "UC1",
    channelTitle: "Chan",
    title: id,
    description: "",
    publishedAt: `2026-01-${String(day).padStart(2, "0")}T00:00:00Z`,
    thumbnail: "",
  };
}

function byId(items: FeedItem[]): Map<string, FeedItem> {
  return new Map(items.map((item) => [feedItemId(item), item]));
}

describe("extendOrder", () => {
  test("returns the same list when nothing changed", () => {
    const items = [video("a", 1), video("b", 2)];
    const order = ["a", "b"];
    expect(extendOrder(order, byId(items), items)).toBe(order);
  });

  test("appends arrivals oldest first without moving what is shown", () => {
    const items = [video("a", 5), video("c", 9), video("b", 7), video("z", 1)];
    expect(extendOrder(["a"], byId(items), items)).toEqual([
      "a",
      "z",
      "b",
      "c",
    ]);
  });

  test("drops entries that no longer pass", () => {
    const items = [video("b", 2)];
    expect(extendOrder(["a", "b"], byId(items), items)).toEqual(["b"]);
  });
});

describe("isOldestFirst", () => {
  test("accepts ascending and rejects a late arrival", () => {
    expect(isOldestFirst([video("a", 1), video("b", 2)])).toBe(true);
    expect(isOldestFirst([video("b", 2), video("a", 1)])).toBe(false);
  });
});
