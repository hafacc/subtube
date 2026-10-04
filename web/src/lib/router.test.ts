import { describe, expect, test } from "bun:test";
import { parseRoute, routeToUrl } from "./router";

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
