import { afterAll, describe, expect, test } from "bun:test";
import { parseRoute, routeToUrl } from "./router";
import { Router } from "./router.svelte";

describe("parseRoute", () => {
  test("empty search is the feed", () => {
    expect(parseRoute("")).toEqual({ channel: null, item: null });
  });

  test("?v opens a video over the feed", () => {
    expect(parseRoute("?v=abc")).toEqual({
      channel: null,
      item: { kind: "video", id: "abc" },
    });
  });

  test("?list opens a playlist", () => {
    expect(parseRoute("?list=PL1")).toEqual({
      channel: null,
      item: { kind: "playlist", id: "PL1" },
    });
  });

  test("?channel is a background with no open item", () => {
    expect(parseRoute("?channel=UC1")).toEqual({ channel: "UC1", item: null });
  });

  test("channel + video keeps both (player layered over the channel)", () => {
    expect(parseRoute("?channel=UC1&v=abc")).toEqual({
      channel: "UC1",
      item: { kind: "video", id: "abc" },
    });
  });

  test("video wins when both v and list are present", () => {
    expect(parseRoute("?v=abc&list=PL1").item).toEqual({
      kind: "video",
      id: "abc",
    });
  });

  test("an empty channel param is stripped to no channel", () => {
    expect(parseRoute("?channel=&v=abc").channel).toBeNull();
  });
});

describe("routeToUrl", () => {
  test("round-trips through parseRoute and keeps the path", () => {
    const route = {
      channel: "UC1",
      item: { kind: "video" as const, id: "abc" },
    };
    const url = routeToUrl(route, "/app/");
    expect(url).toBe("/app/?channel=UC1&v=abc");
    expect(parseRoute(url.slice(url.indexOf("?")))).toEqual(route);
  });

  test("the bare feed is just the path", () => {
    expect(routeToUrl({ channel: null, item: null }, "/")).toBe("/");
  });
});

/** A window with a browser's history: entries with their state, and Back and Forward. */
function fakeWindow(entries: { search: string; state: unknown }[]) {
  let current = entries.length - 1;
  let onPop: (event: { state: unknown }) => void = () => undefined;
  const go = (offset: number): void => {
    current += offset;
    onPop({ state: entries[current]?.state });
  };
  const write = (replaced: unknown, url: string): void => {
    const query = url.indexOf("?");
    entries[current] = {
      search: query === -1 ? "" : url.slice(query),
      state: replaced,
    };
  };
  const fake = {
    location: {
      pathname: "/",
      get search(): string {
        return entries[current]?.search ?? "";
      },
    },
    history: {
      get state(): unknown {
        return entries[current]?.state;
      },
      pushState(pushed: unknown, _unused: string, url: string) {
        entries.splice(current + 1);
        current += 1;
        write(pushed, url);
      },
      replaceState(replaced: unknown, _unused: string, url: string) {
        write(replaced, url);
      },
      back: () => go(-1),
    },
    addEventListener(_type: string, listener: typeof onPop) {
      onPop = listener;
    },
  };
  return { fake, entries, forward: () => go(1), back: () => go(-1) };
}

describe("Router", () => {
  const ITEM = { kind: "video", id: "abc" } as const;
  const realWindow: unknown = Reflect.get(globalThis, "window");

  afterAll(() => {
    Object.assign(globalThis, { window: realWindow });
  });

  function routerOver(search: string) {
    const browser = fakeWindow([{ search, state: null }]);
    Object.assign(globalThis, { window: browser.fake });
    return { router: new Router(), ...browser };
  }

  test("closing an item the app opened goes back", () => {
    const { router, entries } = routerOver("");
    router.open({ channel: null, item: ITEM });
    router.close();
    expect(router.route).toEqual({ channel: null, item: null });
    expect(entries.map(({ search }) => search)).toEqual(["", "?v=abc"]);
  });

  test("closing a link's item strips it in place", () => {
    const { router, entries } = routerOver("?channel=UCa&v=abc");
    router.close();
    expect(router.route).toEqual({ channel: "UCa", item: null });
    expect(entries.map(({ search }) => search)).toEqual(["?channel=UCa"]);
  });

  test("closing after Back and Forward still goes back", () => {
    const { router, entries, back, forward } = routerOver("");
    router.open({ channel: "UCa", item: null });
    router.open({ channel: "UCa", item: ITEM });
    back();
    forward();
    expect(router.route.item).toEqual(ITEM);
    router.close();
    expect(router.route).toEqual({ channel: "UCa", item: null });
    expect(entries.map(({ search }) => search)).toEqual([
      "",
      "?channel=UCa",
      "?channel=UCa&v=abc",
    ]);
  });

  test("a replaced entry keeps its place, also over a reload", () => {
    const { router, entries } = routerOver("");
    router.open({ channel: null, item: ITEM });
    router.replace({ channel: null, item: { kind: "video", id: "next" } });
    expect(entries.map(({ search }) => search)).toEqual(["", "?v=next"]);
    const reloaded = fakeWindow(entries);
    Object.assign(globalThis, { window: reloaded.fake });
    const second = new Router();
    expect(second.route.item).toEqual({ kind: "video", id: "next" });
    second.close();
    expect(second.route).toEqual({ channel: null, item: null });
    expect(entries.map(({ search }) => search)).toEqual(["", "?v=next"]);
  });
});
