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

/** How full a video's progress bar is, from 0 to 1; null for no bar. */
export function progressFraction(
  entry: WatchEntry | undefined,
  durationSeconds = 0,
): number | null {
  const position = entryPosition(entry);
  if (isWatchedEntry(entry, durationSeconds)) {
    return 1;
  } else if (position === null || durationSeconds <= 0) {
    return null;
  } else {
    return Math.min(1, position / durationSeconds);
  }
}
