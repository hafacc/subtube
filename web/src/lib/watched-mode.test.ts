import { describe, expect, test } from "bun:test";
import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";
import {
  autoplayAdvances,
  emptiedBySelection,
  modeFiltered,
  WATCHED_MODE_OPTIONS,
  type WatchedMode,
} from "./watched-mode";

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

const items = ["a", "b", "c", "d"].map(video);
const listed = (mode: WatchedMode, staying: string[] = []): string[] =>
  modeFiltered(items, mode, new Set(["b", "d"]), new Set(staying)).map(
    feedItemId,
  );

describe("modeFiltered", () => {
  test("unwatched lists only unwatched items", () => {
    expect(listed("unwatched")).toEqual(["a", "c"]);
  });

  test("watched lists only watched items", () => {
    expect(listed("watched")).toEqual(["b", "d"]);
  });

  test("all lists both, in the order given", () => {
    expect(listed("all")).toEqual(["a", "b", "c", "d"]);
  });

  test("an item that changed sides on screen stays in either mode", () => {
    expect(listed("unwatched", ["b"])).toEqual(["a", "b", "c"]);
    expect(listed("watched", ["a"])).toEqual(["a", "b", "d"]);
  });
});

describe("the watched chip", () => {
  test("moves from Unwatched to Watched to All", () => {
    expect(WATCHED_MODE_OPTIONS.map((option) => option.label)).toEqual([
      "Unwatched",
      "Watched",
      "All",
    ]);
  });

  test("auto-play moves on everywhere but among watched items", () => {
    expect(autoplayAdvances("unwatched")).toBe(true);
    expect(autoplayAdvances("all")).toBe(true);
    expect(autoplayAdvances("watched")).toBe(false);
  });
});

describe("emptiedBySelection", () => {
  test("unwatched with no chips is simply caught up", () => {
    expect(emptiedBySelection("unwatched", "none", [])).toBe(false);
  });

  test("another mode, a time chip or a topic chip is a selection", () => {
    expect(emptiedBySelection("watched", "none", [])).toBe(true);
    expect(emptiedBySelection("all", "none", [])).toBe(true);
    expect(emptiedBySelection("unwatched", "week", [])).toBe(true);
    expect(emptiedBySelection("unwatched", "none", ["10"])).toBe(true);
  });

  test("a topic id that is no topic selects nothing", () => {
    expect(emptiedBySelection("unwatched", "none", ["99"])).toBe(false);
  });
});
