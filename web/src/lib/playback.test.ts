import { describe, expect, test } from "bun:test";
import { Playback, type PlaybackFeed } from "./playback";
import type { RouteItem } from "./router";
import type { FeedItem, LiveStatus } from "./types";
import type { YouTubePlayer } from "./youtube-player";

const STATES = { PLAYING: 1, PAUSED: 2, ENDED: 0 };

type Call =
  | { load: string[]; start: number | undefined }
  | { list: string; index: number; start: number }
  | {
      id: string;
      position: number;
      ended: boolean;
      upload: string;
      place?: { video: string; progress: number };
      duration?: number;
    }
  | { marked: string }
  | "ended"
  | "toggled"
  | "pause"
  | "play";

/** A playback of `item` over a fake player and feed, with everything it did in order. */
function playing(
  item: RouteItem,
  options: {
    resumeAt?: number;
    liveStatus?: LiveStatus;
    playlist?: string[];
    playlistStart?: { index: number; position: number };
  } = {},
): {
  playback: Playback;
  player: YouTubePlayer & { time: number; index: number };
  calls: Call[];
} {
  const calls: Call[] = [];
  const entry: FeedItem = {
    kind: "video",
    videoId: item.id,
    channelId: "UC1",
    channelTitle: "Chan",
    title: item.id,
    description: "",
    publishedAt: "2026-01-01T00:00:00Z",
    thumbnail: "",
    liveStatus: options.liveStatus,
  };
  const feed: PlaybackFeed = {
    recordProgress: (id, position, duration, ended, upload, place) => {
      if (place === undefined) {
        calls.push({ id, position, ended, upload });
      } else {
        calls.push({ id, position, ended, upload, place, duration });
      }
    },
    setWatched: (id) => {
      calls.push({ marked: id });
    },
    resumeAt: () => options.resumeAt ?? 0,
    playlistStart: () => options.playlistStart ?? { index: 0, position: 0 },
    findItem: () => (item.kind === "video" ? entry : undefined),
  };
  const player = {
    time: 0,
    index: 0,
    destroy: () => undefined,
    pauseVideo: () => {
      calls.push("pause");
    },
    playVideo: () => {
      calls.push("play");
    },
    getIframe: () => {
      throw new Error("no iframe in tests");
    },
    loadPlaylist: (
      playlist:
        | string[]
        | { list: string; index: number; startSeconds: number },
      _index?: number,
      start?: number,
    ) => {
      if (Array.isArray(playlist)) {
        calls.push({ load: playlist, start });
      } else {
        calls.push({
          list: playlist.list,
          index: playlist.index,
          start: playlist.startSeconds,
        });
      }
    },
    getCurrentTime: () => player.time,
    getDuration: () => 600,
    getVideoData: () => ({
      video_id: options.playlist?.[player.index] ?? item.id,
      title: "Title",
    }),
    getPlaylist: () => options.playlist ?? null,
    getPlaylistIndex: () => player.index,
  };
  const playback = new Playback(
    item,
    feed,
    STATES,
    () => {
      calls.push("ended");
    },
    () => {
      calls.push("toggled");
    },
  );
  return { playback, player, calls };
}

const VIDEO: RouteItem = { kind: "video", id: "v1" };
const PLAYLIST: RouteItem = { kind: "playlist", id: "PL1" };

describe("Playback of a video", () => {
  test("starts where it was left", () => {
    const { playback, player, calls } = playing(VIDEO, { resumeAt: 42 });
    playback.ready(player);
    expect(calls).toEqual([{ load: ["v1"], start: 42 }]);
  });

  test("saves nothing before it has played", () => {
    const { playback, player, calls } = playing(VIDEO);
    playback.ready(player);
    playback.tick();
    playback.save("soon");
    expect(calls).toEqual([{ load: ["v1"], start: 0 }]);
  });

  test("saves on this device while playing and uploads on pause", () => {
    const { playback, player, calls } = playing(VIDEO);
    playback.stateChanged(STATES.PLAYING, player);
    player.time = 5;
    playback.tick();
    player.time = 7;
    playback.stateChanged(STATES.PAUSED, player);
    playback.tick();
    expect(calls).toEqual([
      { id: "v1", position: 5, ended: false, upload: "later" },
      "toggled",
      { id: "v1", position: 7, ended: false, upload: "soon" },
    ]);
  });

  test("a pause that follows no playing saves nothing", () => {
    const { playback, player, calls } = playing(VIDEO);
    playback.stateChanged(STATES.PAUSED, player);
    expect(calls).toEqual([]);
  });

  test("the end marks it, runs onended, and stops later saves", () => {
    const { playback, player, calls } = playing(VIDEO);
    playback.stateChanged(STATES.PLAYING, player);
    player.time = 600;
    playback.stateChanged(STATES.ENDED, player);
    playback.save("soon");
    expect(calls).toEqual([
      { id: "v1", position: 600, ended: true, upload: "soon" },
      "ended",
    ]);
  });

  test("a live broadcast saves no position and is marked at its end", () => {
    const { playback, player, calls } = playing(VIDEO, { liveStatus: "live" });
    playback.stateChanged(STATES.PLAYING, player);
    playback.tick();
    playback.stateChanged(STATES.ENDED, player);
    expect(calls).toEqual([{ marked: "v1" }, "ended"]);
  });

  test("keeps what the player reports about its video", () => {
    const { playback, player } = playing(VIDEO);
    playback.stateChanged(STATES.PLAYING, player);
    expect(playback.videoData).toEqual({ video_id: "v1", title: "Title" });
  });
});

