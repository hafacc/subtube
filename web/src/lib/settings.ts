import type { ChannelSort } from "./channel-order";
import type { TimeChip } from "./chips";
import type { FeedSort } from "./feed-order";

/** The settings synced through the Drive file, as this version reads them. */
export interface Settings {
  /** the feed's order */
  feedSort: FeedSort;
  /** the channel list's order */
  channelSort: ChannelSort;
  /** whether the next unwatched item plays when one ends */
  autoplay: boolean;
  /** the selected time chip */
  timeChip: TimeChip;
  /** the selected topic chips' category ids */
  topicChips: string[];
  /** the channel list's selected time chip */
  channelTimeChip: TimeChip;
  /** the channel list's selected topic chips' category ids */
  channelTopicChips: string[];
}

/** What a setting reads as when it is missing or holds a value this version doesn't know. */
export const DEFAULT_SETTINGS: Settings = {
  feedSort: "newest",
  channelSort: "newest",
  autoplay: false,
  timeChip: "none",
  topicChips: [],
  channelTimeChip: "none",
  channelTopicChips: [],
};

const FEED_SORTS: readonly FeedSort[] = [
  "newest",
  "shortest",
  "title",
  "random",
];
const CHANNEL_SORTS: readonly ChannelSort[] = ["newest", "name", "unwatched"];
const TIME_CHIPS: readonly TimeChip[] = ["none", "day", "week", "month"];

function oneOf<Value extends string>(
  options: readonly Value[],
  value: unknown,
  fallback: Value,
): Value {
  return options.find((option) => option === value) ?? fallback;
}

function stringsOr(value: unknown, fallback: string[]): string[] {
  return Array.isArray(value) && value.every((id) => typeof id === "string")
    ? value
    : fallback;
}

/** The settings in a merged view's `settings` map (shared/fixtures/settings.json). */
export function readSettings(
  entries: Readonly<Record<string, { value: unknown }>>,
): Settings {
  const autoplay = entries.autoplay?.value;
  return {
    feedSort: oneOf(
      FEED_SORTS,
      entries.feedSort?.value,
      DEFAULT_SETTINGS.feedSort,
    ),
    channelSort: oneOf(
      CHANNEL_SORTS,
      entries.channelSort?.value,
      DEFAULT_SETTINGS.channelSort,
    ),
    autoplay:
      typeof autoplay === "boolean" ? autoplay : DEFAULT_SETTINGS.autoplay,
    timeChip: oneOf(
      TIME_CHIPS,
      entries.timeChip?.value,
      DEFAULT_SETTINGS.timeChip,
    ),
    topicChips: stringsOr(
      entries.topicChips?.value,
      DEFAULT_SETTINGS.topicChips,
    ),
    channelTimeChip: oneOf(
      TIME_CHIPS,
      entries.channelTimeChip?.value,
      DEFAULT_SETTINGS.channelTimeChip,
    ),
    channelTopicChips: stringsOr(
      entries.channelTopicChips?.value,
      DEFAULT_SETTINGS.channelTopicChips,
    ),
  };
}
