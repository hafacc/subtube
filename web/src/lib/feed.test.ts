import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  test,
} from "bun:test";
import { expectAccount, forgetToken } from "./auth";
import { UNREACHABLE_MESSAGE } from "./errors";
import {
  type ChannelItems,
  completeItems,
  covers,
  FeedController,
  fetchChannels,
  needsShorts,
  Prefetch,
} from "./feed.svelte";
import { feedItemId } from "./feed-item";
import { recheckPlatform } from "./platform";
import type { Router } from "./router.svelte";
import type { Session } from "./session.svelte";
import { defaultFilter } from "./sync-merge";
import type { SyncStore } from "./sync-store";
import type { Channel, ChannelFilter, FeedItem, Video } from "./types";
import { DailyLimitError, TokenExpiredError } from "./youtube";

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
    durationSeconds: 600,
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

interface Entry {
  at: number;
  watched: boolean;
  position?: number;
}

/** What the controller saved, in order. */
type Save =
  | { ids: string[]; watched: boolean }
  | { id: string; position: number; ended: boolean; upload: boolean }
  | { filters: Record<string, ChannelFilter> }
  | "flush";

/** A controller over loaded items, on the feed (null) or a channel's page, with the saves it made. */
function loaded(
  watched: string[],
  page: string | null,
  watchedElsewhere: string[] = [],
  synced: Record<string, { at: number; value: unknown }> = {},
): {
  feed: FeedController;
  saves: Save[];
  synced: Record<string, { at: number; value: unknown }>;
  entries: Map<string, Entry>;
} {
  const saves: Save[] = [];
  const savedFilters: Record<string, ChannelFilter> = {};
  const entries = new Map<string, Entry>(
    [...watched, ...watchedElsewhere].map((id) => [
      id,
      { at: 1, watched: true },
    ]),
  );
  const mark = (id: string, isWatched: boolean) =>
    entries.set(
      id,
      isWatched
        ? { ...entries.get(id), at: 2, watched: true }
        : { at: 2, watched: false },
    );
  const store = {
    setWatched: (id: string, isWatched: boolean) => {
      mark(id, isWatched);
      saves.push({ ids: [id], watched: isWatched });
    },
    setWatchedAll: (ids: readonly string[], isWatched: boolean) => {
      for (const id of ids) {
        mark(id, isWatched);
      }
      saves.push({ ids: [...ids], watched: isWatched });
    },
    setProgress: (
      id: string,
      position: number,
      ended: boolean,
      upload: boolean,
    ) => {
      entries.set(id, { at: 2, watched: ended, position });
      saves.push({ id, position, ended, upload });
    },
    flush: () => saves.push("flush"),
    setFilter: () => undefined,
    savedFilters: () => ({ ...savedFilters }),
    setFilters: (filters: Record<string, ChannelFilter>) => {
      Object.assign(savedFilters, filters);
      saves.push({ filters });
    },
    noteLoaded: () => undefined,
    watchedEntry: (id: string) => entries.get(id),
    settings: () => ({ ...synced }),
    setSetting: (name: string, value: unknown) => {
      synced[name] = { at: 1, value };
    },
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
  markOnly(feed, watched);
  return { feed, saves, synced, entries };
}

/** Make exactly these ids the watched ones. */
function markOnly(feed: FeedController, ids: string[]): void {
  feed.watched.clear();
  for (const id of ids) {
    feed.watched.add(id);
  }
}

const shown = (feed: FeedController): string[] => feed.feed.map(feedItemId);

const byId = (left: FeedItem, right: FeedItem): number =>
  feedItemId(left).localeCompare(feedItemId(right));

describe("FeedController watched marks", () => {
  test("unmarking one hidden video brings it back in its sorted place", () => {
    const { feed } = loaded(["a3"], null);
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
    feed.setWatched("a3", false);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });

  test("one id's mark alone moves the counts", () => {
    const { feed } = loaded([], null);
    expect(feed.unwatchedCount).toBe(4);
    feed.watched.add("a3");
    expect(feed.unwatchedCount).toBe(3);
    feed.watched.delete("a3");
    expect(feed.unwatchedCount).toBe(4);
  });

  test("a mark shows a full bar, and unmarking takes it away", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    expect(feed.bars.get("a3")).toBe(1);
    feed.setWatched("a3", false);
    expect(feed.bars.has("a3")).toBe(false);
  });
});

