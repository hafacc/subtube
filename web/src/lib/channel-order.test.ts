import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/channel-order.json";
import {
  type ChannelOrderKey,
  type ChannelSort,
  compareChannelOrder,
  HeldChannelOrder,
  inHeldOrder,
  orderChannels,
} from "./channel-order";
import { defaultFilter } from "./sync-merge";
import type { Channel, ChannelFilter, Video } from "./types";

describe("shared channel order fixtures", () => {
  for (const testCase of fixture.cases) {
    test(testCase.name, () => {
      const channels: ChannelOrderKey[] = testCase.channels;
      const sort = (
        "sort" in testCase ? testCase.sort : "newest"
      ) as ChannelSort;
      for (const given of [channels, channels.toReversed()]) {
        expect(
          given
            .toSorted((left, right) => compareChannelOrder(left, right, sort))
            .map(({ id }) => id),
        ).toEqual(testCase.expected);
      }
    });
  }
});

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

function video(channelId: string, title: string, day: number): Video {
  return {
    kind: "video",
    videoId: `${channelId}-${day}`,
    channelId,
    channelTitle: channelId,
    title,
    description: "",
    publishedAt: `2026-01-${String(day).padStart(2, "0")}T00:00:00Z`,
    thumbnail: "",
  };
}

describe("orderChannels", () => {
  const items = [
    video("UCa", "live now", 9),
    video("UCa", "talk", 2),
    video("UCb", "talk", 5),
    video("UCc", "live now", 8),
    video("UCd", "talk", 10),
  ];
  const order = (channels: Channel[]): string[] =>
    orderChannels(channels, items).map(({ channelId }) => channelId);

  test("orders by each channel's newest item, off channels last", () => {
    expect(
      order([
        channel("UCb"),
        channel("UCc"),
        channel("UCd", { enabled: false }),
        channel("UCa"),
        channel("UCe"),
      ]),
    ).toEqual(["UCa", "UCc", "UCb", "UCe", "UCd"]);
  });

  test("a filter that hides the newest item doesn't move its channel", () => {
    expect(
      order([
        channel("UCa", { mode: "exclude", regex: "live" }),
        channel("UCb"),
        channel("UCc", { mode: "include", regex: "nothing matches" }),
      ]),
    ).toEqual(["UCa", "UCc", "UCb"]);
  });

  test("orders by unwatched count, then by newest item", () => {
    const channels = [channel("UCa"), channel("UCb"), channel("UCc")];
    expect(
      orderChannels(
        channels,
        items,
        "unwatched",
        new Map([
          ["UCb", 4],
          ["UCc", 4],
        ]),
      ).map(({ channelId }) => channelId),
    ).toEqual(["UCc", "UCb", "UCa"]);
  });
});

const ids = (channels: Channel[]): string[] =>
  channels.map(({ channelId }) => channelId);

describe("inHeldOrder", () => {
  test("keeps the held places whatever the fresh order is", () => {
    expect(
      ids(
        inHeldOrder(
          [channel("UCc"), channel("UCa"), channel("UCb")],
          ["UCa", "UCb", "UCc"],
        ),
      ),
    ).toEqual(["UCa", "UCb", "UCc"]);
  });

  test("returns the fresh channels, so a row shows its new state", () => {
    const [held] = inHeldOrder(
      [channel("UCb"), channel("UCa", { enabled: false })],
      ["UCa", "UCb"],
    );
    expect(held.channelId).toBe("UCa");
    expect(held.filter.enabled).toBe(false);
  });

  test("puts channels it doesn't know at the end, in fresh order", () => {
    expect(
      ids(
        inHeldOrder(
          [channel("UCy"), channel("UCb"), channel("UCx"), channel("UCa")],
          ["UCa", "UCb"],
        ),
      ),
    ).toEqual(["UCa", "UCb", "UCy", "UCx"]);
  });

  test("drops channels that are gone", () => {
    expect(ids(inHeldOrder([channel("UCb")], ["UCa", "UCb"]))).toEqual(["UCb"]);
  });
});

describe("HeldChannelOrder", () => {
  const sorted = (channels: Channel[]): Channel[] =>
    orderChannels(channels, []);

  test("holds the order while the moment is the same", () => {
    const order = new HeldChannelOrder();
    expect(
      ids(order.arrange(sorted([channel("UCa"), channel("UCb")]), "feed")),
    ).toEqual(["UCa", "UCb"]);
    const switchedOff = sorted([
      channel("UCa", { enabled: false }),
      channel("UCb"),
    ]);
    expect(ids(switchedOff)).toEqual(["UCb", "UCa"]);
    const shown = order.arrange(switchedOff, "feed");
    expect(ids(shown)).toEqual(["UCa", "UCb"]);
    expect(shown[0].filter.enabled).toBe(false);
  });

  test("puts the list in order again when the moment changes", () => {
    const order = new HeldChannelOrder();
    order.arrange(sorted([channel("UCa"), channel("UCb")]), "feed");
    const switchedOff = sorted([
      channel("UCa", { enabled: false }),
      channel("UCb"),
    ]);
    order.arrange(switchedOff, "feed");
    expect(ids(order.arrange(switchedOff, "channel"))).toEqual(["UCb", "UCa"]);
    expect(ids(order.arrange(switchedOff, "channel"))).toEqual(["UCb", "UCa"]);
  });

  test("holds the new order after the moment changed", () => {
    const order = new HeldChannelOrder();
    order.arrange(sorted([channel("UCb"), channel("UCa")]), "one");
    order.arrange(
      sorted([channel("UCb"), channel("UCa", { enabled: false })]),
      "two",
    );
    expect(
      ids(order.arrange(sorted([channel("UCa"), channel("UCb")]), "two")),
    ).toEqual(["UCb", "UCa"]);
  });
});

describe("HeldChannelOrder with chips", () => {
  const all = [channel("UCa"), channel("UCb"), channel("UCc")];

  test("shows only the kept channels when the moment changes", () => {
    const order = new HeldChannelOrder();
    expect(ids(order.arrange(all, "one", new Set(["UCa", "UCc"])))).toEqual([
      "UCa",
      "UCc",
    ]);
    expect(ids(order.arrange(all, "two", new Set(["UCb"])))).toEqual(["UCb"]);
    expect(ids(order.arrange(all, "three", null))).toEqual([
      "UCa",
      "UCb",
      "UCc",
    ]);
  });

  test("a channel no longer kept stays in place while the moment is the same", () => {
    const order = new HeldChannelOrder();
    order.arrange(all, "one", new Set(["UCa", "UCb"]));
    const switchedOff = [
      channel("UCb"),
      channel("UCc"),
      channel("UCa", { enabled: false }),
    ];
    const shown = order.arrange(switchedOff, "one", new Set(["UCb"]));
    expect(ids(shown)).toEqual(["UCa", "UCb"]);
    expect(shown[0].filter.enabled).toBe(false);
    expect(ids(order.arrange(switchedOff, "two", new Set(["UCb"])))).toEqual([
      "UCb",
    ]);
  });

  test("a channel kept since joins after the held ones", () => {
    const order = new HeldChannelOrder();
    order.arrange(all, "one", new Set(["UCb", "UCc"]));
    expect(
      ids(order.arrange(all, "one", new Set(["UCa", "UCb", "UCc"]))),
    ).toEqual(["UCb", "UCc", "UCa"]);
  });
});
