import { compileFilter, videoPassesFilter } from "./filters";
import type { Channel, FeedItem } from "./types";

/** What a channel list orders a channel by. */
export interface ChannelOrderKey {
  /** YouTube channel id */
  id: string;
  /** channel name */
  title: string;
  /** whether the channel is on */
  enabled: boolean;
  /** `publishedAt` of its newest item passing its filter; absent when none passes */
  newestPassing?: string;
}

function compareCodeUnits(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

// on with something passing, on with nothing passing, off
function group(key: ChannelOrderKey): number {
  if (!key.enabled) {
    return 2;
  } else if (key.newestPassing === undefined) {
    return 1;
  } else {
    return 0;
  }
}

/**
 * The order of every channel list: channels that are on with an item passing
 * their filter first, by the newest such item; then on with nothing passing;
 * then off. Ties and the last two groups go by title ignoring case, then id.
 */
export function compareChannelOrder(
  left: ChannelOrderKey,
  right: ChannelOrderKey,
): number {
  const leftGroup = group(left);
  return (
    leftGroup - group(right) ||
    (leftGroup === 0
      ? compareCodeUnits(right.newestPassing ?? "", left.newestPassing ?? "")
      : 0) ||
    compareCodeUnits(left.title.toLowerCase(), right.title.toLowerCase()) ||
    compareCodeUnits(left.id, right.id)
  );
}

/** Channels in list order, given the items loaded for them; watched items count. */
export function orderChannels(
  channels: readonly Channel[],
  items: Iterable<FeedItem>,
): Channel[] {
  const compiled = new Map(
    channels.map((channel) => [
      channel.channelId,
      {
        kind: channel.filter.contentMode === "playlists" ? "playlist" : "video",
        filter: compileFilter(channel.filter),
      },
    ]),
  );
  const newest = new Map<string, string>();
  for (const item of items) {
    const entry = compiled.get(item.channelId);
    const prior = newest.get(item.channelId);
    if (
      entry &&
      item.kind === entry.kind &&
      (prior === undefined || item.publishedAt > prior) &&
      videoPassesFilter(item, entry.filter)
    ) {
      newest.set(item.channelId, item.publishedAt);
    }
  }
  const key = (channel: Channel): ChannelOrderKey => ({
    id: channel.channelId,
    title: channel.title,
    enabled: channel.filter.enabled,
    newestPassing: newest.get(channel.channelId),
  });
  return channels.toSorted((left, right) =>
    compareChannelOrder(key(left), key(right)),
  );
}
