import { describe, expect, test } from "bun:test";
import { FeedController } from "./feed.svelte";
import { feedItemId } from "./feed-item";
import type { Router } from "./router.svelte";
import type { Session } from "./session.svelte";
import { defaultFilter } from "./sync-merge";
import type { SyncStore } from "./sync-store";
import type { Channel, Video } from "./types";

function video(id: string, day: number, channelId = "UCa"): Video {
  return {
    kind: "video",
    videoId: id,
    channelId,
    channelTitle: channelId,
    title: id,
    description: "",
    publishedAt: `2026-01-${String(day).padStart(2, "0")}T00:00:00Z`,
    thumbnail: "",
  };
}

function channel(channelId: string): Channel {
  return {
    channelId,
    title: channelId,
    thumbnail: "",
    filter: defaultFilter(),
  };
}

/** A controller over loaded items, on the feed (null) or a channel's page, with the saves it made. */
function loaded(
  watched: string[],
  page: string | null,
  watchedElsewhere: string[] = [],
): {
  feed: FeedController;
  saves: { ids: string[]; watched: boolean }[];
} {
  const saves: { ids: string[]; watched: boolean }[] = [];
  const store = {
    setWatched: (id: string, isWatched: boolean) =>
      saves.push({ ids: [id], watched: isWatched }),
    setWatchedAll: (ids: readonly string[], isWatched: boolean) =>
      saves.push({ ids: [...ids], watched: isWatched }),
    setFilter: () => undefined,
    isWatched: (id: string) => watchedElsewhere.includes(id),
  } as unknown as SyncStore;
  const session = { account: { channelId: "UCme" } } as unknown as Session;
  const router = { route: { channel: page, item: null } } as unknown as Router;
  const feed = new FeedController(session, store, router);
  feed.channels = new Map([
    ["UCa", channel("UCa")],
    ["UCb", channel("UCb")],
  ]);
  feed.items = [
    video("a1", 1),
    video("b5", 5, "UCb"),
    video("a3", 3),
    video("a7", 7),
  ];
  feed.watched = new Set(watched);
  return { feed, saves };
}

const shown = (feed: FeedController): string[] => feed.feed.map(feedItemId);

describe("FeedController mark all", () => {
  test("marks the channel's shown cards watched, in place, as one save", () => {
    const { feed, saves } = loaded(["a1"], "UCa");
    expect(shown(feed)).toEqual(["a7", "a3"]);
    feed.markAll(feed.channels.get("UCa") as Channel);
    expect(shown(feed)).toEqual(["a7", "a3"]);
    expect(feed.watched).toEqual(new Set(["a1", "a3", "a7"]));
    expect(saves).toEqual([{ ids: ["a7", "a3"], watched: true }]);
  });

  test("then unmarks exactly those cards, leaving older watched ones hidden", () => {
    const { feed, saves } = loaded(["a1"], "UCa");
    const channelA = feed.channels.get("UCa") as Channel;
    void feed.feed;
    feed.markAll(channelA);
    expect(feed.markAllFor(channelA).watched).toBe(false);
    feed.markAll(channelA);
    expect(shown(feed)).toEqual(["a7", "a3"]);
    expect(feed.watched).toEqual(new Set(["a1"]));
    expect(saves[1]).toEqual({ ids: ["a7", "a3"], watched: false });
  });

  test("is disabled when the channel shows no card", () => {
    const { feed, saves } = loaded(["a1", "a3", "a7"], "UCa");
    const channelA = feed.channels.get("UCa") as Channel;
    expect(shown(feed)).toEqual([]);
    expect(feed.markAllFor(channelA)).toEqual({ watched: true, ids: [] });
    feed.markAll(channelA);
    expect(saves).toEqual([]);
  });

  test("with watched cards shown, unmarking shows them all as unwatched", () => {
    const { feed } = loaded(["a1", "a3", "a7"], "UCa");
    feed.toggleShowWatched();
    feed.markAll(feed.channels.get("UCa") as Channel);
    feed.toggleShowWatched();
    expect(shown(feed)).toEqual(["a7", "a3", "a1"]);
  });

  test("unmarking one hidden video brings it back in its sorted place", () => {
    const { feed } = loaded(["a3"], null);
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
    feed.setWatched("a3", false);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });
});

describe("FeedController just-watched cards", () => {
  test("a card marked watched stays until the watched toggle is used", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    feed.toggleShowWatched();
    feed.toggleShowWatched();
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("a filter edit drops it", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    const channelB = feed.channels.get("UCb") as Channel;
    feed.updateFilter("UCb", { ...channelB.filter, minDurationSeconds: 0 });
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("a single channel's fetch arriving doesn't drop it", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    feed.addChannelItems("UCb", "videos", [video("b5", 5, "UCb")]);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });

  test("items already watched elsewhere stay hidden when they arrive", () => {
    const { feed } = loaded([], null, ["b9"]);
    feed.addChannelItems("UCb", "videos", [
      video("b5", 5, "UCb"),
      video("b9", 9, "UCb"),
    ]);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });
});
