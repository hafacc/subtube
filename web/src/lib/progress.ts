/*
 * How far a video has been played and when that makes it watched
 * (shared/fixtures/watch-progress.json). Drive carries the position; whether
 * the video is watched is worked out here from it and the video's length.
 */

/** A watched entry of a Drive file, as far as progress reads it. */
export interface WatchEntry {
  /** true for a mark, or a video whose player reported the end */
  watched: boolean;
  /** how far the video has been played, in seconds; anything else reads as none */
  position?: unknown;
  /** the video of a playlist that was playing; anything but a string reads as none */
  video?: unknown;
  /** how far through a playlist that is, from 0 to 1; anything else reads as none */
  progress?: unknown;
}

/** Where in a playlist its player is. */
export interface PlaylistPlace {
  /** the id of the playing video */
  video: string;
  /** how far through the playlist that is, from 0 to 1 ({@link playlistProgress}) */
  progress: number;
}

/** Where a playlist starts when opened. */
export interface PlaylistStart {
  /** the place of the video to start at among the playlist's videos, from 0 */
  index: number;
  /** how far into that video, in seconds */
  position: number;
}

/** A video this close to its end, in seconds, is watched. */
export const FINISHED_WITHIN_SECONDS = 10;

/** An entry's position in seconds; null when it has none. */
export function entryPosition(entry: WatchEntry | undefined): number | null {
  const position = entry?.position;
  return typeof position === "number" && position >= 0 ? position : null;
}

/**
 * Whether a video is watched: marked so, or played into the last
 * {@link FINISHED_WITHIN_SECONDS} of a length longer than that.
 */
export function isWatchedEntry(
  entry: WatchEntry | undefined,
  durationSeconds = 0,
): boolean {
  const position = entryPosition(entry);
  return (
    entry?.watched === true ||
    (position !== null &&
      durationSeconds > FINISHED_WITHIN_SECONDS &&
      position >= durationSeconds - FINISHED_WITHIN_SECONDS)
  );
}

/** Where a video starts when opened, in seconds: its position unless it is watched. */
export function resumePosition(
  entry: WatchEntry | undefined,
  durationSeconds = 0,
): number {
  return isWatchedEntry(entry, durationSeconds)
    ? 0
    : (entryPosition(entry) ?? 0);
}

/**
 * How full an item's progress bar is, from 0 to 1; null for no bar. A
 * playlist, which has no length, shows its entry's progress.
 */
export function progressFraction(
  entry: WatchEntry | undefined,
  durationSeconds = 0,
): number | null {
  const position = entryPosition(entry);
  const progress = entry?.progress;
  if (isWatchedEntry(entry, durationSeconds)) {
    return 1;
  } else if (durationSeconds > 0) {
    return position === null ? null : Math.min(1, position / durationSeconds);
  } else {
    return typeof progress === "number" && progress >= 0 && progress <= 1
      ? progress
      : null;
  }
}

/**
 * How far through a playlist its player is, from 0 to 1, counting every
 * video as equally long: `position` of `durationSeconds` into the video at
 * `index`, from 0, of `count`.
 */
export function playlistProgress(
  index: number,
  count: number,
  position: number,
  durationSeconds: number,
): number {
  if (count <= 0) {
    return 0;
  } else {
    const part =
      durationSeconds > 0
        ? Math.min(1, Math.max(0, position / durationSeconds))
        : 0;
    return Math.min(1, Math.max(0, (index + part) / count));
  }
}

/**
 * Where a playlist starts when opened: at the video that was playing, where
 * it was left, when `videos`, the ids its player loaded, still has it;
 * otherwise, and when it is watched, at its first video.
 */
export function playlistStart(
  entry: WatchEntry | undefined,
  videos: readonly string[],
): PlaylistStart {
  const video = entry?.video;
  const index =
    entry?.watched !== true && typeof video === "string"
      ? videos.indexOf(video)
      : -1;
  if (index < 0) {
    return { index: 0, position: 0 };
  } else {
    return { index, position: entryPosition(entry) ?? 0 };
  }
}
