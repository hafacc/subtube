import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/player.json";
import { feedItemId } from "./feed-item";
import {
  afterRoute,
  cardHolds,
  clipped,
  endOutcome,
  largeBox,
  MINIMIZED_MARGIN,
  MINIMIZED_ROOM,
  minimizedBox,
  nextInQueue,
  type PlayerPlace,
  type Playing,
  type PlayQueue,
  routeItem,
  visibleFraction,
} from "./player";
import { PlayerController, type PlayerFeed } from "./player.svelte";
import type { Route } from "./router";
import type { FeedItem, Video } from "./types";
import type { WatchedMode } from "./watched-mode";

function video(id: string): Video {
  return {
    kind: "video",
    videoId: id,
    channelId: "UCa",
    channelTitle: "UCa",
    title: id,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    durationSeconds: 600,
  };
}

const LIST: FeedItem[] = [video("a"), video("b"), video("c"), video("d")];
const QUEUE: PlayQueue = { items: LIST, mode: "unwatched" };

type SharedCase = { name: string } & (
  | {
      op: "next";
      items: string[];
      mode: WatchedMode;
      watched: string[];
      autoplay: boolean;
      ended: string;
      expected: string | null;
    }
  | {
      op: "end";
      place: PlayerPlace;
      next: boolean;
      nextCardShowing: boolean;
      expected:
        | { kind: "next"; place: PlayerPlace }
        | { kind: "stay" | "close" };
    }
  | {
      op: "minimizedSize";
      viewWidth: number;
      expected: { width: number; height: number };
    }
);

describe("shared player fixture", () => {
  for (const shared of fixture.cases as SharedCase[]) {
    test(shared.name, () => {
      if (shared.op === "next") {
        const next = nextInQueue(
          { items: shared.items.map(video), mode: shared.mode },
          shared.ended,
          new Set(shared.watched),
          shared.autoplay,
        );
        expect(next === null ? null : feedItemId(next)).toBe(shared.expected);
      } else if (shared.op === "end") {
        const outcome = endOutcome(
          shared.place,
          shared.next ? video("next") : null,
          shared.nextCardShowing,
        );
        expect(
          outcome.kind === "next"
            ? { kind: outcome.kind, place: outcome.place }
            : { kind: outcome.kind },
        ).toEqual(shared.expected);
      } else {
        expect(shared.op).toBe("minimizedSize");
        const { width, height } = minimizedBox(
          { width: shared.viewWidth, height: 900 },
          0,
        );
        expect({ width, height }).toEqual(shared.expected);
      }
    });
  }
});

describe("nextInQueue", () => {
  test("is the next unwatched item after the ended one", () => {
    const next = nextInQueue(QUEUE, "a", new Set(["a", "b"]), true);
    expect(next).toBe(LIST[2]);
  });

  test("is nothing with auto-play off", () => {
    expect(nextInQueue(QUEUE, "a", new Set(), false)).toBeNull();
  });

  test("is nothing for a list of watched items", () => {
    const queue: PlayQueue = { items: LIST, mode: "watched" };
    expect(nextInQueue(queue, "a", new Set(), true)).toBeNull();
  });

  test("moves on in a list of all items", () => {
    const queue: PlayQueue = { items: LIST, mode: "all" };
    expect(nextInQueue(queue, "c", new Set(), true)).toBe(LIST[3]);
  });

  test("is nothing at the end, or for an item not in the list", () => {
    expect(nextInQueue(QUEUE, "d", new Set(), true)).toBeNull();
    expect(nextInQueue(QUEUE, "z", new Set(), true)).toBeNull();
    expect(nextInQueue(QUEUE, "b", new Set(["c", "d"]), true)).toBeNull();
  });
});

