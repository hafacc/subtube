import { compareIgnoringCase } from "./text-order";
import type { Channel, FeedItem } from "./types";

/** The orders the channel list can be read in. */
export type ChannelSort = "newest" | "name" | "unwatched";

/** The channel list's orders, in menu order. */
export const CHANNEL_SORT_OPTIONS = [
  { value: "newest", label: "Latest" },
  { value: "name", label: "Name" },
  { value: "unwatched", label: "Unwatched" },
] as const satisfies readonly { value: ChannelSort; label: string }[];

/** What a channel list orders a channel by. */
export interface ChannelOrderKey {
  /** YouTube channel id */
  id: string;
  /** channel name */
  title: string;
  /** whether the channel is on */
  enabled: boolean;
  /** `publishedAt` of its newest fetched item; absent when it has none */
  newest?: string;
  /** how many of its unwatched items pass its filter; absent reads as 0 */
  unwatched?: number;
}

function compareCodeUnits(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

// on with something fetched, on with nothing fetched, off
function group(key: ChannelOrderKey): number {
  if (!key.enabled) {
    return 2;
  } else if (key.newest === undefined) {
    return 1;
  } else {
    return 0;
  }
}

function byName(left: ChannelOrderKey, right: ChannelOrderKey): number {
  return (
    compareIgnoringCase(left.title, right.title) ||
    compareCodeUnits(left.id, right.id)
  );
}

function byNewestVideo(left: ChannelOrderKey, right: ChannelOrderKey): number {
  const leftGroup = group(left);
  return (
    leftGroup - group(right) ||
    (leftGroup === 0
      ? compareCodeUnits(right.newest ?? "", left.newest ?? "")
      : 0) ||
    byName(left, right)
  );
}

/**
 * The order of every channel list (shared/fixtures/channel-order.json).
 * Channels that are off go last, by name, in every sort. Those that are on go
 * by newest fetched item (then the ones with nothing fetched), by name, or by
 * unwatched count with ties in newest-item order.
 */
export function compareChannelOrder(
  left: ChannelOrderKey,
  right: ChannelOrderKey,
  sort: ChannelSort = "newest",
): number {
  if (!left.enabled || !right.enabled) {
    return (
      Number(!left.enabled) - Number(!right.enabled) || byName(left, right)
    );
  } else if (sort === "name") {
    return byName(left, right);
  } else if (sort === "unwatched") {
    return (
      (right.unwatched ?? 0) - (left.unwatched ?? 0) ||
      byNewestVideo(left, right)
    );
  } else {
    return byNewestVideo(left, right);
  }
}

/** Channels in list order, given the items fetched for them and each one's unwatched count. */
export function orderChannels(
  channels: readonly Channel[],
  items: Iterable<FeedItem>,
  sort: ChannelSort = "newest",
  unwatched: ReadonlyMap<string, number> = new Map(),
): Channel[] {
  const newest = new Map<string, string>();
  for (const item of items) {
    const prior = newest.get(item.channelId);
    if (prior === undefined || item.publishedAt > prior) {
      newest.set(item.channelId, item.publishedAt);
    }
  }
  const key = (channel: Channel): ChannelOrderKey => ({
    id: channel.channelId,
    title: channel.title,
    enabled: channel.filter.enabled,
    newest: newest.get(channel.channelId),
    unwatched: unwatched.get(channel.channelId),
  });
  return channels.toSorted((left, right) =>
    compareChannelOrder(key(left), key(right), sort),
  );
}

/**
 * `fresh` in the order of the ids in `held`: a channel among them keeps its
 * place, and the others follow in the order `fresh` has them.
 */
export function inHeldOrder(
  fresh: readonly Channel[],
  held: readonly string[],
): Channel[] {
  const places = new Map(held.map((channelId, index) => [channelId, index]));
  const place = (channel: Channel): number =>
    places.get(channel.channelId) ?? held.length;
  // toSorted is stable, so the channels with no place stay in fresh order
  return fresh.toSorted((left, right) => place(left) - place(right));
}

/**
 * A channel list's order, held while the list is worked in: the list is put
 * in order only when the moment it is shown for changes, so a switch, a mark
 * or a filter edit in between changes a row without moving it or taking it
 * out.
 */
export class HeldChannelOrder {
  private moment: string | null = null;
  private held: string[] = [];

  /**
   * The channels as the list shows them. `fresh` is every channel in sorted
   * order and `kept` the ids the list's chips keep (null for all of them).
   * When `moment` differs from the last call's, the kept channels are taken
   * as they are; otherwise the channels shown then stay, joined by any kept
   * since, rearranged by {@link inHeldOrder}.
   */
  arrange(
    fresh: readonly Channel[],
    moment: string,
    kept: ReadonlySet<string> | null = null,
  ): Channel[] {
    const isKept = ({ channelId }: Channel): boolean =>
      kept === null || kept.has(channelId);
    if (moment === this.moment) {
      const shown = new Set(this.held);
      return inHeldOrder(
        fresh.filter(
          (channel) => shown.has(channel.channelId) || isKept(channel),
        ),
        this.held,
      );
    } else {
      const listed = fresh.filter(isKept);
      this.moment = moment;
      this.held = listed.map(({ channelId }) => channelId);
      return listed;
    }
  }
}
