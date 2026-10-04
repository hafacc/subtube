/** Whether a filter keeps or drops what its pattern finds. */
export type FilterMode = "include" | "exclude";
/** What a filter's pattern is searched in. */
export type FilterScope = "title" | "both" | "description";
/** Whether a channel contributes its uploads or its playlists to the feed. */
export type ContentMode = "videos" | "playlists";
/**
 * A video's broadcast kind: "vod" is a finished live stream or premiere,
 * "normal" a plain upload that was never broadcast.
 */
export type LiveStatus = "upcoming" | "live" | "vod" | "normal";
/**
 * Per-channel broadcast filter: "all" keeps everything but upcoming, "vod" only
 * live streams and their replays, "normal" only plain uploads.
 */
export type LiveFilter = "all" | "vod" | "normal";
/** Per-channel Shorts filter: everything, no Shorts, or only Shorts. */
export type ShortsFilter = "all" | "normal" | "shorts";

/** A channel as YouTube names it; never saved in the Drive file. */
export interface ChannelInfo {
  /** YouTube channel id (UC…). */
  channelId: string;
  /** channel name */
  title: string;
  /** avatar URL; empty when there is none */
  thumbnail: string;
}

/** A YouTube subscription: the channel as YouTube names it. */
export type Subscription = ChannelInfo;

/**
 * A channel's saved filter, as kept in the Drive file
 * (shared/schema/device-file.schema.json). It never holds the channel's
 * identity; fields a newer client added are kept as they are.
 */
export interface ChannelFilter {
  /** whether the main feed loads this channel */
  enabled: boolean;
  /** pattern in the shared pattern language; "" is no pattern */
  regex: string;
  /** include keeps what the pattern finds; exclude drops it */
  mode: FilterMode;
  /** whether ASCII letters match case-sensitively; default false */
  caseSensitive?: boolean;
  /** what the pattern is searched in; default title */
  searchScope?: FilterScope;
  /** drop videos shorter than this many seconds; 0 or absent keeps all */
  minDurationSeconds?: number;
  /** which broadcast kinds to keep; default all */
  liveFilter?: LiveFilter;
  /** which of Shorts and other videos to keep; default all */
  shortsFilter?: ShortsFilter;
  /** whether the channel shows its uploads or its playlists; default videos */
  contentMode?: ContentMode;
  /** added in subtube rather than subscribed to on YouTube; listed while true */
  followed?: boolean;
  /** fields from a newer client, kept as they were */
  [unknown: string]: unknown;
}

/** A channel the feed reads: YouTube's identity plus the saved filter. */
export interface Channel extends ChannelInfo {
  /** the saved filter, or the default one */
  filter: ChannelFilter;
}

/** One uploaded video. */
export interface Video {
  /** discriminant */
  kind: "video";
  /** YouTube video id */
  videoId: string;
  /** the uploading channel */
  channelId: string;
  /** the uploading channel's name */
  channelTitle: string;
  /** title, HTML entities decoded */
  title: string;
  /** description */
  description: string;
  /** RFC 3339 publish time */
  publishedAt: string;
  /** thumbnail URL; empty when there is none */
  thumbnail: string;
  /** length in seconds; 0 or absent for live or upcoming */
  durationSeconds?: number;
  /** broadcast kind; absent reads as "normal" */
  liveStatus?: LiveStatus;
  /** whether it is a Short; absent means unknown */
  isShort?: boolean;
}

/** One of a channel's playlists, shown as a single feed entry. */
export interface Playlist {
  /** discriminant */
  kind: "playlist";
  /** YouTube playlist id */
  playlistId: string;
  /** the owning channel */
  channelId: string;
  /** the owning channel's name */
  channelTitle: string;
  /** title, HTML entities decoded */
  title: string;
  /** description */
  description: string;
  /** creation time, which orders it in the feed */
  publishedAt: string;
  /** thumbnail URL; empty when there is none */
  thumbnail: string;
  /** number of videos */
  itemCount: number;
}

/** A feed entry: a video, or a whole playlist for a channel showing playlists. */
export type FeedItem = Video | Playlist;
