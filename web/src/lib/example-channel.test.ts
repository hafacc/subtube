import { describe, expect, test } from "bun:test";
import { canBeExample, pickExampleChannel } from "./example-channel";
import { defaultFilter } from "./sync-merge";
import type { Channel, ChannelFilter, Video } from "./types";

function channel(
  channelId: string,
  changes: Partial<ChannelFilter> = {},
): Channel {
  return {
    channelId,
    title: channelId,
    thumbnail: "",
    filter: { ...defaultFilter(), ...changes },
  };
}

function video(id: string, day: number, isShort: boolean): Video {
  return {
    kind: "video",
    videoId: id,
    channelId: "UC1",
    channelTitle: "Chan",
    title: id,
    description: "",
    publishedAt: `2026-01-${String(day).padStart(2, "0")}T00:00:00Z`,
    thumbnail: "",
    isShort,
  };
}

describe("canBeExample", () => {
  test("needs on, uploads, and no only-matches pattern", () => {
    expect(canBeExample(channel("UCa"))).toBe(true);
    expect(canBeExample(channel("UCa", { enabled: false }))).toBe(false);
    expect(canBeExample(channel("UCa", { contentMode: "playlists" }))).toBe(
      false,
    );
    expect(canBeExample(channel("UCa", { mode: "include", regex: "x" }))).toBe(
      false,
    );
    expect(canBeExample(channel("UCa", { mode: "exclude", regex: "x" }))).toBe(
      true,
    );
  });
});

describe("pickExampleChannel", () => {
  test("prefers the most Shorts", () => {
    const items = new Map([
      ["UCa", [video("a1", 9, false), video("a2", 8, true)]],
      ["UCb", [video("b1", 1, true), video("b2", 2, true)]],
    ]);
    expect(
      pickExampleChannel([channel("UCa"), channel("UCb")], items)?.channelId,
    ).toBe("UCb");
  });

  test("breaks ties, none with Shorts included, by the newest upload", () => {
    const items = new Map([
      ["UCa", [video("a1", 3, false)]],
      ["UCb", [video("b1", 7, false)]],
    ]);
    expect(
      pickExampleChannel([channel("UCa"), channel("UCb")], items)?.channelId,
    ).toBe("UCb");
  });

  test("skips channels that can't be the example", () => {
    const items = new Map([["UCb", [video("b1", 7, true)]]]);
    expect(
      pickExampleChannel(
        [channel("UCa"), channel("UCb", { enabled: false })],
        items,
      )?.channelId,
    ).toBe("UCa");
    expect(
      pickExampleChannel([channel("UCb", { enabled: false })], items),
    ).toBe(null);
  });
});
