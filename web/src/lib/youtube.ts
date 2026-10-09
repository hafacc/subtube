import { ShownError } from "./errors";
import { byNewest } from "./feed-order";
import { decodeHtmlEntities } from "./html";
import { classifyShorts, type ShortsList, withoutShortsList } from "./shorts";
import type {
  ChannelInfo,
  FeedItem,
  LiveStatus,
  Playlist,
  Video,
} from "./types";

const API_BASE = "https://www.googleapis.com/youtube/v3";

/** Google refused the token: it expired or was revoked. */
export class TokenExpiredError extends Error {
  constructor() {
    super("Google access token expired or missing");
    this.name = "TokenExpiredError";
  }
}

/** The playlist doesn't exist; a channel with no Shorts has no Shorts list. */
export class PlaylistNotFoundError extends Error {
  constructor(playlistId: string) {
    super(`Playlist ${playlistId} not found`);
    this.name = "PlaylistNotFoundError";
  }
}

/**
 * The token is valid but lacks a scope subtube asked for: the user unticked
 * YouTube or Drive access on Google's consent screen. Signing in again fixes it.
 */
export class InsufficientScopeError extends ShownError {
  constructor() {
    super(
      "SubTube needs both permissions Google asks for. Sign in again and allow them.",
    );
    this.name = "InsufficientScopeError";
  }
}

/** What the app says when YouTube's daily limit is used up. */
export const DAILY_LIMIT_MESSAGE =
  "SubTube has reached YouTube's daily limit. Try again after midnight Pacific time.";

/** YouTube refused a request because the app's daily quota is used up; asking again today can't work. */
export class DailyLimitError extends ShownError {
  constructor() {
    super(DAILY_LIMIT_MESSAGE);
    this.name = "DailyLimitError";
  }
}

const DAILY_LIMIT_REASONS: readonly unknown[] = [
  "quotaExceeded",
  "dailyLimitExceeded",
];

/**
 * Whether an answer says the daily quota is used up: status 403 with a JSON
 * body whose `error.errors` holds a `reason` of `quotaExceeded` or
 * `dailyLimitExceeded`. The per-minute `rateLimitExceeded` is not it.
 */
export function isDailyLimit(status: number, body: string): boolean {
  if (status !== 403) {
    return false;
  } else {
    try {
      const errors: unknown = JSON.parse(body)?.error?.errors;
      return (
        Array.isArray(errors) &&
        errors.some((entry) => DAILY_LIMIT_REASONS.includes(entry?.reason))
      );
    } catch {
      return false;
    }
  }
}

/** Whether a Google answer says the token lacks a scope: status 403 naming a missing permission. */
export function isMissingScope(status: number, body: string): boolean {
  return (
    status === 403 &&
    (body.includes("ACCESS_TOKEN_SCOPE_INSUFFICIENT") ||
      body.includes("insufficientPermissions"))
  );
}

/** Google answered a request with a status that has no meaning of its own here. */
export class GoogleRequestError extends Error {
  /** Carries the HTTP `status` Google answered with. */
  constructor(readonly status: number) {
    super(`Google request failed: ${status}`);
    this.name = "GoogleRequestError";
  }
}

async function apiGet<Response>(
  path: string,
  params: Record<string, string>,
  token: string,
): Promise<Response> {
  const url = new URL(API_BASE + path);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 401) {
    throw new TokenExpiredError();
  } else if (response.ok) {
    return response.json() as Promise<Response>;
  } else {
    const body = await response.text();
    if (isMissingScope(response.status, body)) {
      throw new InsufficientScopeError();
    } else if (isDailyLimit(response.status, body)) {
      throw new DailyLimitError();
    } else if (response.status === 404 && body.includes("playlistNotFound")) {
      throw new PlaylistNotFoundError(params.playlistId ?? "");
    } else {
      console.error(`YouTube API ${path} failed: ${response.status} ${body}`);
      throw new GoogleRequestError(response.status);
    }
  }
}

interface SubscriptionListResponse {
  items: Array<{
    snippet: {
      title: string;
      resourceId: { channelId: string };
      thumbnails: { default?: { url: string }; medium?: { url: string } };
    };
  }>;
  nextPageToken?: string;
}

/**
 * A channel's picture: the 88px one, which covers the largest avatar drawn
 * (40px) on a screen of twice the density; "" when it has none.
 */
export function channelPicture(thumbnails: {
  default?: { url: string };
  medium?: { url: string };
}): string {
  return thumbnails.default?.url ?? thumbnails.medium?.url ?? "";
}

