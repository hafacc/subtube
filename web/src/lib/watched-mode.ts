import { knownTopics, type TimeChip } from "./chips";
import { feedItemId } from "./feed-item";
import type { FeedItem } from "./types";

/** Which of watched and unwatched items a page lists. */
export type WatchedMode = "unwatched" | "watched" | "all";

/** The mode a visit starts in. */
export const DEFAULT_WATCHED_MODE: WatchedMode = "unwatched";

/** The watched modes a chip offers, in the order it moves through them; "all" has no chip. */
export const WATCHED_MODE_OPTIONS = [
  { value: "unwatched", label: "Unwatched" },
  { value: "watched", label: "Watched" },
] as const satisfies readonly { value: WatchedMode; label: string }[];

/**
 * The items a watched mode lists. An item in `staying`, one that changed
 * sides while it was on screen, is listed in every mode.
 */
export function modeFiltered(
  items: readonly FeedItem[],
  mode: WatchedMode,
  watched: ReadonlySet<string>,
  staying: ReadonlySet<string>,
): FeedItem[] {
  return items.filter((item) => {
    const id = feedItemId(item);
    return (
      mode === "all" ||
      watched.has(id) === (mode === "watched") ||
      staying.has(id)
    );
  });
}

/** Whether auto-play moves on in a mode: not among watched items only. */
export function autoplayAdvances(mode: WatchedMode): boolean {
  return mode !== "watched";
}

/**
 * Whether an empty list is empty because of what is selected, rather than
 * because nothing is left to watch: any mode but unwatched, a time chip, a
 * topic chip, or a group chip that narrows the list (`grouped`).
 */
export function emptiedBySelection(
  mode: WatchedMode,
  timeChip: TimeChip,
  topicChips: readonly string[],
  grouped = false,
): boolean {
  return (
    mode !== "unwatched" ||
    timeChip !== "none" ||
    knownTopics(topicChips).size > 0 ||
    grouped
  );
}
