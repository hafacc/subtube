import { describe, expect, test } from "bun:test";
import { markAllChoice } from "./mark-all";
import type { FeedItem, Playlist, Video } from "./types";

function video(id: string): Video {
  return {
    kind: "video",
    videoId: id,
    channelId: "UCa",
    channelTitle: "A",
    title: id,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
  };
}

function playlist(id: string): Playlist {
  return {
    kind: "playlist",
    playlistId: id,
    channelId: "UCa",
    channelTitle: "A",
    title: id,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    itemCount: 3,
  };
}

describe("markAllChoice", () => {
  const shown: FeedItem[] = [video("seen"), video("new"), playlist("list")];

  test("marks watched the shown cards that aren't watched", () => {
    expect(markAllChoice(shown, new Set(["seen"]))).toEqual({
      watched: true,
      ids: ["new", "list"],
    });
  });

  test("marks exactly the shown cards unwatched once all are watched", () => {
    expect(
      markAllChoice(shown, new Set(["seen", "new", "list", "not-shown"])),
    ).toEqual({ watched: false, ids: ["seen", "new", "list"] });
  });

  test("does nothing, as mark watched, when no card is shown", () => {
    expect(markAllChoice([], new Set(["seen"]))).toEqual({
      watched: true,
      ids: [],
    });
  });
});
