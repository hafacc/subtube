import type { ChannelSort } from "./channel-order";
import type { TimeChip } from "./chips";
import { FEED_SORTS, type FeedSort } from "./feed-order";
import { oneOf } from "./values";

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
  /** the selected group chips' names */
  groupChips: string[];
  /** the channel list's selected group chips' names */
  channelGroupChips: string[];
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
  groupChips: [],
  channelGroupChips: [],
};

const CHANNEL_SORTS: readonly ChannelSort[] = ["newest", "name", "unwatched"];
const TIME_CHIPS: readonly TimeChip[] = ["none", "day", "week", "month"];

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
      entries.feedSort?.value,
      FEED_SORTS,
      DEFAULT_SETTINGS.feedSort,
    ),
    channelSort: oneOf(
      entries.channelSort?.value,
      CHANNEL_SORTS,
      DEFAULT_SETTINGS.channelSort,
    ),
    autoplay:
      typeof autoplay === "boolean" ? autoplay : DEFAULT_SETTINGS.autoplay,
    timeChip: oneOf(
      entries.timeChip?.value,
      TIME_CHIPS,
      DEFAULT_SETTINGS.timeChip,
    ),
    topicChips: stringsOr(
      entries.topicChips?.value,
      DEFAULT_SETTINGS.topicChips,
    ),
    channelTimeChip: oneOf(
      entries.channelTimeChip?.value,
      TIME_CHIPS,
      DEFAULT_SETTINGS.channelTimeChip,
    ),
    channelTopicChips: stringsOr(
      entries.channelTopicChips?.value,
      DEFAULT_SETTINGS.channelTopicChips,
    ),
    groupChips: stringsOr(
      entries.groupChips?.value,
      DEFAULT_SETTINGS.groupChips,
    ),
    channelGroupChips: stringsOr(
      entries.channelGroupChips?.value,
      DEFAULT_SETTINGS.channelGroupChips,
    ),
  };
}