describe("endOutcome", () => {
  test("the next item plays where the player is", () => {
    expect(endOutcome("large", LIST[1], false)).toEqual({
      kind: "next",
      item: LIST[1],
      place: "large",
    });
    expect(endOutcome("minimized", LIST[1], true)).toEqual({
      kind: "next",
      item: LIST[1],
      place: "minimized",
    });
    expect(endOutcome("card", LIST[1], true)).toEqual({
      kind: "next",
      item: LIST[1],
      place: "card",
    });
  });

  test("a card that is not on the page gives the next item to the corner", () => {
    expect(endOutcome("card", LIST[1], false)).toEqual({
      kind: "next",
      item: LIST[1],
      place: "minimized",
    });
  });

  test("with nothing next, large and minimized stay and a card's player closes", () => {
    expect(endOutcome("large", null, false)).toEqual({ kind: "stay" });
    expect(endOutcome("minimized", null, false)).toEqual({ kind: "stay" });
    expect(endOutcome("card", null, false)).toEqual({ kind: "close" });
  });
});

describe("afterRoute", () => {
  const playing: Playing = {
    item: { kind: "video", id: "a" },
    place: "large",
    page: null,
    queue: QUEUE,
  };

  test("losing the item minimizes a large player and leaves others alone", () => {
    expect(afterRoute(playing, null, null)).toEqual({
      ...playing,
      place: "minimized",
    });
    const inCard: Playing = { ...playing, place: "card" };
    expect(afterRoute(inCard, null, "UCb")).toBe(inCard);
    expect(afterRoute(null, null, null)).toBeNull();
  });

  test("the playing item in the URL makes the player large, list kept", () => {
    const minimized: Playing = { ...playing, place: "minimized" };
    expect(afterRoute(minimized, playing.item, "UCb")).toEqual(playing);
    expect(afterRoute(playing, playing.item, null)).toBe(playing);
  });

  test("any other item is a link: large, with no list", () => {
    expect(afterRoute(playing, { kind: "video", id: "z" }, "UCb")).toEqual({
      item: { kind: "video", id: "z" },
      place: "large",
      page: "UCb",
      queue: null,
    });
    expect(afterRoute(null, { kind: "playlist", id: "a" }, null)).toEqual({
      item: { kind: "playlist", id: "a" },
      place: "large",
      page: null,
      queue: null,
    });
  });
});

describe("boxes", () => {
  const view = { top: 100, left: 0, width: 400, height: 600 };

  test("visibleFraction is the share of the box inside the view", () => {
    const box = { top: 0, left: 0, width: 400, height: 200 };
    expect(visibleFraction(box, view)).toBe(0.5);
    expect(visibleFraction({ ...box, top: 300 }, view)).toBe(1);
    expect(visibleFraction({ ...box, top: 700 }, view)).toBe(0);
  });

  test("a card holds the player when half of it shows and it is big enough", () => {
    expect(cardHolds({ top: 0, left: 0, width: 400, height: 200 }, view)).toBe(
      true,
    );
    expect(cardHolds({ top: -1, left: 0, width: 400, height: 200 }, view)).toBe(
      false,
    );
    expect(
      cardHolds({ top: 300, left: 0, width: 240, height: 135 }, view),
    ).toBe(false);
  });

  test("clipped is the part inside the view", () => {
    expect(
      clipped({ top: 0, left: 50, width: 400, height: 200 }, view),
    ).toEqual({ top: 100, left: 50, width: 350, height: 100 });
    expect(
      clipped({ top: 0, left: 0, width: 400, height: 100 }, view),
    ).toBeNull();
  });

  test("the minimized box is 356 by 200, 16 from the bottom right corner", () => {
    expect(minimizedBox({ width: 1440, height: 900 }, 0)).toEqual({
      top: 684,
      left: 1068,
      width: 356,
      height: 200,
    });
  });

  test("the room kept under a list is the minimized box and its margins, at any width", () => {
    for (const width of [320, 390, 760, 1440]) {
      const { top } = minimizedBox({ width, height: 900 }, 0);
      expect(MINIMIZED_ROOM).toBe(900 - top + MINIMIZED_MARGIN);
    }
  });

  test("the minimized box sits beside an open panel", () => {
    expect(minimizedBox({ width: 1440, height: 900 }, 320).left).toBe(748);
  });

  test("a window too narrow gives the width it has, never under 200 high", () => {
    expect(minimizedBox({ width: 340, height: 700 }, 0)).toEqual({
      top: 484,
      left: 16,
      width: 308,
      height: 200,
    });
  });

  test("the large box leaves room for the bar above it", () => {
    const box = largeBox({ width: 1440, height: 900 });
    expect(box.width).toBe(1344);
    expect(box.height).toBe(756);
    expect(box.left).toBe(48);
    expect(box.top - 37).toBeGreaterThanOrEqual(48);
    expect(box.top + box.height).toBeLessThanOrEqual(900 - 48);
    const short = largeBox({ width: 1440, height: 500 });
    expect(short.top - 37).toBeGreaterThanOrEqual(16);
    expect(short.top + short.height).toBeLessThanOrEqual(500 - 16);
    expect(short.width / short.height).toBeCloseTo(16 / 9, 1);
  });
});

