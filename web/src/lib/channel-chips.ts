import { chipFiltered, knownTopics, type TimeChip } from "./chips";
import { compileFilter, videoPassesFilter } from "./filters";
import type { Channel, ContentMode, FeedItem } from "./types";

/** The kind of feed entry a content mode shows. */
export function kindFor(mode: ContentMode | undefined): FeedItem["kind"] {
  return mode === "playlists" ? "playlist" : "video";
}

/**
 * The items the channel list's chips look at: of the channels that are on,
 * every fetched item of the kind the channel shows that passes its filter,
 * watched or not, in the order given.
 */
export function passingItems(
  channels: Iterable<Channel>,
  items: readonly FeedItem[],
): FeedItem[] {
  const enabled = new Map(
    Array.from(channels)
      .filter((channel) => channel.filter.enabled)
      .map((channel) => [
        channel.channelId,
        {
          kind: kindFor(channel.filter.contentMode),
          filter: compileFilter(channel.filter),
        },
      ]),
  );
  return items.filter((item) => {
    const entry = enabled.get(item.channelId);
    return (
      entry !== undefined &&
      item.kind === entry.kind &&
      videoPassesFilter(item, entry.filter)
    );
  });
}

/**
 * The channels the channel list's chips keep, by id
 * (shared/fixtures/channel-chips.json): those with at least one of `items`
 * that is inside the time chip's span and, when a topic is selected, in a
 * selected topic. Null when no span and no topic is chosen, which keeps
 * every channel. `items` is {@link passingItems}.
 */
export function chipKeptChannels(
  items: readonly FeedItem[],
  timeChip: TimeChip,
  selected: readonly string[],
  now: number,
): Set<string> | null {
  if (timeChip === "none" && knownTopics(selected).size === 0) {
    return null;
  } else {
    return new Set(
      chipFiltered(items, timeChip, selected, now).map(
        ({ channelId }) => channelId,
      ),
    );
  }
}