/** The account's YouTube subscriptions, alphabetically. */
export async function fetchSubscriptions(
  token: string,
): Promise<ChannelInfo[]> {
  const subscriptions: ChannelInfo[] = [];
  let pageToken: string | undefined;
  do {
    const params: Record<string, string> = {
      part: "snippet",
      mine: "true",
      maxResults: "50",
      order: "alphabetical",
    };
    if (pageToken) {
      params.pageToken = pageToken;
    }
    const data = await apiGet<SubscriptionListResponse>(
      "/subscriptions",
      params,
      token,
    );
    for (const item of data.items) {
      subscriptions.push({
        channelId: item.snippet.resourceId.channelId,
        title: decodeHtmlEntities(item.snippet.title),
        thumbnail: channelPicture(item.snippet.thumbnails),
      });
    }
    pageToken = data.nextPageToken;
  } while (pageToken);
  return subscriptions;
}

interface PlaylistItemsResponse {
  items: Array<{
    snippet: {
      title: string;
      description: string;
      publishedAt: string;
      videoOwnerChannelId?: string;
      videoOwnerChannelTitle?: string;
      thumbnails: {
        default?: { url: string };
        medium?: { url: string };
        high?: { url: string };
      };
    };
    contentDetails: { videoId: string; videoPublishedAt?: string };
  }>;
  nextPageToken?: string;
}

/**
 * A channel's uploads playlist ID is its channel ID with the "UC" prefix swapped
 * for "UU", which lets us list uploads without spending a channels.list call.
 */
export function uploadsPlaylistId(channelId: string): string {
  return `UU${channelId.slice(2)}`;
}

/**
 * A channel's Shorts, as their own playlist: "UUSH" in place of "UC". YouTube
 * keeps one beside the uploads list (as it does "UULF" for regular videos and
 * "UULV" for live streams); undocumented, like the /shorts/ redirect.
 */
export function shortsPlaylistId(channelId: string): string {
  return `UUSH${channelId.slice(2)}`;
}

const HIDDEN_TITLES = new Set(["Private video", "Deleted video"]);

interface VideoListResponse {
  items: Array<{
    id: string;
    snippet: {
      liveBroadcastContent: "none" | "live" | "upcoming";
      categoryId?: string;
    };
    contentDetails: { duration: string };
    // present only if the video was ever a live stream or premiere
    liveStreamingDetails?: { actualEndTime?: string };
  }>;
}

/** What videos.list adds to a playlist entry. */
export interface VideoDetails {
  /** length in seconds; 0 for live or upcoming */
  durationSeconds: number;
  /** broadcast kind */
  liveStatus: LiveStatus;
  /** YouTube's category id; absent when it has none */
  categoryId?: string;
}

/**
 * Classify a video as live/upcoming/vod/normal. A finished broadcast (a stream
 * replay or aired premiere) reports liveBroadcastContent "none" but carries
 * liveStreamingDetails with an actualEndTime; a plain upload has neither.
 */
function classifyLiveStatus(
  item: VideoListResponse["items"][number],
): LiveStatus {
  if (item.snippet.liveBroadcastContent === "live") {
    return "live";
  } else if (item.snippet.liveBroadcastContent === "upcoming") {
    return "upcoming";
  } else {
    return item.liveStreamingDetails?.actualEndTime ? "vod" : "normal";
  }
}

/**
 * Parse an ISO 8601 duration (e.g. "PT1H2M3S", "P1DT4M") to seconds. Live and
 * upcoming videos report "P0D" (no time part), which yields 0.
 */
export function parseIsoDuration(iso: string): number {
  const match = /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(
    iso,
  );
  if (!match) {
    return 0;
  } else {
    const [days, hours, minutes, seconds] = match
      .slice(1)
      .map((part) => Number(part ?? 0));
    return days * 86400 + hours * 3600 + minutes * 60 + seconds;
  }
}

/**
 * playlistItems doesn't expose duration, broadcast kind or category, so fetch those from
 * videos.list separately (50 ids per call, flat 1 unit regardless of parts) and
 * key by video id.
 */
export async function fetchVideoDetails(
  videoIds: string[],
  token: string,
): Promise<Map<string, VideoDetails>> {
  const details = new Map<string, VideoDetails>();
  for (let start = 0; start < videoIds.length; start += 50) {
    const batch = videoIds.slice(start, start + 50);
    const data = await apiGet<VideoListResponse>(
      "/videos",
      {
        part: "snippet,contentDetails,liveStreamingDetails",
        id: batch.join(","),
      },
      token,
    );
    for (const item of data.items) {
      details.set(item.id, {
        durationSeconds: parseIsoDuration(item.contentDetails.duration),
        liveStatus: classifyLiveStatus(item),
        categoryId: item.snippet.categoryId,
      });
    }
  }
  return details;
}

