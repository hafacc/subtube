import type { Channel, FeedItem } from "./types";

/** Whether setup may use a channel as its example: on, uploads, no "only matches" pattern. */
export function canBeExample(channel: Channel): boolean {
  const { filter } = channel;
  return (
    filter.enabled &&
    filter.contentMode !== "playlists" &&
    !(filter.mode === "include" && filter.regex !== "")
  );
}

interface Score {
  shorts: number;
  newest: string;
}

function score(items: readonly FeedItem[]): Score {
  let shorts = 0;
  let newest = "";
  for (const item of items) {
    if (item.kind === "video" && item.isShort === true) {
      shorts += 1;
    }
    if (item.publishedAt > newest) {
      newest = item.publishedAt;
    }
  }
  return { shorts, newest };
}

/**
 * Setup's example channel among those that {@link canBeExample}: the most Shorts
 * among its fetched videos, then the newest upload, then the lower channel id.
 */
export function pickExampleChannel(
  channels: readonly Channel[],
  itemsByChannel: ReadonlyMap<string, readonly FeedItem[]>,
): Channel | null {
  let best: { channel: Channel; score: Score } | null = null;
  for (const channel of channels.filter(canBeExample)) {
    const current = score(itemsByChannel.get(channel.channelId) ?? []);
    if (
      best === null ||
      current.shorts > best.score.shorts ||
      (current.shorts === best.score.shorts &&
        (current.newest > best.score.newest ||
          (current.newest === best.score.newest &&
            channel.channelId < best.channel.channelId)))
    ) {
      best = { channel, score: current };
    }
  }
  return best?.channel ?? null;
}