describe("FeedController watch progress", () => {
  test("a position part-way is saved on the device only, and the video stays unwatched", () => {
    const { feed, saves } = loaded([], null);
    feed.recordProgress("a3", 150.7, 600, false, "later");
    expect(saves).toEqual([
      { id: "a3", position: 150, ended: false, upload: false },
    ]);
    expect(feed.watched.has("a3")).toBe(false);
    expect(feed.bars.get("a3")).toBe(0.25);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    expect(feed.resumeAt("a3")).toBe(150);
    expect(feed.unwatchedCount).toBe(4);
  });

  test("pausing or leaving uploads after the usual pause, hiding the tab at once", () => {
    const { feed, saves } = loaded([], null);
    feed.recordProgress("a3", 10, 600, false, "soon");
    feed.recordProgress("a3", 20, 600, false, "now");
    expect(saves).toEqual([
      { id: "a3", position: 10, ended: false, upload: true },
      { id: "a3", position: 20, ended: false, upload: true },
      "flush",
    ]);
  });

  test("the last 10 seconds make it watched; it stays on screen with a full bar", () => {
    const { feed } = loaded([], null);
    feed.recordProgress("a3", 590, 600, false, "later");
    expect(feed.watched.has("a3")).toBe(true);
    expect(feed.bars.get("a3")).toBe(1);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    expect(feed.unwatchedCount).toBe(3);
    expect(feed.resumeAt("a3")).toBe(0);
    feed.setWatchedMode("unwatched");
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("moving back in a watched video makes it unwatched at the new position", () => {
    const { feed } = loaded([], null);
    feed.recordProgress("a3", 600, 600, true, "soon");
    expect(feed.watched.has("a3")).toBe(true);
    feed.recordProgress("a3", 120, 600, false, "later");
    expect(feed.watched.has("a3")).toBe(false);
    expect(feed.bars.get("a3")).toBe(0.2);
    expect(feed.resumeAt("a3")).toBe(120);
  });

  test("the feed's length counts before the player's", () => {
    const { feed } = loaded([], null);
    feed.items = [{ ...video("a3", 3), durationSeconds: 1200 }];
    feed.recordProgress("a3", 590, 600, false, "later");
    expect(feed.watched.has("a3")).toBe(false);
    expect(feed.bars.get("a3")).toBeCloseTo(590 / 1200);
  });

  test("a short video is watched only when its player reports the end", () => {
    const { feed } = loaded([], null);
    feed.items = [{ ...video("a3", 3), durationSeconds: 8 }];
    feed.recordProgress("a3", 7, 8, false, "later");
    expect(feed.watched.has("a3")).toBe(false);
    feed.recordProgress("a3", 8, 8, true, "soon");
    expect(feed.watched.has("a3")).toBe(true);
  });

  test("positions saved on another device show when the items arrive", () => {
    const { feed, entries } = loaded([], null);
    entries.set("b9", { at: 1, watched: false, position: 30 });
    entries.set("b8", { at: 1, watched: false, position: 115 });
    feed.addChannelItems("UCb", "videos", [
      { ...video("b9", 9, "UCb"), durationSeconds: 120 },
      { ...video("b8", 8, "UCb"), durationSeconds: 120 },
    ]);
    expect(feed.bars.get("b9")).toBe(0.25);
    expect(feed.watched.has("b8")).toBe(true);
    expect(shown(feed)).toEqual(["b9", "a7", "a3", "a1"]);
  });
});

describe("FeedController just-watched cards", () => {
  test("a card marked watched stays until the watched toggle is used", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    feed.setWatchedMode("unwatched");
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("a filter edit drops it", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    const channelB = feed.channels.get("UCb") as Channel;
    feed.updateFilter("UCb", { ...channelB.filter, minDurationSeconds: 0 });
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("a move to another page drops it", () => {
    const { feed } = loaded([], null);
    feed.setWatched("a3", true);
    feed.pageChanged();
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

describe("FeedController watched modes", () => {
  test("watched lists only watched items and all lists both", () => {
    const { feed } = loaded(["a3", "b5"], null);
    expect(shown(feed)).toEqual(["a7", "a1"]);
    feed.setWatchedMode("watched");
    expect(shown(feed)).toEqual(["b5", "a3"]);
    feed.setWatchedMode("all");
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });

  test("the sidebar's unwatched counts ignore the mode", () => {
    const { feed } = loaded(["a3"], null);
    feed.setWatchedMode("watched");
    expect(feed.unwatchedCount).toBe(3);
  });

  test("a watched video played again stays among the watched until the mode changes", () => {
    const { feed } = loaded(["a3", "b5"], null);
    feed.setWatchedMode("watched");
    feed.recordProgress("a3", 5, 600, false, "later");
    expect(feed.watched.has("a3")).toBe(false);
    expect(shown(feed)).toEqual(["b5", "a3"]);
    feed.setWatchedMode("watched");
    expect(shown(feed)).toEqual(["b5"]);
  });

  test("the topic chips are counted over the mode's list", () => {
    const { feed } = loaded(["a3"], null);
    feed.items = [
      { ...video("a1", 1), categoryId: "10" },
      { ...video("a3", 3), categoryId: "20" },
    ];
    expect(feed.topicChips).toEqual(["10"]);
    feed.setWatchedMode("watched");
    expect(feed.topicChips).toEqual(["20"]);
  });

  test("auto-play moves to the next unwatched item, but not among the watched", () => {
    const { feed } = loaded(["b5"], null);
    expect(feed.autoplayNext("a7")).toBeNull();
    feed.setSetting("autoplay", true);
    expect(feed.autoplayNext("a7")?.title).toBe("a3");
    feed.setWatchedMode("all");
    expect(feed.autoplayNext("a7")?.title).toBe("a3");
    feed.setWatchedMode("watched");
    expect(feed.autoplayNext("b5")).toBeNull();
  });
});

describe("FeedController settings", () => {
  test("reads the synced settings and falls back to defaults", () => {
    const { feed } = loaded([], null, [], {
      feedSort: { at: 1, value: "title" },
      channelSort: { at: 1, value: "sideways" },
    });
    expect(feed.settings.feedSort).toBe("title");
    expect(feed.settings.channelSort).toBe("newest");
    expect(shown(feed)).toEqual(["a1", "a3", "a7", "b5"]);
  });

  test("a change applies at once and is saved", () => {
    const { feed, synced } = loaded([], null);
    feed.setSetting("feedSort", "title");
    expect(shown(feed)).toEqual(["a1", "a3", "a7", "b5"]);
    expect(synced.feedSort.value).toBe("title");
  });

  test("the random order holds while nothing loads", () => {
    const { feed } = loaded([], null);
    feed.setSetting("feedSort", "random");
    const order = shown(feed);
    feed.setWatched("a3", true);
    feed.setSetting("autoplay", true);
    expect(shown(feed)).toEqual(order);
  });

  test("a reshuffle puts the random order in another order", () => {
    const { feed } = loaded([], null);
    feed.setSetting("feedSort", "random");
    const orders = new Set<string>();
    for (let round = 0; round < 50; round += 1) {
      feed.reshuffle();
      orders.add(shown(feed).join());
    }
    expect(orders.size).toBeGreaterThan(1);
  });

  test("a reversed order is applied and saved", () => {
    const { feed, synced } = loaded([], null);
    feed.setSetting("feedSort", "titleReversed");
    expect(shown(feed)).toEqual(["b5", "a7", "a3", "a1"]);
    expect(synced.feedSort.value).toBe("titleReversed");
  });
});

describe("FeedController chips", () => {
  function withTopics(page: string | null = null): FeedController {
    const { feed } = loaded([], page);
    feed.items = [
      { ...video("a1", 1), categoryId: "10" },
      { ...video("b5", 5, "UCb"), categoryId: "10" },
      { ...video("a3", 3), categoryId: "20" },
      { ...video("a7", 7), categoryId: "27" },
    ];
    return feed;
  }

  test("lists the topics of the items shown, most common first", () => {
    expect(withTopics().topicChips).toEqual(["10", "27", "20"]);
    expect(withTopics("UCb").topicChips).toEqual(["10"]);
  });

  test("selected topics keep the items in any of them, and are saved", () => {
    const feed = withTopics();
    feed.toggleTopicChip("20");
    expect(shown(feed)).toEqual(["a3"]);
    feed.toggleTopicChip("27");
    expect(shown(feed)).toEqual(["a7", "a3"]);
    expect(feed.settings.topicChips).toEqual(["20", "27"]);
    feed.toggleTopicChip("20");
    expect(shown(feed)).toEqual(["a7"]);
  });

  test("the chip row is counted before the chips filter", () => {
    const feed = withTopics();
    feed.toggleTopicChip("27");
    expect(feed.topicChips).toEqual(["10", "27", "20"]);
  });

  test("hidden watched items don't count, and a selected chip with none stays", () => {
    const feed = withTopics();
    feed.toggleTopicChip("27");
    markOnly(feed, ["a7"]);
    expect(feed.topicChips).toEqual(["10", "20", "27"]);
    expect(shown(feed)).toEqual([]);
    expect(feed.emptiedBySelection).toBe(true);
  });

  test("an empty list is only caught up with unwatched and no chip selected", () => {
    const feed = withTopics();
    markOnly(feed, ["a1", "b5", "a3", "a7"]);
    expect(shown(feed)).toEqual([]);
    expect(feed.emptiedBySelection).toBe(false);
    feed.setSetting("timeChip", "week");
    expect(feed.emptiedBySelection).toBe(true);
    feed.setSetting("timeChip", "none");
    feed.setWatchedMode("all");
    expect(feed.emptiedBySelection).toBe(true);
  });

  test("a time or topic chip change drops a card that stayed", () => {
    const feed = withTopics();
    feed.setWatched("a3", true);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    feed.setSetting("feedSort", "newest");
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
    feed.toggleTopicChip("10");
    feed.toggleTopicChip("10");
    expect(shown(feed)).toEqual(["a7", "b5", "a1"]);
  });

  test("a topic saved by an older version is ignored", () => {
    const { feed } = loaded([], null, [], {
      topicChips: { at: 1, value: ["Music"] },
    });
    expect(feed.topicChips).toEqual([]);
    expect(shown(feed)).toEqual(["a7", "b5", "a3", "a1"]);
  });

  test("a channel's fetched items are listed whatever its filter keeps", () => {
    const feed = withTopics();
    const channelA = feed.channels.get("UCa") as Channel;
    feed.updateFilter("UCa", { ...channelA.filter, topics: ["27"] });
    expect(shown(feed)).toEqual(["a7", "b5"]);
    expect(feed.channelFetched("UCa").map(feedItemId)).toEqual([
      "a1",
      "a3",
      "a7",
    ]);
  });

  test("a time chip keeps only recent items", () => {
    const feed = withTopics();
    feed.items = [
      video("old", 1),
      { ...video("new", 2), publishedAt: new Date().toISOString() },
    ];
    feed.setSetting("timeChip", "week");
    expect(shown(feed)).toEqual(["new"]);
    feed.setSetting("timeChip", "none");
    expect(shown(feed)).toEqual(["new", "old"]);
  });

  test("the channel counts ignore the chips", () => {
    const feed = withTopics();
    feed.toggleTopicChip("27");
    markOnly(feed, ["a1"]);
    expect(feed.unwatchedByChannel).toEqual(
      new Map([
        ["UCa", 2],
        ["UCb", 1],
      ]),
    );
    expect(feed.unwatchedCount).toBe(3);
  });

  test("a channel that is off or filtered out has no count", () => {
    const feed = withTopics();
    const channelA = feed.channels.get("UCa") as Channel;
    feed.updateFilter("UCa", { ...channelA.filter, regex: "\\ba7\\b" });
    const channelB = feed.channels.get("UCb") as Channel;
    feed.updateFilter("UCb", { ...channelB.filter, enabled: false });
    expect(feed.unwatchedByChannel).toEqual(new Map([["UCa", 1]]));
  });
});

const HIDE_SHORTS: Channel["filter"] = {
  ...defaultFilter(),
  shortsFilter: "normal",
};

describe("FeedController groups", () => {
  test("a new group has a chip at once and is saved in one save", () => {
    const { feed, saves } = loaded([], null);
    expect(feed.groups).toEqual([]);
    feed.saveGroup(null, "Making", ["UCa", "UCb"]);
    expect(feed.groups).toEqual(["Making"]);
    expect(saves).toEqual([
      {
        filters: {
          UCa: { ...defaultFilter(), groups: ["Making"] },
          UCb: { ...defaultFilter(), groups: ["Making"] },
        },
      },
    ]);
    expect(feed.settings.groupChips).toEqual([]);
  });

  test("a selected group keeps its channels' items, and a topic narrows them", () => {
    const { feed, synced } = loaded([], null);
    feed.items = [
      { ...video("a1", 1), categoryId: "10" },
      { ...video("a3", 3), categoryId: "20" },
      { ...video("b5", 5, "UCb"), categoryId: "10" },
    ];
    feed.saveGroup(null, "Making", ["UCa"]);
    feed.toggleGroupChip("Making");
    expect(shown(feed)).toEqual(["a3", "a1"]);
    expect(synced.groupChips.value).toEqual(["Making"]);
    expect(feed.topicChips).toEqual(["10", "20"]);
    feed.toggleTopicChip("10");
    expect(shown(feed)).toEqual(["a1"]);
    feed.clearChips();
    expect(shown(feed)).toEqual(["b5", "a3", "a1"]);
    expect(feed.settings.channelGroupChips).toEqual([]);
  });

  test("a channel's page ignores the feed's groups", () => {
    const { feed } = loaded([], "UCb");
    feed.saveGroup(null, "Making", ["UCa"]);
    feed.toggleGroupChip("Making");
    expect(shown(feed)).toEqual(["b5"]);
    expect(feed.emptiedBySelection).toBe(false);
  });

  test("a group with nothing unwatched reads as a selection, not caught up", () => {
    const { feed } = loaded(["b5"], null);
    feed.saveGroup(null, "Making", ["UCb"]);
    expect(feed.emptiedBySelection).toBe(false);
    feed.toggleGroupChip("Making");
    expect(shown(feed)).toEqual([]);
    expect(feed.emptiedBySelection).toBe(true);
  });

  test("a name of no group filters nothing", () => {
    const { feed } = loaded([], null, [], {
      groupChips: { at: 1, value: ["Gone"] },
      channelGroupChips: { at: 1, value: ["Gone"] },
    });
    expect(shown(feed)).toHaveLength(4);
    expect(feed.emptiedBySelection).toBe(false);
  });

  test("the editor's save renames and changes channels in one save", () => {
    const { feed, saves } = loaded([], null);
    feed.saveGroup(null, "Making", ["UCa"]);
    feed.toggleGroupChip("Making");
    saves.length = 0;
    feed.saveGroup("Making", "Workshop", ["UCb"]);
    expect(saves).toEqual([
      {
        filters: {
          UCa: { ...defaultFilter(), groups: [] },
          UCb: { ...defaultFilter(), groups: ["Workshop"] },
        },
      },
    ]);
    expect(feed.groups).toEqual(["Workshop"]);
    expect(feed.settings.groupChips).toEqual(["Workshop"]);
    expect(shown(feed)).toEqual(["b5"]);
  });

  test("renaming and deleting follow through to the selected chips", () => {
    const { feed } = loaded([], null, [], {
      channelGroupChips: { at: 1, value: ["Making"] },
    });
    feed.saveGroup(null, "Making", ["UCa"]);
    feed.toggleGroupChip("Making");
    feed.saveGroup("Making", "Workshop", ["UCa"]);
    expect(feed.groups).toEqual(["Workshop"]);
    expect(feed.settings.groupChips).toEqual(["Workshop"]);
    expect(feed.settings.channelGroupChips).toEqual(["Workshop"]);
    feed.deleteGroup("Workshop");
    expect(feed.groups).toEqual([]);
    expect(feed.settings.groupChips).toEqual([]);
    expect(feed.settings.channelGroupChips).toEqual([]);
    expect(shown(feed)).toHaveLength(4);
  });
});

describe("needsShorts and covers", () => {
  test("only uploads with Shorts hidden or alone need the Shorts list", () => {
    expect(needsShorts(defaultFilter())).toBe(false);
    expect(needsShorts({ ...defaultFilter(), shortsFilter: "all" })).toBe(
      false,
    );
    expect(needsShorts(HIDE_SHORTS)).toBe(true);
    expect(needsShorts({ ...defaultFilter(), shortsFilter: "shorts" })).toBe(
      true,
    );
    expect(needsShorts({ ...HIDE_SHORTS, contentMode: "playlists" })).toBe(
      false,
    );
  });

  test("fetched items cover a filter of their mode, with Shorts marks when it filters on them", () => {
    const plain: ChannelItems = { mode: "videos", shorts: false, items: [] };
    expect(covers(plain, defaultFilter())).toBe(true);
    expect(covers(plain, HIDE_SHORTS)).toBe(false);
    expect(covers({ ...plain, shorts: true }, HIDE_SHORTS)).toBe(true);
    expect(covers({ ...plain, shorts: true }, defaultFilter())).toBe(true);
    expect(
      covers(plain, { ...defaultFilter(), contentMode: "playlists" }),
    ).toBe(false);
  });
});

describe("completeItems", () => {
  /** What completing `filter` from `have` asked for, and what came back. */
  async function completed(
    filter: Channel["filter"],
    have: ChannelItems | null,
  ): Promise<{ asked: string[]; result: ChannelItems }> {
    const asked: string[] = [];
    const result = await completeItems(
      { ...channel("UCa"), filter },
      have,
      async (wanted) => {
        asked.push("all");
        return {
          mode: wanted.filter.contentMode ?? "videos",
          shorts: needsShorts(wanted.filter),
          items: [],
        };
      },
      async (_wanted, fetched) => {
        asked.push("shorts");
        return { ...fetched, shorts: true };
      },
    );
    return { asked, result };
  }
  const plain: ChannelItems = { mode: "videos", shorts: false, items: [] };

  test("asks for nothing when what is fetched is enough", async () => {
    expect((await completed(defaultFilter(), plain)).asked).toEqual([]);
  });

  test("asks only for the Shorts list when uploads lack it", async () => {
    const { asked, result } = await completed(HIDE_SHORTS, plain);
    expect(asked).toEqual(["shorts"]);
    expect(result.shorts).toBe(true);
  });

  test("fetches everything with nothing fetched or the other mode", async () => {
    expect((await completed(HIDE_SHORTS, null)).asked).toEqual(["all"]);
    expect(
      (await completed({ ...defaultFilter(), contentMode: "playlists" }, plain))
        .asked,
    ).toEqual(["all"]);
  });
});

describe("fetchChannels", () => {
  const channels = Array.from({ length: 20 }, (_, index) =>
    channel(`UC${index}`),
  );
  const got = (mode: "videos" = "videos"): ChannelItems => ({
    mode,
    shorts: false,
    items: [],
  });

  test("a failed channel makes the load partial and the rest go on", async () => {
    const result = await fetchChannels(channels, async ({ channelId }) => {
      if (channelId === "UC3") {
        throw new Error("refused");
      }
      return got();
    });
    expect(Array.from(result.failed)).toEqual(["UC3"]);
    expect(result.fetched.size).toBe(19);
    expect(result.dailyLimit).toBe(false);
  });

  test("the daily limit stops the requests not yet sent and keeps what was fetched", async () => {
    const asked: string[] = [];
    const result = await fetchChannels(channels, async ({ channelId }) => {
      asked.push(channelId);
      await Promise.resolve();
      if (channelId === "UC7") {
        throw new DailyLimitError();
      }
      return got();
    });
    expect(result.dailyLimit).toBe(true);
    expect(asked.length).toBeLessThan(channels.length);
    expect(asked.length).toBeLessThanOrEqual(7 + 6 + 6);
    expect(result.fetched.size + result.failed.size).toBe(channels.length);
    expect(result.fetched.has("UC0")).toBe(true);
    expect(result.failed.has("UC19")).toBe(true);
    expect(asked).not.toContain("UC19");
  });

  test("reports each channel as it finishes: fetched, failed or skipped", async () => {
    const reported: number[] = [];
    await fetchChannels(
      channels,
      async ({ channelId }) => {
        await Promise.resolve();
        if (channelId === "UC2") {
          throw new Error("refused");
        } else if (channelId === "UC7") {
          throw new DailyLimitError();
        }
        return got();
      },
      (finished) => reported.push(finished),
    );
    expect(reported).toEqual(channels.map((_, index) => index + 1));
  });

  test("a refused token ends the fetch", async () => {
    await expect(
      fetchChannels(channels, async () => {
        throw new TokenExpiredError();
      }),
    ).rejects.toBeInstanceOf(TokenExpiredError);
  });
});

describe("Prefetch", () => {
  const channels = Array.from({ length: 8 }, (_, index) =>
    channel(`UC${index}`),
  );
  const hidingShorts = (source: Channel): Channel => ({
    ...source,
    filter: { ...source.filter, shortsFilter: "normal" },
  });

  /** A prefetch whose requests end only when released; `started` names each, "+shorts" for a Shorts list alone. */
  function held(): {
    prefetch: Prefetch;
    started: string[];
    release: (name: string, items?: FeedItem[] | Error) => void;
  } {
    const started: string[] = [];
    const finish = new Map<string, (items: FeedItem[] | Error) => void>();
    const request = (name: string): Promise<FeedItem[]> => {
      started.push(name);
      return new Promise<FeedItem[]>((resolve, reject) => {
        finish.set(name, (items) =>
          items instanceof Error ? reject(items) : resolve(items),
        );
      });
    };
    const prefetch = new Prefetch(
      async (wanted) => ({
        mode: wanted.filter.contentMode ?? "videos",
        shorts: needsShorts(wanted.filter),
        items: await request(wanted.channelId),
      }),
      async (wanted, fetched) => {
        await request(`${wanted.channelId}+shorts`);
        return { ...fetched, shorts: true };
      },
    );
    return {
      prefetch,
      started,
      release: (name, items) =>
        finish.get(name)?.(items ?? new Error("refused")),
    };
  }

  test("fetches nothing until it is told which channels", () => {
    expect(held().started).toEqual([]);
  });

  test("starts on six channels at once and hands over each one's items", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly(channels);
    expect(started).toEqual(["UC0", "UC1", "UC2", "UC3", "UC4", "UC5"]);
    const items = [video("v1", 1, "UC0")];
    release("UC0", items);
    expect(await prefetch.items("UC0")).toEqual({
      mode: "videos",
      shorts: false,
      items,
    });
    expect(started).toContain("UC6");
  });

  test("has nothing for a failed fetch or a channel it wasn't given", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly(channels.slice(0, 2));
    release("UC0", []);
    release("UC1");
    expect(await prefetch.items("UC1")).toBeNull();
    expect(await prefetch.items("UC2")).toBeNull();
    expect(started).toEqual(["UC0", "UC1"]);
  });

  test("a second set keeps what is fetched, starts what is new, and never starts what was dropped", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly(channels.slice(0, 7));
    prefetch.fetchOnly([channels[0], channels[7]]);
    const items = [video("v1", 1, "UC0")];
    release("UC0", items);
    expect((await prefetch.items("UC0"))?.items).toEqual(items);
    expect(await prefetch.items("UC6")).toBeNull();
    expect(started).toEqual(["UC0", "UC1", "UC2", "UC3", "UC4", "UC5", "UC7"]);
  });

  test("a channel dropped while being fetched has no items, and is not fetched again when it comes back", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly([channels[0], channels[1]]);
    prefetch.fetchOnly([channels[1]]);
    const items = [video("v1", 1, "UC0")];
    release("UC0", items);
    expect(await prefetch.items("UC0")).toBeNull();
    prefetch.fetchOnly([channels[0], channels[1]]);
    expect((await prefetch.items("UC0"))?.items).toEqual(items);
    expect(started).toEqual(["UC0", "UC1"]);
  });

  test("a Shorts choice made after the fetch adds only the Shorts list", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly([channels[0]]);
    const items = [video("v1", 1, "UC0")];
    release("UC0", items);
    expect((await prefetch.items("UC0"))?.shorts).toBe(false);
    prefetch.fetchOnly([hidingShorts(channels[0])]);
    await Promise.resolve();
    await Promise.resolve();
    release("UC0+shorts", []);
    expect(await prefetch.items("UC0")).toEqual({
      mode: "videos",
      shorts: true,
      items,
    });
    prefetch.fetchOnly([hidingShorts(channels[0])]);
    prefetch.fetchOnly([channels[0]]);
    expect(started).toEqual(["UC0", "UC0+shorts"]);
  });

  test("a Shorts choice made while a channel waits is fetched in one go", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly(channels.slice(0, 7));
    prefetch.fetchOnly(channels.slice(0, 7).map(hidingShorts));
    release("UC0", []);
    await new Promise((resolve) => setTimeout(resolve));
    expect(started).toContain("UC6");
    release("UC6", []);
    expect((await prefetch.items("UC6"))?.shorts).toBe(true);
    expect(started).not.toContain("UC6+shorts");
  });

  test("a Shorts list that fails leaves the uploads for the feed to add to", async () => {
    const { prefetch, release } = held();
    prefetch.fetchOnly([channels[0]]);
    release("UC0", []);
    await prefetch.items("UC0");
    prefetch.fetchOnly([hidingShorts(channels[0])]);
    await Promise.resolve();
    await Promise.resolve();
    release("UC0+shorts");
    expect(await prefetch.items("UC0")).toEqual({
      mode: "videos",
      shorts: false,
      items: [],
    });
  });

  test("after the daily limit refuses a request, no waiting channel is asked for", async () => {
    const { prefetch, started, release } = held();
    prefetch.fetchOnly(channels);
    release("UC0", new DailyLimitError());
    expect(await prefetch.items("UC0")).toBeNull();
    expect(await prefetch.items("UC6")).toBeNull();
    expect(await prefetch.items("UC7")).toBeNull();
    expect(started).toEqual(["UC0", "UC1", "UC2", "UC3", "UC4", "UC5"]);
  });
});

describe("FeedController with a video it hasn't loaded", () => {
  test("the player's length decides, as the feed has none", () => {
    const { feed } = loaded([], null);
    feed.recordProgress("elsewhere", 595, 600, false, "later");
    expect(feed.watched.has("elsewhere")).toBe(true);
  });
});

/** The extension and YouTube, faked for the tests of whole loads. */
interface FakeGoogle {
  /** what the extension answers a token request with; undefined is no answer */
  token: () => unknown;
  /** each subscribed channel's uploads, as video ids, newest first */
  uploads: Record<string, string[]>;
  /** the videos that are live now */
  live: Set<string>;
  /** whether YouTube refuses a request's token */
  refuses: (request: string, token: string) => boolean;
  /** whether YouTube answers a request with a server error */
  fails: (request: string) => boolean;
  /** every YouTube request made, as "list ids" */
  requests: string[];
}

describe("FeedController loads", () => {
  const realFetch = globalThis.fetch;
  const realError = console.error;
  let google: FakeGoogle;

  beforeAll(async () => {
    (globalThis as { chrome?: unknown }).chrome = {
      runtime: {
        sendMessage(
          _extensionId: string,
          message: { type: string },
          callback: (response: unknown) => void,
        ) {
          callback(
            message.type === "token" ? google.token() : { version: "1" },
          );
        },
      },
    };
    await recheckPlatform();
  });

  afterAll(() => {
    globalThis.fetch = realFetch;
    console.error = realError;
    delete (globalThis as { chrome?: unknown }).chrome;
  });

  beforeEach(() => {
    let minted = 0;
    google = {
      token: () => {
        minted += 1;
        return { accessToken: `token-${minted}`, expiresIn: 3600 };
      },
      uploads: { UCa: ["a2", "a1"], UCb: ["b1"] },
      live: new Set(),
      refuses: () => false,
      fails: () => false,
      requests: [],
    };
    forgetToken();
    expectAccount(null);
    console.error = () => undefined;
    globalThis.fetch = (async (
      input: string | URL | Request,
      init?: RequestInit,
    ) => {
      const url = new URL(String(input));
      const list = url.pathname.split("/").at(-1) ?? "";
      const ids =
        url.searchParams.get("playlistId") ?? url.searchParams.get("id") ?? "";
      const request = ids ? `${list} ${ids}` : list;
      const token = new Headers(init?.headers).get("Authorization") ?? "";
      google.requests.push(request);
      if (google.refuses(request, token.replace("Bearer ", ""))) {
        return new Response("{}", { status: 401 });
      } else if (google.fails(request)) {
        return new Response("{}", { status: 500 });
      } else if (list === "subscriptions") {
        return Response.json({
          items: Object.keys(google.uploads).map((channelId) => ({
            snippet: {
              title: channelId,
              resourceId: { channelId },
              thumbnails: {},
            },
          })),
        });
      } else if (list === "playlistItems") {
        const videoIds = google.uploads[`UC${ids.slice(2)}`] ?? [];
        return Response.json({
          items: videoIds.map((videoId, index) => ({
            snippet: {
              title: videoId,
              description: "",
              publishedAt: `2026-01-${String(20 - index).padStart(2, "0")}T00:00:00Z`,
              thumbnails: {},
            },
            contentDetails: { videoId },
          })),
        });
      } else {
        return Response.json({
          items: ids.split(",").map((id) => ({
            id,
            snippet: {
              liveBroadcastContent: google.live.has(id) ? "live" : "none",
            },
            contentDetails: { duration: google.live.has(id) ? "P0D" : "PT10M" },
          })),
        });
      }
    }) as typeof fetch;
  });

  /** A controller over the faked account, on the feed (null) or a channel's page, and how often it called the token lost. */
  function controller(page: string | null = null): {
    feed: FeedController;
    lost: () => number;
  } {
    let lost = 0;
    const store = {
      load: async () => undefined,
      followedIds: () => [],
      channels: (subscribed: { channelId: string; title: string }[]) =>
        new Map(
          subscribed.map((info) => [
            info.channelId,
            { ...info, thumbnail: "", filter: defaultFilter() },
          ]),
        ),
      noteLoaded: () => undefined,
      watchedEntry: () => undefined,
      settings: () => ({}),
      flush: () => undefined,
    } as unknown as SyncStore;
    const session = {
      account: { channelId: "UCme" },
      ready: true,
      tokenLost: () => {
        lost += 1;
      },
    } as unknown as Session;
    const router = {
      route: { channel: page, item: null },
    } as unknown as Router;
    return {
      feed: new FeedController(session, store, router),
      lost: () => lost,
    };
  }

  /** Start the controller on a faked page; `fire` runs the listeners of an event and waits for what they began. */
  function started(feed: FeedController): {
    fire: (type: string) => Promise<void>;
    stop: () => void;
  } {
    const listeners = new Map<string, () => void>();
    const target = {
      visibilityState: "visible",
      addEventListener: (type: string, listener: () => void) =>
        void listeners.set(type, listener),
      removeEventListener: (type: string) => void listeners.delete(type),
    };
    const page = globalThis as { document?: unknown; window?: unknown };
    page.document = target;
    page.window = target;
    const stop = feed.start();
    return {
      fire: async (type) => {
        listeners.get(type)?.();
        // a load is under way when the listener started one
        while (feed.loading) {
          await new Promise((resolve) => setTimeout(resolve, 0));
        }
      },
      stop: () => {
        stop();
        delete page.document;
        delete page.window;
      },
    };
  }

  test("a failed load is tried again on returning, a load that worked is not", async () => {
    const { feed } = controller();
    const { fire, stop } = started(feed);
    google.fails = (request) => request === "subscriptions";
    await feed.load();
    expect(feed.error).not.toBeNull();
    google.fails = () => false;
    await fire("visibilitychange");
    expect(feed.error).toBeNull();
    expect(shown(feed)).toEqual(["a2", "b1", "a1"]);
    const requests = google.requests.length;
    await fire("visibilitychange");
    expect(google.requests.length).toBe(requests);
    stop();
  });

  test("coming back online loads again only while an error shows", async () => {
    const { feed } = controller();
    const { fire, stop } = started(feed);
    google.fails = (request) => request === "subscriptions";
    await feed.load();
    google.fails = () => false;
    await fire("online");
    expect(feed.error).toBeNull();
    expect(shown(feed)).toEqual(["a2", "b1", "a1"]);
    const requests = google.requests.length;
    await fire("online");
    expect(google.requests.length).toBe(requests);
    stop();
  });

  test("a load shows every channel's uploads", async () => {
    const { feed } = controller();
    await feed.load();
    expect(shown(feed)).toEqual(["a2", "b1", "a1"]);
    expect(feed.error).toBeNull();
  });

  test("a token refused mid-load keeps the channels already fetched", async () => {
    const { feed } = controller();
    google.refuses = (request, token) =>
      request === "playlistItems UUb" && token === "token-1";
    await feed.load();
    expect(shown(feed)).toEqual(["a2", "b1", "a1"]);
    const count = (request: string) =>
      google.requests.filter((made) => made === request).length;
    expect(count("playlistItems UUa")).toBe(1);
    expect(count("videos a2,a1")).toBe(1);
    expect(count("playlistItems UUb")).toBe(2);
  });

  test("the page of a channel the feed doesn't load waits for the first load", async () => {
    const { feed } = controller("UCz");
    await feed.ensureChannelItems();
    expect(google.requests).toEqual([]);
    const load = feed.load();
    await feed.ensureChannelItems();
    await load;
    while (feed.channelLoading) {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    expect(
      google.requests.filter((made) => made === "playlistItems UUz"),
    ).toHaveLength(1);
    expect(google.requests.indexOf("playlistItems UUz")).toBeGreaterThan(
      google.requests.indexOf("playlistItems UUb"),
    );
  });

  test("a later load asks for the details of new and live videos only", async () => {
    const { feed } = controller();
    google.live.add("b1");
    await feed.load();
    const first = feed.items;
    google.requests.length = 0;
    await feed.load();
    expect(google.requests.filter((made) => made.startsWith("videos"))).toEqual(
      ["videos b1"],
    );
    expect(feed.items.toSorted(byId)).toEqual(first.toSorted(byId));

    google.uploads.UCa = ["a3", "a2", "a1"];
    google.live.clear();
    google.requests.length = 0;
    await feed.load();
    expect(
      google.requests.filter((made) => made.startsWith("videos")).toSorted(),
    ).toEqual(["videos a3", "videos b1"]);
    expect(
      feed.items.map((item) => item.kind === "video" && item.durationSeconds),
    ).toEqual([600, 600, 600, 600]);
  });

  test("an extension that doesn't answer is an error, not a lost session", async () => {
    const { feed, lost } = controller();
    google.token = () => undefined;
    await feed.load();
    expect(lost()).toBe(0);
    expect(feed.error).toBe("The SubTube extension didn't answer.");
  });

  test("no token without a sign-in is a lost session", async () => {
    const { feed, lost } = controller();
    google.token = () => ({ error: "interaction required" });
    await feed.load();
    expect(lost()).toBe(1);
    expect(feed.error).toBeNull();
  });

  test("a silent sign-in that failed by itself is an error, not a lost session", async () => {
    const { feed, lost } = controller();
    google.token = () => ({
      error: "Authorization page could not be loaded.",
      signInRequired: false,
    });
    await feed.load();
    expect(lost()).toBe(0);
    expect(feed.error).toBe(UNREACHABLE_MESSAGE);
  });
});