/**
 * The details of the videos among `items` that YouTube won't change: those
 * with a length that are not live or upcoming, by video id. A fetch given
 * them asks videos.list only for the others.
 */
export function settledDetails(
  items: Iterable<FeedItem>,
): Map<string, VideoDetails> {
  const settled = new Map<string, VideoDetails>();
  for (const item of items) {
    if (
      item.kind === "video" &&
      item.durationSeconds &&
      (item.liveStatus === "normal" || item.liveStatus === "vod")
    ) {
      settled.set(item.videoId, {
        durationSeconds: item.durationSeconds,
        liveStatus: item.liveStatus,
        categoryId: item.categoryId,
      });
    }
  }
  return settled;
}

/** One page of a playlist's entries; a playlist YouTube says it can't find has none. */
async function playlistPage(
  playlistId: string,
  maxResults: number,
  token: string,
): Promise<PlaylistItemsResponse["items"]> {
  try {
    const data = await apiGet<PlaylistItemsResponse>(
      "/playlistItems",
      {
        part: "snippet,contentDetails",
        playlistId,
        maxResults: String(maxResults),
      },
      token,
    );
    return data.items;
  } catch (caught) {
    if (caught instanceof PlaylistNotFoundError) {
      return [];
    } else {
      throw caught;
    }
  }
}

/**
 * A channel's newest uploads, each with its duration and broadcast kind, and
 * with `judgeShorts` whether it is a Short; without, the Shorts list is not
 * fetched and a video that could be a Short is left unjudged. `probe` asks
 * /shorts/{id} directly, where the platform can. A channel with no uploads,
 * whose uploads list YouTube answers "not found" for, has none. A video in
 * `known` ({@link settledDetails}) keeps those details and is not asked for.
 */
export async function fetchUploads(
  channelId: string,
  channelTitle: string,
  token: string,
  maxResults = 15,
  probe?: (videoId: string) => Promise<boolean | null>,
  judgeShorts = true,
  known: ReadonlyMap<string, VideoDetails> = new Map(),
): Promise<Video[]> {
  const entries = await playlistPage(
    uploadsPlaylistId(channelId),
    maxResults,
    token,
  );
  const videos = entries
    .filter((item) => !HIDDEN_TITLES.has(item.snippet.title))
    .map((item) => ({
      kind: "video" as const,
      videoId: item.contentDetails.videoId,
      channelId: item.snippet.videoOwnerChannelId ?? channelId,
      channelTitle: decodeHtmlEntities(
        item.snippet.videoOwnerChannelTitle ?? channelTitle,
      ),
      title: decodeHtmlEntities(item.snippet.title),
      description: item.snippet.description,
      publishedAt:
        item.contentDetails.videoPublishedAt ?? item.snippet.publishedAt,
      thumbnail:
        item.snippet.thumbnails.medium?.url ??
        item.snippet.thumbnails.default?.url ??
        "",
    }));

  const details = await fetchVideoDetails(
    videos.map((video) => video.videoId).filter((id) => !known.has(id)),
    token,
  );
  const detailed = videos.map((video) => {
    const detail = known.get(video.videoId) ?? details.get(video.videoId);
    return {
      ...video,
      durationSeconds: detail?.durationSeconds ?? 0,
      liveStatus: detail?.liveStatus ?? "normal",
      categoryId: detail?.categoryId,
    };
  });
  if (judgeShorts) {
    return markShorts(detailed, channelId, token, maxResults, probe);
  } else {
    return withoutShortsList(detailed);
  }
}

/**
 * Say which of a channel's already fetched uploads are Shorts, from its
 * Shorts list; `maxResults` is the size of the uploads page they came from.
 */
export function markShorts(
  videos: Video[],
  channelId: string,
  token: string,
  maxResults: number,
  probe?: (videoId: string) => Promise<boolean | null>,
): Promise<Video[]> {
  return classifyShorts(
    videos,
    () => fetchShortIds(channelId, token, maxResults),
    probe,
  );
}

interface PlaylistListResponse {
  items: Array<{
    id: string;
    snippet: {
      title: string;
      description: string;
      publishedAt: string;
      channelId?: string;
      channelTitle?: string;
      thumbnails: {
        default?: { url: string };
        medium?: { url: string };
        high?: { url: string };
      };
    };
    contentDetails: { itemCount: number };
  }>;
  nextPageToken?: string;
}