/** A controller over a fake feed and router, with the routes it went to. */
function controller(
  options: { narrow?: boolean; autoplay?: boolean; mode?: WatchedMode } = {},
) {
  const state = {
    feed: LIST as readonly FeedItem[],
    watched: new Set<string>(),
    watchedMode: options.mode ?? ("unwatched" as WatchedMode),
    settings: { autoplay: options.autoplay ?? true },
    narrow: options.narrow ?? false,
    fullScreen: false,
  };
  const feed: PlayerFeed = {
    get feed() {
      return state.feed;
    },
    get watched() {
      return state.watched;
    },
    get watchedMode() {
      return state.watchedMode;
    },
    get settings() {
      return state.settings;
    },
    autoplayNext: () => null,
  };
  const entries: Route[] = [{ channel: null, item: null }];
  let current = 0;
  const moves: string[] = [];
  const router = {
    get route(): Route {
      return entries[current] as Route;
    },
    open(route: Route) {
      moves.push("open");
      entries.splice(current + 1, entries.length, route);
      current += 1;
      player.routeChanged(route.item);
    },
    replace(route: Route) {
      moves.push("replace");
      entries[current] = route;
      player.routeChanged(route.item);
    },
    close() {
      moves.push("close");
      if (current > 0) {
        current -= 1;
      } else {
        entries[0] = { channel: router.route.channel, item: null };
      }
      player.routeChanged(router.route.item);
    },
    /** The browser's Back. */
    back() {
      current -= 1;
      player.routeChanged(router.route.item);
    },
    /** The browser's Forward. */
    forward() {
      current += 1;
      player.routeChanged(router.route.item);
    },
  };
  const player: PlayerController = new PlayerController(
    feed,
    router,
    () => state.narrow,
    () => state.fullScreen,
  );
  return { player, router, state, moves, entries };
}

