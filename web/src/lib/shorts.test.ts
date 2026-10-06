import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/shorts.json";
import { classifyShorts, withoutShortsList } from "./shorts";
import type { Video } from "./types";

function video(videoId: string, durationSeconds: number): Video {
  return {
    kind: "video",
    videoId,
    channelId: "UCchannel",
    channelTitle: "Channel",
    title: videoId,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    durationSeconds,
  };
}

const verdicts = (videos: Video[]) =>
  Object.fromEntries(videos.map((item) => [item.videoId, item.isShort]));

describe("classifyShorts", () => {
  test("skips the Shorts list when nothing is short enough", async () => {
    let asked = false;
    const result = await classifyShorts([video("long", 600)], async () => {
      asked = true;
      return new Set();
    });
    expect(asked).toBe(false);
    expect(verdicts(result)).toEqual({ long: false });
  });

  test("judges candidates by the Shorts list", async () => {
    const result = await classifyShorts(
      [video("short", 30), video("clip", 90), video("long", 600)],
      async () => new Set(["short", "long"]),
    );
    expect(verdicts(result)).toEqual({ short: true, clip: false, long: false });
  });

  test("a channel with no Shorts list has no Shorts", async () => {
    const result = await classifyShorts([video("clip", 90)], async () => null);
    expect(verdicts(result)).toEqual({ clip: false });
  });

  test("probes instead when there is no list and the platform can", async () => {
    const result = await classifyShorts(
      [video("short", 30), video("unsure", 40), video("long", 600)],
      async () => null,
      async (videoId) => (videoId === "short" ? true : null),
    );
    expect(verdicts(result)).toEqual({
      short: true,
      unsure: undefined,
      long: false,
    });
  });
});

describe("shared Shorts fixtures", () => {
  for (const testCase of fixture.cases) {
    test(testCase.name, async () => {
      let readsShortsList = false;
      const probes: string[] = [];
      const probeAnswers = (
        testCase as { probe?: Record<string, boolean | null> }
      ).probe;
      const result = await classifyShorts(
        testCase.videos.map((entry) => ({
          ...video(entry.videoId, 0),
          durationSeconds: entry.durationSeconds,
        })),
        async () => {
          readsShortsList = true;
          return testCase.shortsList ? new Set(testCase.shortsList) : null;
        },
        probeAnswers &&
          (async (videoId) => {
            probes.push(videoId);
            if (!(videoId in probeAnswers)) {
              throw new Error("probe failed");
            }
            return probeAnswers[videoId];
          }),
      );
      expect(
        Object.fromEntries(
          result.map((item) => [item.videoId, item.isShort ?? null]),
        ),
      ).toEqual(testCase.expected as unknown as Record<string, boolean | null>);
      expect(readsShortsList).toBe(testCase.readsShortsList);
      expect(probes.sort()).toEqual([...testCase.probes].sort());
    });
  }
});

describe("withoutShortsList", () => {
  test("marks what can't be a Short and leaves candidates unjudged", () => {
    const [long, clip, unknown] = withoutShortsList([
      video("long", 600),
      video("clip", 90),
      video("unknown", 0),
    ]);
    expect(long.isShort).toBe(false);
    expect(clip.isShort).toBeUndefined();
    expect(unknown.isShort).toBe(false);
  });
});
