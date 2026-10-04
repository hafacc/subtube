import type { ChannelInfo } from "./types";
import { fetchChannelsById } from "./youtube";

/*
 * Names and pictures of channels followed in subtube. The Drive file never holds
 * them (YouTube owns a channel's identity) and subscriptions don't list these
 * channels, so they are looked up by id and kept here between loads.
 */
const STORAGE_KEY = "subtube.channelInfo";
/** A kept entry older than this is looked up again on the next load. */
const REFRESH_AFTER_MS = 24 * 60 * 60 * 1000;

interface StoredInfo extends ChannelInfo {
  /** when it was looked up, in epoch milliseconds */
  fetchedAt: number;
}

function readStored(): Record<string, StoredInfo> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Record<string, StoredInfo>) : {};
  } catch {
    return {};
  }
}

function writeStored(stored: Record<string, StoredInfo>): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
  } catch {
    // the next load looks them up again
  }
}

/** The kept identity of each of these channels, without asking YouTube. */
export function cachedChannelInfo(
  channelIds: string[],
): Map<string, ChannelInfo> {
  const stored = readStored();
  const found = new Map<string, ChannelInfo>();
  for (const channelId of channelIds) {
    const info = stored[channelId];
    if (info) {
      found.set(channelId, info);
    }
  }
  return found;
}

/** Forget every kept channel identity. */
export function clearChannelInfo(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // nothing was kept
  }
}

/**
 * The identity of each of these channels: kept entries as they are, missing or
 * old ones looked up with channels.list (50 ids per quota unit).
 */
export async function channelInfo(
  channelIds: string[],
  token: string,
  now = Date.now(),
): Promise<Map<string, ChannelInfo>> {
  const stored = readStored();
  const stale = channelIds.filter(
    (channelId) =>
      !stored[channelId] ||
      now - stored[channelId].fetchedAt > REFRESH_AFTER_MS,
  );
  if (stale.length > 0) {
    for (const summary of await fetchChannelsById(stale, token)) {
      stored[summary.channelId] = {
        channelId: summary.channelId,
        title: summary.title,
        thumbnail: summary.thumbnail,
        fetchedAt: now,
      };
    }
    writeStored(stored);
  }
  return cachedChannelInfo(channelIds);
}