describe("PlayerController in a wide window", () => {
  test("a card plays large with its item in the URL", () => {
    const { player, router } = controller();
    player.play(LIST[0] as FeedItem);
    expect(player.playing?.place).toBe("large");
    expect(router.route.item).toEqual({ kind: "video", id: "a" });
  });

  test("minimize drops the item from the URL and keeps playing", () => {
    const { player, router } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    expect(player.playing?.place).toBe("minimized");
    expect(player.playing?.item.id).toBe("a");
    expect(router.route.item).toBeNull();
  });

  test("Back from large minimizes; Back while minimized keeps the player", () => {
    const { player, router } = controller();
    router.open({ channel: "UCb", item: null });
    player.play(LIST[0] as FeedItem);
    router.back();
    expect(player.playing?.place).toBe("minimized");
    router.back();
    expect(router.route.channel).toBeNull();
    expect(player.playing?.place).toBe("minimized");
  });

  test("Forward onto the playing item makes it large, and minimizing goes back again", () => {
    const { player, router, entries } = controller();
    router.open({ channel: "UCb", item: null });
    player.play(LIST[0] as FeedItem);
    router.back();
    router.forward();
    expect(player.playing?.place).toBe("large");
    expect(player.playing?.queue?.items).toEqual(LIST);
    player.minimize();
    expect(player.playing?.place).toBe("minimized");
    expect(router.route).toEqual({ channel: "UCb", item: null });
    expect(entries).toHaveLength(3);
    router.forward();
    expect(player.playing?.place).toBe("large");
  });

  test("the playing item is known wherever the player is drawn", () => {
    const { player } = controller();
    expect(player.isPlaying("a")).toBe(false);
    player.play(LIST[0] as FeedItem);
    expect(player.isPlaying("a")).toBe(true);
    expect(player.isPlaying("b")).toBe(false);
    player.minimize();
    expect(player.isPlaying("a")).toBe(true);
    expect(player.inCard("a")).toBe(false);
    player.close();
    expect(player.isPlaying("a")).toBe(false);
  });

  test("going to another page keeps a minimized player", () => {
    const { player, router } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    router.open({ channel: "UCb", item: null });
    player.pageChanged();
    expect(player.playing?.place).toBe("minimized");
  });

  test("expand makes it large over the page showing", () => {
    const { player, router } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    router.open({ channel: "UCb", item: null });
    player.expand();
    expect(player.playing?.place).toBe("large");
    expect(router.route).toEqual({
      channel: "UCb",
      item: { kind: "video", id: "a" },
    });
  });

  test("close removes the player and the item from the URL", () => {
    const { player, router } = controller();
    player.play(LIST[0] as FeedItem);
    player.close();
    expect(player.playing).toBeNull();
    expect(router.route.item).toBeNull();
  });

  test("closing a minimized player leaves the URL alone", () => {
    const { player, moves } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    moves.length = 0;
    player.close();
    expect(player.playing).toBeNull();
    expect(moves).toEqual([]);
  });

  test("another card replaces a minimized player, large", () => {
    const { player } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    player.play(LIST[2] as FeedItem);
    expect(player.playing?.item.id).toBe("c");
    expect(player.playing?.place).toBe("large");
  });

  test("the end plays the next of the list it started from, in the same size", () => {
    const { player, router, state, moves } = controller();
    player.play(LIST[0] as FeedItem);
    player.minimize();
    router.open({ channel: "UCb", item: null });
    state.feed = [video("x"), video("y")];
    state.watchedMode = "watched";
    state.watched = new Set(["a", "b"]);
    player.pageChanged();
    player.ended("a");
    expect(player.playing?.item.id).toBe("c");
    expect(player.playing?.place).toBe("minimized");
    expect(router.route.item).toBeNull();
    moves.length = 0;
    player.expand();
    player.ended("c");
    expect(player.playing?.item.id).toBe("d");
    expect(player.playing?.place).toBe("large");
    expect(moves).toEqual(["open", "replace"]);
    expect(router.route.item).toEqual({ kind: "video", id: "d" });
  });

  test("with nothing next, large and minimized stay until closed", () => {
    const { player } = controller({ autoplay: false });
    player.play(LIST[0] as FeedItem);
    player.ended("a");
    expect(player.playing?.item.id).toBe("a");
    expect(player.playing?.place).toBe("large");
    player.minimize();
    player.ended("a");
    expect(player.playing?.item.id).toBe("a");
    expect(player.playing?.place).toBe("minimized");
    player.close();
    expect(player.playing).toBeNull();
  });

  test("an end of something that is not playing does nothing", () => {
    const { player } = controller();
    player.play(LIST[0] as FeedItem);
    player.ended("b");
    expect(player.playing?.item.id).toBe("a");
  });

  test("a link plays large and Back minimizes it", () => {
    const { player, router } = controller();
    router.open({ channel: null, item: { kind: "video", id: "z" } });
    expect(player.playing).toEqual({
      item: { kind: "video", id: "z" },
      place: "large",
      page: null,
      queue: null,
    });
    router.back();
    expect(player.playing?.place).toBe("minimized");
  });
});

