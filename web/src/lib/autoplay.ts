import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

/** The auto-play chip's choices, in the order it moves through them. */
export const AUTOPLAY_OPTIONS = [
  { value: "off", label: "Play one" },
  { value: "on", label: "Auto-play" },
] as const satisfies readonly { value: "off" | "on"; label: string }[];

/**
 * What auto-play plays after `endedId`: the first unwatched item after it in
 * the list shown. Null at the end of the list, or when the ended item isn't
 * in it.
 */
export function nextUnwatched(
  shown: readonly FeedItem[],
  endedId: string,
  watched: ReadonlySet<string>,
): FeedItem | null {
  const position = shown.findIndex((item) => feedItemId(item) === endedId);
  if (position === -1) {
    return null;
  } else {
    return (
      shown
        .slice(position + 1)
        .find((item) => !watched.has(feedItemId(item))) ?? null
    );
  }
}
