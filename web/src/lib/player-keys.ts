/*
 * YouTube's own keyboard shortcuts, carried out through the IFrame API for
 * keys pressed on the page, where the embed never hears them.
 */

import type { YouTubeKeyControls } from "./youtube-player";

/** How far the arrow keys jump, in seconds. */
const ARROW_SEEK_SECONDS = 5;
/** How far J and L jump, in seconds. */
const LETTER_SEEK_SECONDS = 10;
/** How much the up and down arrows change the volume, out of 100. */
const VOLUME_STEP = 5;
/** `YT.PlayerState.PLAYING`. */
const PLAYING = 1;
/** `YT.PlayerState.BUFFERING`. */
const BUFFERING = 3;

/** What a key does to the player. */
export type PlayerKeyAction =
  | { kind: "toggle" }
  | { kind: "seekBy"; seconds: number }
  | { kind: "seekToFraction"; fraction: number }
  | { kind: "seekToEnd" }
  | { kind: "volumeBy"; step: number }
  | { kind: "mute" }
  | { kind: "speed"; faster: boolean }
  | { kind: "next" }
  | { kind: "previous" }
  | { kind: "fullscreen" };

/** What the key `key` does as YouTube maps it, or null for a key it leaves alone. */
export function playerKeyAction(
  key: string,
  shift: boolean,
): PlayerKeyAction | null {
  if (/^[0-9]$/.test(key)) {
    return { kind: "seekToFraction", fraction: Number(key) / 10 };
  }
  switch (key) {
    case " ":
    case "k":
    case "K":
      return { kind: "toggle" };
    case "ArrowLeft":
      return { kind: "seekBy", seconds: -ARROW_SEEK_SECONDS };
    case "ArrowRight":
      return { kind: "seekBy", seconds: ARROW_SEEK_SECONDS };
    case "j":
    case "J":
      return { kind: "seekBy", seconds: -LETTER_SEEK_SECONDS };
    case "l":
    case "L":
      return { kind: "seekBy", seconds: LETTER_SEEK_SECONDS };
    case "Home":
      return { kind: "seekToFraction", fraction: 0 };
    case "End":
      return { kind: "seekToEnd" };
    case "ArrowUp":
      return { kind: "volumeBy", step: VOLUME_STEP };
    case "ArrowDown":
      return { kind: "volumeBy", step: -VOLUME_STEP };
    case "m":
    case "M":
      return { kind: "mute" };
    case "f":
    case "F":
      return { kind: "fullscreen" };
    case ">":
      return { kind: "speed", faster: true };
    case "<":
      return { kind: "speed", faster: false };
    case "N":
      return shift ? { kind: "next" } : null;
    case "P":
      return shift ? { kind: "previous" } : null;
    default:
      return null;
  }
}

/** The playback rate after `current` one step faster or slower among `rates`. */
export function nextRate(
  rates: number[],
  current: number,
  faster: boolean,
): number {
  const sorted = [...rates].sort((first, second) => first - second);
  const index = sorted.indexOf(current);
  if (index === -1) {
    return current;
  } else {
    const moved = faster ? index + 1 : index - 1;
    return sorted[Math.max(0, Math.min(sorted.length - 1, moved))] ?? current;
  }
}

/** Carry out `action` on `player`, all but full screen, which needs the page. */
export function applyPlayerKey(
  action: Exclude<PlayerKeyAction, { kind: "fullscreen" }>,
  player: YouTubeKeyControls,
): void {
  switch (action.kind) {
    case "toggle": {
      const state = player.getPlayerState();
      if (state === PLAYING || state === BUFFERING) {
        player.pauseVideo();
      } else {
        player.playVideo();
      }
      break;
    }
    case "seekBy": {
      const target = player.getCurrentTime() + action.seconds;
      player.seekTo(Math.max(0, Math.min(player.getDuration(), target)), true);
      break;
    }
    case "seekToFraction":
      player.seekTo(player.getDuration() * action.fraction, true);
      break;
    case "seekToEnd":
      player.seekTo(player.getDuration(), true);
      break;
    case "volumeBy": {
      const volume = Math.max(
        0,
        Math.min(100, player.getVolume() + action.step),
      );
      player.setVolume(volume);
      if (volume > 0 && player.isMuted()) {
        player.unMute();
      }
      break;
    }
    case "mute":
      if (player.isMuted()) {
        player.unMute();
      } else {
        player.mute();
      }
      break;
    case "speed":
      player.setPlaybackRate(
        nextRate(
          player.getAvailablePlaybackRates(),
          player.getPlaybackRate(),
          action.faster,
        ),
      );
      break;
    case "next":
      player.nextVideo();
      break;
    case "previous":
      player.previousVideo();
      break;
  }
}
