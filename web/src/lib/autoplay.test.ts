import { describe, expect, test } from "bun:test";
import { nextUnwatched } from "./autoplay";
import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

function video(id: string): FeedItem {
  return {
    kind: "video",
    videoId: id,
    channelId: "UC1",
    channelTitle: "Chan",
    title: id,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
  };
}

const shown = ["a", "b", "c", "d"].map(video);
const next = (endedId: string, watched: string[]): string | null => {
  const item = nextUnwatched(shown, endedId, new Set(watched));
  return item ? feedItemId(item) : null;
};

describe("nextUnwatched", () => {
  test("is the item after the one that ended, in the order shown", () => {
    expect(next("a", ["a"])).toBe("b");
  });

  test("skips watched items", () => {
    expect(next("a", ["a", "b", "c"])).toBe("d");
  });

  test("never goes back to an earlier item", () => {
    expect(next("c", ["c", "d"])).toBeNull();
  });

  test("stops at the end of the list", () => {
    expect(next("d", ["d"])).toBeNull();
  });

  test("stops when the ended item isn't in the list", () => {
    expect(next("elsewhere", [])).toBeNull();
  });
});
