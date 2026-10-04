import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/channel-order.json";
import {
  type ChannelOrderKey,
  compareChannelOrder,
  orderChannels,
} from "./channel-order";
import { defaultFilter } from "./sync-merge";
import type { Channel, ChannelFilter, Video } from "./types";

describe("shared channel order fixtures", () => {
  for (const testCase of fixture.cases) {
    test(testCase.name, () => {
      const channels: ChannelOrderKey[] = testCase.channels;
      expect(
        channels.toSorted(compareChannelOrder).map(({ id }) => id),
      ).toEqual(testCase.expected);
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
  test("orders by the newest item that passes each channel's filter", () => {
    const channels = [
      channel("UCa", { mode: "exclude", regex: "live" }),
      channel("UCb"),
      channel("UCc", { mode: "exclude", regex: "live" }),
      channel("UCd", { enabled: false }),
    ];
    const items = [
      video("UCa", "live now", 9),
      video("UCa", "talk", 2),
      video("UCb", "talk", 5),
      video("UCc", "live now", 8),
      video("UCd", "talk", 10),
    ];
    expect(
      orderChannels(channels, items).map(({ channelId }) => channelId),
    ).toEqual(["UCb", "UCa", "UCc", "UCd"]);
  });
});
