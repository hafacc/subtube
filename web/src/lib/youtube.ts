import { decodeHtmlEntities } from "./html";
import { classifyShorts } from "./shorts";
import type { ChannelInfo, LiveStatus, Playlist, Video } from "./types";

const API_BASE = "https://www.googleapis.com/youtube/v3";

/** Google refused the token: it expired or was revoked. */
export class TokenExpiredError extends Error {
  constructor() {
    super("YouTube access token expired or missing");
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
export class InsufficientScopeError extends Error {
  constructor() {
    super(
      "SubTube needs both permissions Google asks for. Sign in again and allow them.",
    );
    this.name = "InsufficientScopeError";
  }
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
  }
  if (!response.ok) {
    const body = await response.text();
    if (
      response.status === 403 &&
      (body.includes("ACCESS_TOKEN_SCOPE_INSUFFICIENT") ||
        body.includes("insufficientPermissions"))
    ) {
      throw new InsufficientScopeError();
    }
    if (response.status === 404 && body.includes("playlistNotFound")) {
      throw new PlaylistNotFoundError(params.playlistId ?? "");
    }
    console.error(`YouTube API ${path} failed: ${response.status} ${body}`);
    throw new GoogleRequestError(response.status);
  }
  return response.json() as Promise<Response>;
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
        thumbnail:
          item.snippet.thumbnails.medium?.url ??
          item.snippet.thumbnails.default?.url ??
          "",
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
    snippet: { liveBroadcastContent: "none" | "live" | "upcoming" };
    contentDetails: { duration: string };
    // Present only if the video was ever a live stream or premiere.
    liveStreamingDetails?: { actualEndTime?: string };
  }>;
}

/** What videos.list adds to a playlist entry. */
export interface VideoDetails {
  /** length in seconds; 0 for live or upcoming */
  durationSeconds: number;
  /** broadcast kind */
  liveStatus: LiveStatus;
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
  }
  if (item.snippet.liveBroadcastContent === "upcoming") {
    return "upcoming";
  }
  return item.liveStreamingDetails?.actualEndTime ? "vod" : "normal";
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
  }
  const [days, hours, minutes, seconds] = match
    .slice(1)
    .map((part) => Number(part ?? 0));
  return days * 86400 + hours * 3600 + minutes * 60 + seconds;
}

/**
 * playlistItems doesn't expose duration or broadcast kind, so fetch those from
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
      });
    }
  }
  return details;
}

/**
 * A channel's newest uploads, each with its duration, broadcast kind and
 * Short-ness. `probe` asks /shorts/{id} directly, where the platform can.
 */
export async function fetchUploads(
  channelId: string,
  channelTitle: string,
  token: string,
  maxResults = 15,
  probe?: (videoId: string) => Promise<boolean | null>,
): Promise<Video[]> {
  const data = await apiGet<PlaylistItemsResponse>(
    "/playlistItems",
    {
      part: "snippet,contentDetails",
      playlistId: uploadsPlaylistId(channelId),
      maxResults: String(maxResults),
    },
    token,
  );
  const videos = data.items
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
    videos.map((video) => video.videoId),
    token,
  );
  const detailed = videos.map((video) => {
    const detail = details.get(video.videoId);
    return {
      ...video,
      durationSeconds: detail?.durationSeconds ?? 0,
      liveStatus: detail?.liveStatus ?? "normal",
    };
  });
  return classifyShorts(
    detailed,
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
    .sort((left, right) => right.publishedAt.localeCompare(left.publishedAt));
}

/**
 * The ids of a channel's newest Shorts, or null when it has no Shorts list.
 * Every Short among a channel's newest `max` uploads is among its newest `max`
 * Shorts, so this one page judges every video of an uploads page that size.
 *
 * A channel with no Shorts is usually answered 404 `playlistNotFound`, but for
 * some YouTube answers 500 `backendError`: a 5xx here, after one retry, also
 * reads as no list.
 */
export async function fetchShortIds(
  channelId: string,
  token: string,
  max = 50,
): Promise<Set<string> | null> {
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
    } else if (isServerError(caught)) {
      console.error(`Shorts list ${playlistId} failed again; read as missing`);
      return null;
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
      customUrl?: string;
      thumbnails: { default?: { url: string }; medium?: { url: string } };
    };
    statistics?: { subscriberCount?: string; hiddenSubscriberCount?: boolean };
  }>;
}

/** A channel as subtube lists it outside the feed. */
export interface ChannelSummary extends ChannelInfo {
  /** the @handle, when the channel has one */
  handle?: string;
  /** Undefined when the channel hides it. */
  subscriberCount?: number;
}

function toSummary(
  item: NonNullable<ChannelListResponse["items"]>[number],
): ChannelSummary {
  const hidden = item.statistics?.hiddenSubscriberCount ?? true;
  return {
    channelId: item.id,
    title: decodeHtmlEntities(item.snippet.title),
    thumbnail:
      item.snippet.thumbnails.medium?.url ??
      item.snippet.thumbnails.default?.url ??
      "",
    handle: item.snippet.customUrl,
    subscriberCount:
      hidden || item.statistics?.subscriberCount === undefined
        ? undefined
        : Number(item.statistics.subscriberCount),
  };
}

/** The signed-in account's own channel: its id keys everything stored for the account. */
export async function fetchMyChannel(token: string): Promise<ChannelSummary> {
  const data = await apiGet<ChannelListResponse>(
    "/channels",
    { part: "snippet", mine: "true" },
    token,
  );
  const mine = data.items?.[0];
  if (mine) {
    return toSummary(mine);
  } else {
    throw new Error("This Google account has no YouTube channel.");
  }
}

/** Channels by id, 50 per call (1 quota unit each); ids YouTube doesn't know are left out. */
export async function fetchChannelsById(
  channelIds: string[],
  token: string,
): Promise<ChannelSummary[]> {
  const found: ChannelSummary[] = [];
  for (let start = 0; start < channelIds.length; start += 50) {
    const data = await apiGet<ChannelListResponse>(
      "/channels",
      {
        part: "snippet,statistics",
        id: channelIds.slice(start, start + 50).join(","),
        maxResults: "50",
      },
      token,
    );
    found.push(...(data.items ?? []).map(toSummary));
  }
  return found;
}