/**
 * A channel's public, self-made playlists. playlists.list has no order param and
 * only a creation timestamp, so we sort by that (newest first) ourselves — right
 * for episode-per-playlist channels, the intended use. One page (50) keeps it
 * quota-neutral with the uploads path; that's ~a year of weekly episodes.
 */
export async function fetchPlaylists(
  channelId: string,
  channelTitle: string,
  token: string,
  maxResults = 50,
): Promise<Playlist[]> {
  const data = await apiGet<PlaylistListResponse>(
    "/playlists",
    {
      part: "snippet,contentDetails",
      channelId,
      maxResults: String(maxResults),
    },
    token,
  );
  return data.items
    .map((item) => ({
      kind: "playlist" as const,
      playlistId: item.id,
      channelId: item.snippet.channelId ?? channelId,
      channelTitle: decodeHtmlEntities(
        item.snippet.channelTitle ?? channelTitle,
      ),
      title: decodeHtmlEntities(item.snippet.title),
      description: item.snippet.description,
      publishedAt: item.snippet.publishedAt,
      thumbnail:
        item.snippet.thumbnails.medium?.url ??
        item.snippet.thumbnails.default?.url ??
        "",
      itemCount: item.contentDetails.itemCount,
    }))
    .sort(byNewest);
}

/**
 * The ids of a channel's newest Shorts; null when it has no Shorts list
 * (404 `playlistNotFound`), "failed" when the list couldn't be read.
 * Every Short among a channel's newest `max` uploads is among its newest `max`
 * Shorts, so this one page judges every video of an uploads page that size.
 *
 * For some channels with no Shorts YouTube answers 500 `backendError`
 * instead of the 404: a 5xx here, after one retry, or a request that never
 * got an answer, is "failed".
 */
export async function fetchShortIds(
  channelId: string,
  token: string,
  max = 50,
): Promise<ShortsList> {
  const playlistId = shortsPlaylistId(channelId);
  const request = async () => {
    const data = await apiGet<PlaylistItemsResponse>(
      "/playlistItems",
      { part: "contentDetails", playlistId, maxResults: String(max) },
      token,
    );
    return new Set(data.items.map((item) => item.contentDetails.videoId));
  };
  const isServerError = (caught: unknown) =>
    caught instanceof GoogleRequestError && caught.status >= 500;
  try {
    try {
      return await request();
    } catch (caught) {
      if (!isServerError(caught)) {
        throw caught;
      }
      console.error(`Shorts list ${playlistId} failed; trying once more`);
      return await request();
    }
  } catch (caught) {
    if (caught instanceof PlaylistNotFoundError) {
      return null;
    } else if (isServerError(caught) || caught instanceof TypeError) {
      console.error(`Shorts list ${playlistId} couldn't be read`);
      return "failed";
    } else {
      throw caught;
    }
  }
}

interface ChannelListResponse {
  items?: Array<{
    id: string;
    snippet: {
      title: string;
      thumbnails: { default?: { url: string }; medium?: { url: string } };
    };
  }>;
}

function toInfo(
  item: NonNullable<ChannelListResponse["items"]>[number],
): ChannelInfo {
  return {
    channelId: item.id,
    title: decodeHtmlEntities(item.snippet.title),
    thumbnail: channelPicture(item.snippet.thumbnails),
  };
}

/** The signed-in Google account has no YouTube channel, which keys everything kept for an account. */
export class NoChannelError extends ShownError {
  constructor() {
    super("This Google account has no YouTube channel.");
    this.name = "NoChannelError";
  }
}

/** The signed-in account's own channel: its id keys everything stored for the account. */
export async function fetchMyChannel(token: string): Promise<ChannelInfo> {
  const data = await apiGet<ChannelListResponse>(
    "/channels",
    { part: "snippet", mine: "true" },
    token,
  );
  const mine = data.items?.[0];
  if (mine) {
    return toInfo(mine);
  } else {
    throw new NoChannelError();
  }
}

/** Channels by id, 50 per call (1 quota unit each); ids YouTube doesn't know are left out. */
export async function fetchChannelsById(
  channelIds: string[],
  token: string,
): Promise<ChannelInfo[]> {
  const found: ChannelInfo[] = [];
  for (let start = 0; start < channelIds.length; start += 50) {
    const data = await apiGet<ChannelListResponse>(
      "/channels",
      {
        part: "snippet",
        id: channelIds.slice(start, start + 50).join(","),
        maxResults: "50",
      },
      token,
    );
    found.push(...(data.items ?? []).map(toInfo));
  }
  return found;
}
