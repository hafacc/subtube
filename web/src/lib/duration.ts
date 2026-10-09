/**
 * Format a length in seconds as M:SS or H:MM:SS.
 */
export function formatDuration(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const paddedSeconds = String(seconds).padStart(2, "0");
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${paddedSeconds}`;
  } else {
    return `${minutes}:${paddedSeconds}`;
  }
}

/** Format a playlist's length as "N videos". */
export function videoCount(count: number): string {
  return count === 1 ? "1 video" : `${count} videos`;
}

const DAY_FORMAT = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
});
const DAY_AND_YEAR_FORMAT = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  year: "numeric",
});

/** A publish time as a short date ("Sep 24"), with the year when it isn't `now`'s. */
export function shortDate(publishedAt: string, now: Date = new Date()): string {
  const published = new Date(publishedAt);
  const format =
    published.getFullYear() === now.getFullYear()
      ? DAY_FORMAT
      : DAY_AND_YEAR_FORMAT;
  return format.format(published);
}
