import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/feed-order.json";
import { feedItemId } from "./feed-item";
import { byNewest } from "./feed-order";
import type { Video } from "./types";

function video(id: string, publishedAt: string): Video {
  return {
    kind: "video",
    videoId: id,
    channelId: "UC1",
    channelTitle: "Chan",
    title: id,
    description: "",
    publishedAt,
    thumbnail: "",
  };
}

describe("shared feed order fixtures", () => {
  for (const testCase of fixture.cases) {
    test(testCase.name, () => {
      expect(testCase.op).toBe("sort");
      expect(
        testCase.items
          .map(({ id, publishedAt }) => video(id, publishedAt))
          .sort(byNewest)
          .map(feedItemId),
      ).toEqual(testCase.expected);
    });
  }
});
