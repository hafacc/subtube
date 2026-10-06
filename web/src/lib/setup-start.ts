import { type StartFrom, startMarks } from "./chips";
import { readJson, writeJson } from "./storage";
import type { FeedItem } from "./types";

/*
 * Setup's starting point, applied channel by channel
 * (shared/fixtures/setup-start.json): a channel's older items are marked
 * watched the first time its items are fully fetched, so a channel that
 * failed or was skipped in the first load is marked by a later one.
 */

/** A starting point still to apply to some channels. */
export interface PendingStart {
  /** the span chosen in setup */
  start: Exclude<StartFrom, "all">;
  /** when setup finished, in epoch milliseconds: the span counts back from here */
  cutoff: number;
  /** the channels that were on then and haven't been fetched since, by id */
  channels: string[];
}

/** What a fetch does with a pending starting point. */
export interface StartApplied {
  /** the ids to mark watched, in the order of the items given */
  marks: string[];
  /** what is still to apply; null once no channel is left */
  pending: PendingStart | null;
}

/** The starting point to keep when setup finishes; null when it marks nothing or no channel is on. */
export function pendingStart(
  start: StartFrom,
  cutoff: number,
  channelIds: readonly string[],
): PendingStart | null {
  if (start === "all" || channelIds.length === 0) {
    return null;
  } else {
    return { start, cutoff, channels: [...channelIds] };
  }
}

/**
 * Apply a pending starting point to the channels in `fetched`, whose items
 * were just fetched in full: their `items` published before the cut-off less
 * the span are marked, and they leave the pending channels. Channels not
 * pending, and pending ones not fetched, are untouched.
 */
export function applyStart(
  pending: PendingStart | null,
  fetched: Iterable<string>,
  items: readonly FeedItem[],
): StartApplied {
  if (pending === null) {
    return { marks: [], pending: null };
  } else {
    const done = new Set(fetched);
    const marked = new Set(pending.channels.filter((id) => done.has(id)));
    const channels = pending.channels.filter((id) => !done.has(id));
    return {
      marks: startMarks(
        items.filter((item) => marked.has(item.channelId)),
        pending.start,
        pending.cutoff,
      ),
      pending: channels.length > 0 ? { ...pending, channels } : null,
    };
  }
}

const PENDING_START_PREFIX = "subtube.startFrom.";

function isPending(value: unknown): value is PendingStart {
  const pending = value as Partial<PendingStart> | null;
  return (
    typeof pending === "object" &&
    pending !== null &&
    (pending.start === "day" || pending.start === "week") &&
    typeof pending.cutoff === "number" &&
    Array.isArray(pending.channels) &&
    pending.channels.every((id) => typeof id === "string")
  );
}

/** The starting point kept for an account on this browser; null when there is none. */
export function readPendingStart(accountId: string): PendingStart | null {
  const kept = readJson<unknown>(PENDING_START_PREFIX + accountId);
  return isPending(kept) ? kept : null;
}

/** Keep an account's pending starting point on this browser, or drop it (null). */
export function keepPendingStart(
  accountId: string,
  pending: PendingStart | null,
): void {
  writeJson(PENDING_START_PREFIX + accountId, pending);
}

/** The ids `items` of the fetched channels get marked with, taking those channels out of what is kept for the account. */
export function takeStartMarks(
  accountId: string,
  fetched: Iterable<string>,
  items: readonly FeedItem[],
): string[] {
  const before = readPendingStart(accountId);
  if (before === null) {
    return [];
  } else {
    const { marks, pending } = applyStart(before, fetched, items);
    keepPendingStart(accountId, pending);
    return marks;
  }
}