describe("Playback under a cover", () => {
  // a live broadcast saves no position, so only the cover's own calls show
  const LIVE = { liveStatus: "live" } as const;
  const BUFFERING = 3;

  test("pauses a playing video and plays it again once uncovered", () => {
    const { playback, player, calls } = playing(VIDEO, LIVE);
    playback.stateChanged(STATES.PLAYING, player);
    playback.cover(true);
    playback.stateChanged(STATES.PAUSED, player);
    playback.cover(false);
    playback.stateChanged(STATES.PLAYING, player);
    expect(calls).toEqual(["pause", "play"]);
  });

  test("leaves a video the user paused alone", () => {
    const { playback, player, calls } = playing(VIDEO, LIVE);
    playback.stateChanged(STATES.PLAYING, player);
    playback.stateChanged(STATES.PAUSED, player);
    playback.cover(true);
    playback.cover(false);
    expect(calls).toEqual(["toggled"]);
  });

  test("pauses a video that starts while covered", () => {
    const { playback, player, calls } = playing(VIDEO, LIVE);
    playback.cover(true);
    playback.stateChanged(STATES.PLAYING, player);
    playback.stateChanged(STATES.PAUSED, player);
    playback.cover(false);
    expect(calls).toEqual(["pause", "play"]);
  });

  test("reports a pause and a play that are not its own", () => {
    const { playback, player, calls } = playing(VIDEO, LIVE);
    playback.stateChanged(STATES.PLAYING, player);
    playback.stateChanged(STATES.PAUSED, player);
    playback.stateChanged(BUFFERING, player);
    playback.stateChanged(STATES.PLAYING, player);
    playback.stateChanged(BUFFERING, player);
    playback.stateChanged(STATES.PLAYING, player);
    expect(calls).toEqual(["toggled", "toggled"]);
  });

  test("the first play is not reported", () => {
    const { playback, player, calls } = playing(VIDEO, LIVE);
    playback.stateChanged(BUFFERING, player);
    playback.stateChanged(STATES.PLAYING, player);
    expect(calls).toEqual([]);
  });
});

describe("Playback the player reports an error for", () => {
  test("a video is over, unmarked, and nothing more is saved", () => {
    const { playback, player, calls } = playing(VIDEO);
    playback.ready(player);
    playback.stateChanged(STATES.PLAYING, player);
    calls.length = 0;
    playback.failed();
    playback.save("soon");
    expect(calls).toEqual(["ended"]);
  });

  test("a playlist goes on, as its player skips the video", () => {
    const { playback, player, calls } = playing(PLAYLIST, {
      playlist: ["a", "b"],
    });
    playback.ready(player);
    calls.length = 0;
    playback.failed();
    expect(calls).toEqual([]);
  });
});

describe("Playback of a playlist", () => {
  test("has the player cue its own list, then starts at its first video", () => {
    const { playback, player, calls } = playing(PLAYLIST, {
      playlist: ["a", "b"],
    });
    expect(playback.playerVars).toMatchObject({
      listType: "playlist",
      list: "PL1",
    });
    expect(playback.playerVars.autoplay).toBeUndefined();
    playback.ready(player);
    expect(calls).toEqual([{ list: "PL1", index: 0, start: 0 }]);
  });

  test("starts at the video that was playing, where it was left", () => {
    const { playback, player, calls } = playing(PLAYLIST, {
      playlist: ["a", "b"],
      playlistStart: { index: 1, position: 42 },
    });
    playback.ready(player);
    expect(calls).toEqual([{ list: "PL1", index: 1, start: 42 }]);
  });

  test("saves its playing video, how far into it and through the list, with no length", () => {
    const { playback, player, calls } = playing(PLAYLIST, {
      playlist: ["a", "b"],
    });
    player.index = 1;
    playback.stateChanged(STATES.PLAYING, player);
    player.time = 150;
    playback.tick();
    player.time = 300;
    playback.stateChanged(STATES.PAUSED, player);
    expect(calls).toEqual([
      {
        id: "PL1",
        position: 150,
        ended: false,
        upload: "later",
        place: { video: "b", progress: 0.625 },
        duration: 0,
      },
      "toggled",
      {
        id: "PL1",
        position: 300,
        ended: false,
        upload: "soon",
        place: { video: "b", progress: 0.75 },
        duration: 0,
      },
    ]);
  });

  test("is marked only when its last video ends", () => {
    const { playback, player, calls } = playing(PLAYLIST, {
      playlist: ["a", "b"],
    });
    playback.stateChanged(STATES.ENDED, player);
    expect(calls).toEqual([]);
    player.index = 1;
    playback.stateChanged(STATES.ENDED, player);
    expect(calls).toEqual([{ marked: "PL1" }, "ended"]);
  });
});
