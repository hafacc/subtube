import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/channel-chips.json";
import { chipKeptChannels, passingItems } from "./channel-chips";
import { chipRow, type TimeChip } from "./chips";
import { feedItemId } from "./feed-item";
import { defaultFilter } from "./sync-merge";
import type { Channel, ChannelFilter, FeedItem } from "./types";

interface FixtureItem {
  id: string;
  channelId: string;
  kind?: string;
  publishedAt?: string;
  categoryId?: string;
}

interface FixtureCase {
  name: string;
  op: string;
  channels?: string[];
  items: FixtureItem[];
  selected?: string[];
  timeChip?: string;
  topicChips?: string[];
  now?: number;
  expected: string[];
}

function feedItem(raw: FixtureItem): FeedItem {
  const common = {
    channelId: raw.channelId,
    channelTitle: raw.channelId,
    title: raw.id,
    description: "",
    publishedAt: raw.publishedAt ?? "2026-01-01T00:00:00Z",
    thumbnail: "",
  };
  if (raw.kind === "playlist") {
    return { ...common, kind: "playlist", playlistId: raw.id, itemCount: 1 };
  } else {
    return {
      ...common,
      kind: "video",
      videoId: raw.id,
      categoryId: raw.categoryId,
    };
  }
}

function result(testCase: FixtureCase): string[] {
  const items = testCase.items.map(feedItem);
  if (testCase.op === "chips") {
    return chipRow(items, testCase.selected ?? []);
  } else if (testCase.op === "channels") {
    const kept = chipKeptChannels(
      items,
      testCase.timeChip as TimeChip,
      testCase.topicChips ?? [],
      testCase.now ?? 0,
    );
    return (testCase.channels ?? []).filter(
      (channelId) => kept === null || kept.has(channelId),
    );
  } else {
    throw new Error(`unknown op ${testCase.op}`);
  }
}

describe("shared channel chip fixtures", () => {
  for (const testCase of fixture.cases as FixtureCase[]) {
    test(testCase.name, () => {
      expect(result(testCase)).toEqual(testCase.expected);
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

describe("passingItems", () => {
  const items = [
    feedItem({ id: "a-talk", channelId: "UCa" }),
    feedItem({ id: "a-live", channelId: "UCa" }),
    feedItem({ id: "b-talk", channelId: "UCb" }),
    feedItem({ id: "c-list", channelId: "UCc", kind: "playlist" }),
    feedItem({ id: "c-talk", channelId: "UCc" }),
    feedItem({ id: "d-talk", channelId: "UCd" }),
  ];
  const passing = (channels: Channel[]): string[] =>
    passingItems(channels, items).map(feedItemId);

  test("keeps what each on channel's filter passes", () => {
    expect(
      passing([
        channel("UCa", { mode: "exclude", regex: "\\blive\\b" }),
        channel("UCb"),
      ]),
    ).toEqual(["a-talk", "b-talk"]);
  });

  test("keeps nothing of a channel that is off or unknown", () => {
    expect(passing([channel("UCb", { enabled: false })])).toEqual([]);
  });

  test("keeps only the kind of item the channel shows", () => {
    expect(passing([channel("UCc", { contentMode: "playlists" })])).toEqual([
      "c-list",
    ]);
    expect(passing([channel("UCc")])).toEqual(["c-talk"]);
  });
});
