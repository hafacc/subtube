import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import filterFixture from "../../../shared/fixtures/filters.json";
import patternFixture from "../../../shared/fixtures/patterns.json";
import {
  compileFilter,
  compilePattern,
  isValidPattern,
  PATTERN_META_REGEX,
  videoPassesFilter,
} from "./filters";
import type { ChannelFilter, FeedItem, Playlist, Video } from "./types";

function channel(overrides: Partial<ChannelFilter> = {}): ChannelFilter {
  return {
    enabled: true,
    regex: "",
    mode: "include",
    ...overrides,
  };
}

function video(overrides: Partial<Video> = {}): Video {
  return {
    kind: "video",
    videoId: "v1",
    channelId: "UC1",
    channelTitle: "Chan",
    title: "Hello World",
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    durationSeconds: 600,
    liveStatus: "normal",
    ...overrides,
  };
}

function playlist(overrides: Partial<Playlist> = {}): Playlist {
  return {
    kind: "playlist",
    playlistId: "PL1",
    channelId: "UC1",
    channelTitle: "Chan",
    title: "Episode 1",
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    itemCount: 5,
    ...overrides,
  };
}

const passes = (item: FeedItem, ch: ChannelFilter): boolean =>
  videoPassesFilter(item, compileFilter(ch));

describe("compileFilter", () => {
  test("empty regex compiles to no regex", () => {
    expect(compileFilter(channel()).regex).toBeNull();
  });

  test("invalid regex reports an error and no regex", () => {
    const compiled = compileFilter(channel({ regex: "(" }));
    expect(compiled.regex).toBeNull();
    expect(compiled.error).not.toBeNull();
  });

  test("case-insensitive by default, sensitive when set", () => {
    expect(compileFilter(channel({ regex: "a" })).regex?.test("A")).toBe(true);
    expect(
      compileFilter(channel({ regex: "a", caseSensitive: true })).regex?.test(
        "A",
      ),
    ).toBe(false);
  });
});

describe("videoPassesFilter — regex", () => {
  test("include keeps matches and drops non-matches", () => {
    expect(passes(video({ title: "cats" }), channel({ regex: "cat" }))).toBe(
      true,
    );
    expect(passes(video({ title: "dogs" }), channel({ regex: "cat" }))).toBe(
      false,
    );
  });

  test("exclude inverts the match", () => {
    expect(
      passes(
        video({ title: "cats" }),
        channel({ regex: "cat", mode: "exclude" }),
      ),
    ).toBe(false);
  });

  test("description scope matches the description, not the title", () => {
    const ch = channel({ regex: "secret", searchScope: "description" });
    expect(passes(video({ title: "secret", description: "" }), ch)).toBe(false);
    expect(passes(video({ title: "", description: "a secret" }), ch)).toBe(
      true,
    );
  });

  test("no regex keeps everything", () => {
    expect(passes(video(), channel())).toBe(true);
  });
});

describe("videoPassesFilter — video-only gates", () => {
  test("minimum duration drops shorter videos", () => {
    const ch = channel({ minDurationSeconds: 120 });
    expect(passes(video({ durationSeconds: 60 }), ch)).toBe(false);
    expect(passes(video({ durationSeconds: 600 }), ch)).toBe(true);
  });

  test("upcoming is always hidden", () => {
    expect(passes(video({ liveStatus: "upcoming" }), channel())).toBe(false);
  });

  test("liveFilter vod keeps vod/live and drops normal", () => {
    const ch = channel({ liveFilter: "vod" });
    expect(passes(video({ liveStatus: "vod" }), ch)).toBe(true);
    expect(passes(video({ liveStatus: "normal" }), ch)).toBe(false);
  });

  test("liveFilter normal drops vod", () => {
    const ch = channel({ liveFilter: "normal" });
    expect(passes(video({ liveStatus: "vod" }), ch)).toBe(false);
    expect(passes(video({ liveStatus: "normal" }), ch)).toBe(true);
  });

  test("shortsFilter narrows to/away from Shorts", () => {
    expect(
      passes(video({ isShort: true }), channel({ shortsFilter: "normal" })),
    ).toBe(false);
    expect(
      passes(video({ isShort: true }), channel({ shortsFilter: "shorts" })),
    ).toBe(true);
    expect(
      passes(video({ isShort: false }), channel({ shortsFilter: "shorts" })),
    ).toBe(false);
  });

  test("an unclassified video is held back by either Shorts gate", () => {
    expect(
      passes(
        video({ isShort: undefined }),
        channel({ shortsFilter: "normal" }),
      ),
    ).toBe(false);
    expect(
      passes(
        video({ isShort: undefined }),
        channel({ shortsFilter: "shorts" }),
      ),
    ).toBe(false);
  });

  test("a channel keeping every kind never consults the verdict", () => {
    expect(
      passes(video({ isShort: undefined }), channel({ shortsFilter: "all" })),
    ).toBe(true);
    expect(passes(video({ isShort: true }), channel())).toBe(true);
  });
});

describe("videoPassesFilter — playlists", () => {
  test("playlists skip video-only gates but still match the title regex", () => {
    const ch = channel({
      minDurationSeconds: 9999,
      liveFilter: "vod",
      shortsFilter: "shorts",
      regex: "Episode",
    });
    expect(passes(playlist({ title: "Episode 1" }), ch)).toBe(true);
    expect(passes(playlist({ title: "Trailer" }), ch)).toBe(false);
  });
});

describe("shared pattern fixtures", () => {
  test("the meta regex is shared/patterns/meta-regex.txt", () => {
    const shared = readFileSync(
      new URL("../../../shared/patterns/meta-regex.txt", import.meta.url),
      "utf8",
    ).trimEnd();
    expect(PATTERN_META_REGEX).toBe(shared);
  });

  for (const testCase of patternFixture.cases) {
    test(testCase.name, () => {
      expect(isValidPattern(testCase.pattern)).toBe(testCase.valid);
      for (const check of testCase.matches ?? []) {
        const regex = compilePattern(testCase.pattern, check.caseSensitive);
        expect([check.text, regex.test(check.text)]).toEqual([
          check.text,
          check.matches,
        ]);
      }
    });
  }
});

describe("shared filter fixtures", () => {
  for (const testCase of filterFixture.cases) {
    test(testCase.name, () => {
      const item: FeedItem =
        testCase.item.kind === "playlist"
          ? playlist(testCase.item as Partial<Playlist>)
          : video({
              durationSeconds: undefined,
              liveStatus: undefined,
              isShort: undefined,
              ...(testCase.item as Partial<Video>),
            });
      const filter = { ...testCase.filter } as unknown as ChannelFilter;
      expect(videoPassesFilter(item, compileFilter(filter))).toBe(
        testCase.kept,
      );
    });
  }
});