describe("PlayerController in a narrow window", () => {
  test("a card plays in the card, with nothing in the URL", () => {
    const { player, router } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    expect(player.inCard("b")).toBe(true);
    expect(player.inCard("a")).toBe(false);
    expect(router.route.item).toBeNull();
  });

  test("leaving the page, or the card leaving the list, minimizes", () => {
    const first = controller({ narrow: true });
    first.player.play(LIST[1] as FeedItem);
    first.router.open({ channel: "UCb", item: null });
    first.player.pageChanged();
    expect(first.player.playing?.place).toBe("minimized");

    const second = controller({ narrow: true });
    second.player.play(LIST[1] as FeedItem);
    second.state.feed = [video("a")];
    second.player.pageChanged();
    expect(second.player.playing?.place).toBe("minimized");
  });

  test("a window that became wide minimizes a card's player", () => {
    const { player, state } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    state.narrow = false;
    player.pageChanged();
    expect(player.playing?.place).toBe("minimized");
  });

  test("a window that is wide only while something fills the screen keeps the card's player", () => {
    const { player, state } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    state.narrow = false;
    state.fullScreen = true;
    player.pageChanged();
    expect(player.inCard("b")).toBe(true);
    player.cardLost();
    expect(player.inCard("b")).toBe(true);
    state.narrow = true;
    state.fullScreen = false;
    player.pageChanged();
    expect(player.inCard("b")).toBe(true);
    state.narrow = false;
    player.pageChanged();
    expect(player.playing?.place).toBe("minimized");
  });

  test("a card that can no longer hold the player gives it to the corner", () => {
    const { player } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    player.cardLost();
    expect(player.playing?.place).toBe("minimized");
  });

  test("expand goes back to the card's page and into the card", () => {
    const { player, router } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    router.open({ channel: "UCb", item: null });
    player.pageChanged();
    player.expand();
    expect(router.route).toEqual({ channel: null, item: null });
    expect(player.inCard("b")).toBe(true);
  });

  test("expand is large when the page no longer lists the card", () => {
    const { player, router, state } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    state.feed = [video("a")];
    player.pageChanged();
    player.expand();
    expect(player.playing?.place).toBe("large");
    expect(router.route.item).toEqual({ kind: "video", id: "b" });
  });

  test("expand from another page, with the card gone, is one entry: Back returns there minimized", () => {
    const { player, router, state, entries } = controller({ narrow: true });
    player.play(LIST[1] as FeedItem);
    router.open({ channel: "UCb", item: null });
    state.feed = [video("x")];
    player.pageChanged();
    player.expand();
    expect(player.playing?.place).toBe("large");
    expect(router.route).toEqual({
      channel: null,
      item: { kind: "video", id: "b" },
    });
    expect(entries).toHaveLength(3);
    router.back();
    expect(router.route).toEqual({ channel: "UCb", item: null });
    expect(player.playing?.place).toBe("minimized");
  });

  test("the end moves to the next card on the page, or to the corner", () => {
    const { player, state } = controller({ narrow: true });
    player.play(LIST[0] as FeedItem);
    player.ended("a");
    expect(player.inCard("b")).toBe(true);
    state.feed = [video("b")];
    player.ended("b");
    expect(player.playing?.item.id).toBe("c");
    expect(player.playing?.place).toBe("minimized");
  });

  test("with auto-play off the end closes a card's player", () => {
    const { player } = controller({ narrow: true, autoplay: false });
    player.play(LIST[0] as FeedItem);
    player.ended("a");
    expect(player.playing).toBeNull();
  });
});

test("routeItem names an item as the URL does", () => {
  expect(routeItem(LIST[0] as FeedItem)).toEqual({ kind: "video", id: "a" });
});
