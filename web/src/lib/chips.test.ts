import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/feed-chips.json";
import {
  CATEGORY_NAMES,
  chipFiltered,
  chipRow,
  editorTopics,
  type StartFrom,
  startMarks,
  TIME_CHIP_OPTIONS,
  type TimeChip,
  topicLabel,
} from "./chips";
import { feedItemId } from "./feed-item";
import { groupKeptChannels } from "./groups";
import { defaultFilter } from "./sync-merge";
import type { FeedItem } from "./types";

interface FixtureItem {
  id: string;
  channelId?: string;
  kind?: string;
  publishedAt?: string;
  categoryId?: string;
}

interface FixtureCase {
  name: string;
  op: string;
  categoryId?: string;
  items?: FixtureItem[];
  selected?: string[];
  now?: number;
  timeChip?: string;
  topicChips?: string[];
  channelGroups?: Record<string, string[]>;
  groupChips?: string[];
  start?: string;
  expected: string[] | string | null;
}

function feedItem(raw: FixtureItem): FeedItem {
  const common = {
    channelId: raw.channelId ?? "UC1",
    channelTitle: "Chan",
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

function result(testCase: FixtureCase): string[] | string | null {
  const items = (testCase.items ?? []).map(feedItem);
  if (testCase.op === "label") {
    return topicLabel(testCase.categoryId);
  } else if (testCase.op === "chips") {
    return chipRow(items, testCase.selected ?? []);
  } else if (testCase.op === "filter") {
    return chipFiltered(
      items,
      testCase.timeChip as TimeChip,
      testCase.topicChips ?? [],
      testCase.now ?? 0,
    ).map(feedItemId);
  } else if (testCase.op === "groupFilter") {
    const kept = groupKeptChannels(
      new Map(
        Object.entries(testCase.channelGroups ?? {}).map(
          ([channelId, groups]) => [channelId, { ...defaultFilter(), groups }],
        ),
      ),
      testCase.groupChips ?? [],
    );
    return chipFiltered(
      items.filter((item) => kept?.has(item.channelId) ?? true),
      testCase.timeChip as TimeChip,
      testCase.topicChips ?? [],
      testCase.now ?? 0,
    ).map(feedItemId);
  } else if (testCase.op === "editor") {
    return editorTopics(items);
  } else if (testCase.op === "start") {
    return startMarks(items, testCase.start as StartFrom, testCase.now ?? 0);
  } else {
    throw new Error(`unknown op ${testCase.op}`);
  }
}

describe("shared feed chip fixtures", () => {
  for (const testCase of fixture.cases as FixtureCase[]) {
    test(testCase.name, () => {
      expect(result(testCase)).toEqual(testCase.expected);
    });
  }
});

describe("chips", () => {
  test("a name every object has is not a topic", () => {
    expect(topicLabel("constructor")).toBeNull();
    expect(topicLabel("toString")).toBeNull();
  });

  test("there are fifteen topics", () => {
    expect(Object.keys(CATEGORY_NAMES)).toHaveLength(15);
    expect(editorTopics([])).toHaveLength(15);
  });

  test("a playlist never passes a selected topic", () => {
    const playlist = feedItem({ id: "list", kind: "playlist" });
    expect(chipFiltered([playlist], "none", ["10"], 0)).toEqual([]);
  });

  test("the time chip moves from all time through day, week and month", () => {
    expect(TIME_CHIP_OPTIONS.map((option) => option.value)).toEqual([
      "none",
      "day",
      "week",
      "month",
    ]);
  });
});
