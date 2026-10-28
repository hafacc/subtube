import { describe, expect, test } from "bun:test";
import { applyPlayerKey, nextRate, playerKeyAction } from "./player-keys";
import type { YouTubeKeyControls } from "./youtube-player";

function fakePlayer(state: number) {
  const calls: string[] = [];
  const player = {
    time: 30,
    volume: 50,
    muted: false,
    getPlayerState: () => state,
    getCurrentTime: () => player.time,
    getDuration: () => 100,
    seekTo: (seconds: number) => {
      calls.push(`seek ${seconds}`);
    },
    getVolume: () => player.volume,
    setVolume: (volume: number) => {
      calls.push(`volume ${volume}`);
    },
    isMuted: () => player.muted,
    mute: () => calls.push("mute"),
    unMute: () => calls.push("unmute"),
    playVideo: () => calls.push("play"),
    pauseVideo: () => calls.push("pause"),
  };
  return {
    player: player as unknown as YouTubeKeyControls,
    state: player,
    calls,
  };
}

describe("playerKeyAction", () => {
  test("maps YouTube's keys", () => {
    expect(playerKeyAction(" ", false)).toEqual({ kind: "toggle" });
    expect(playerKeyAction("k", false)).toEqual({ kind: "toggle" });
    expect(playerKeyAction("ArrowLeft", false)).toEqual({
      kind: "seekBy",
      seconds: -5,
    });
    expect(playerKeyAction("l", false)).toEqual({
      kind: "seekBy",
      seconds: 10,
    });
    expect(playerKeyAction("7", false)).toEqual({
      kind: "seekToFraction",
      fraction: 0.7,
    });
    expect(playerKeyAction("ArrowUp", false)).toEqual({
      kind: "volumeBy",
      step: 5,
    });
    expect(playerKeyAction("N", true)).toEqual({ kind: "next" });
    expect(playerKeyAction(">", true)).toEqual({ kind: "speed", faster: true });
  });

  test("leaves other keys alone", () => {
    expect(playerKeyAction("Tab", false)).toBeNull();
    expect(playerKeyAction("Enter", false)).toBeNull();
    expect(playerKeyAction("x", false)).toBeNull();
  });
});

describe("applyPlayerKey", () => {
  test("pauses a playing video and plays a paused one", () => {
    const playing = fakePlayer(1);
    applyPlayerKey({ kind: "toggle" }, playing.player);
    const paused = fakePlayer(2);
    applyPlayerKey({ kind: "toggle" }, paused.player);
    expect([playing.calls, paused.calls]).toEqual([["pause"], ["play"]]);
  });

  test("keeps a jump inside the video", () => {
    const { player, state, calls } = fakePlayer(1);
    state.time = 2;
    applyPlayerKey({ kind: "seekBy", seconds: -5 }, player);
    state.time = 98;
    applyPlayerKey({ kind: "seekBy", seconds: 5 }, player);
    expect(calls).toEqual(["seek 0", "seek 100"]);
  });

  test("raising the volume unmutes", () => {
    const { player, state, calls } = fakePlayer(1);
    state.muted = true;
    state.volume = 98;
    applyPlayerKey({ kind: "volumeBy", step: 5 }, player);
    expect(calls).toEqual(["volume 100", "unmute"]);
  });
});

describe("nextRate", () => {
  test("steps through the rates and stops at the ends", () => {
    const rates = [0.5, 1, 1.5, 2];
    expect(nextRate(rates, 1, true)).toBe(1.5);
    expect(nextRate(rates, 1, false)).toBe(0.5);
    expect(nextRate(rates, 2, true)).toBe(2);
    expect(nextRate(rates, 0.5, false)).toBe(0.5);
  });
});
