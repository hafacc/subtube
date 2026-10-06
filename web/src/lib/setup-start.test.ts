import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/setup-start.json";
import type { StartFrom } from "./chips";
import { applyStart, type PendingStart, pendingStart } from "./setup-start";
import type { FeedItem } from "./types";

interface FixtureItem {
  id: string;
  channelId: string;
  publishedAt: string;
  kind?: "video" | "playlist";
}

interface FixtureCase {
  name: string;
  op: string;
  start?: string;
  cutoff?: number;
  channels?: string[];
  pending?: PendingStart | null;
  fetched?: string[];
  items?: FixtureItem[];
  expected: unknown;
}

function feedItem(entry: FixtureItem): FeedItem {
  const shared = {
    channelId: entry.channelId,
    channelTitle: entry.channelId,
    title: entry.id,
    description: "",
    publishedAt: entry.publishedAt,
    thumbnail: "",
  };
  if (entry.kind === "playlist") {
    return { ...shared, kind: "playlist", playlistId: entry.id, itemCount: 1 };
  } else {
    return { ...shared, kind: "video", videoId: entry.id };
  }
}

function result(testCase: FixtureCase): unknown {
  if (testCase.op === "keep") {
    return pendingStart(
      testCase.start as StartFrom,
      testCase.cutoff ?? 0,
      testCase.channels ?? [],
    );
  } else if (testCase.op === "apply") {
    return applyStart(
      testCase.pending ?? null,
      testCase.fetched ?? [],
      (testCase.items ?? []).map(feedItem),
    );
  } else {
    throw new Error(`unknown op ${testCase.op}`);
  }
}

describe("shared setup starting point fixtures", () => {
  for (const testCase of fixture.cases as FixtureCase[]) {
    test(testCase.name, () => {
      expect(result(testCase)).toStrictEqual(testCase.expected);
    });
  }
});
