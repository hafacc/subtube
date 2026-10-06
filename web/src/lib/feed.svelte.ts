import { getValidToken, silentRefresh, withToken } from "./auth";
import { nextUnwatched } from "./autoplay";
import { chipKeptChannels, kindFor, passingItems } from "./channel-chips";
import { channelInfo } from "./channel-info";
import { chipFiltered, chipRow, startMarks, takePendingStart } from "./chips";
import { feedItemId } from "./feed-item";
import { newShuffleSeed, sortFeed } from "./feed-order";
import { compileFilter, videoPassesFilter } from "./filters";
import { loadFraction } from "./load-progress";
import { platform } from "./platform";
import { isWatchedEntry, progressFraction, resumePosition } from "./progress";
import type { Router } from "./router.svelte";
import type { Session } from "./session.svelte";
import { readSettings, type Settings } from "./settings";
import { defaultFilter } from "./sync-merge";
import { ProfileDeletedError, type SyncStore } from "./sync-store";
import type {
  Channel,
  ChannelFilter,
  ChannelInfo,
  ContentMode,
  FeedItem,
} from "./types";
import {
  autoplayAdvances,
  emptiedBySelection,
  modeFiltered,
  type WatchedMode,
} from "./watched-mode";
import {
  DAILY_LIMIT_MESSAGE,
  DailyLimitError,
  fetchPlaylists,
  fetchSubscriptions,
  fetchUploads,
  InsufficientScopeError,
  markShorts,
  TokenExpiredError,
} from "./youtube";

/** 50 is the most one playlistItems page returns, still for 1 quota unit. */
export const UPLOADS_PER_CHANNEL = 50;
const FETCH_CONCURRENCY = 6;
/** Returning to the tab after this long away loads the feed again. */
export const STALE_AFTER_MS = 15 * 60_000;

/** Run `worker` over `items`, at most `limit` at a time, keeping their order. */
export async function mapWithConcurrency<Item, Result>(
  items: readonly Item[],
  limit: number,
  worker: (item: Item) => Promise<Result>,
): Promise<Result[]> {
  const results = new Array<Result>(items.length);
  let cursor = 0;
  async function run(): Promise<void> {
    while (cursor < items.length) {
      const index = cursor++;
      results[index] = await worker(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, run));
  return results;
}

/** A feed item's length in seconds; 0 for a playlist or a video of unknown length. */
function durationOf(item: FeedItem): number {
  return item.kind === "video" ? (item.durationSeconds ?? 0) : 0;
}

/** Swap one channel's entries of one kind for freshly fetched ones. */
function replaceChannelItems(
  items: FeedItem[],
  channelId: string,
  mode: ContentMode,
  fresh: FeedItem[],
): FeedItem[] {
  const kind = kindFor(mode);
  return [
    ...items.filter(
      (item) => item.channelId !== channelId || item.kind !== kind,
    ),
    ...fresh,
  ];
}

type ShortsProbe = (videoId: string) => Promise<boolean | null>;

/** Whether a filter needs to know which videos are Shorts: uploads, with Shorts hidden or the only ones shown. */
export function needsShorts(filter: ChannelFilter): boolean {
  return (
    filter.contentMode !== "playlists" &&
    (filter.shortsFilter ?? "all") !== "all"
  );
}

/** One channel's fetched items, with the mode they were fetched in. */
export interface ChannelItems {
  /** uploads or playlists */
  mode: ContentMode;
  /** whether the channel's Shorts list was read for them, so `isShort` is set wherever it can be */
  shorts: boolean;
  /** the items */
  items: FeedItem[];
}

/**
 * A channel's newest items: uploads or playlists, as its filter says. The
 * Shorts list is read only when the filter {@link needsShorts}.
 */
export async function fetchChannelItems(
  channel: Channel,
  token: string,
  probe?: ShortsProbe,
): Promise<ChannelItems> {
  if (channel.filter.contentMode === "playlists") {
    return {
      mode: "playlists",
      shorts: false,
      items: await fetchPlaylists(channel.channelId, channel.title, token),
    };
  } else {
    const shorts = needsShorts(channel.filter);
    return {
      mode: "videos",
      shorts,
      items: await fetchUploads(
        channel.channelId,
        channel.title,
        token,
        UPLOADS_PER_CHANNEL,
        probe,
        shorts,
      ),
    };
  }
}

/** Uploads fetched without their channel's Shorts list, now with it: one request, or none when no video could be a Short. */
export async function addShortsMarks(
  channelId: string,
  fetched: ChannelItems,
  token: string,
  probe?: ShortsProbe,
): Promise<ChannelItems> {
  const videos = fetched.items.filter((item) => item.kind === "video");
  return {
    mode: "videos",
    shorts: true,
    items: await markShorts(
      videos,
      channelId,
      token,
      UPLOADS_PER_CHANNEL,
      probe,
    ),
  };
}

/** Whether fetched items are what a filter needs: its mode, with Shorts marks when it filters on them. */
export function covers(fetched: ChannelItems, filter: ChannelFilter): boolean {
  return (
    fetched.mode === (filter.contentMode ?? "videos") &&
    (fetched.shorts || !needsShorts(filter))
  );
}

/** A channel's newest items, fetched with a fresh token and this browser's Shorts probe. */
async function fetchItemsWithToken(channel: Channel): Promise<ChannelItems> {
  const probe = (await platform())?.probeShort;
  return withToken((token) => fetchChannelItems(channel, token, probe));
}

/** The Shorts marks a channel's fetched uploads lack, fetched with a fresh token and this browser's Shorts probe. */
async function addShortsMarksWithToken(
  channel: Channel,
  fetched: ChannelItems,
): Promise<ChannelItems> {
  const probe = (await platform())?.probeShort;
  return withToken((token) =>
    addShortsMarks(channel.channelId, fetched, token, probe),
  );
}

/**
 * What a channel's filter needs, from what is already fetched for it where
 * that helps: nothing more, only the Shorts list, or everything.
 */
export async function completeItems(
  channel: Channel,
  have: ChannelItems | null,
  fetchAll: (channel: Channel) => Promise<ChannelItems>,
  addShorts: (channel: Channel, fetched: ChannelItems) => Promise<ChannelItems>,
): Promise<ChannelItems> {
  if (have && covers(have, channel.filter)) {
    return have;
  } else if (have && covers({ ...have, shorts: true }, channel.filter)) {
    return addShorts(channel, have);
  } else {
    return fetchAll(channel);
  }
}

/** A channel's fetch in a {@link Prefetch}, waiting its turn. */
interface PrefetchJob {
  // the newest filter asked for; read when the job starts
  channel: Channel;
  // what an earlier job fetched or is fetching for the channel, to build on
  before: Promise<ChannelItems | null> | null;
  settle: (result: ChannelItems | null | Promise<ChannelItems | null>) => void;
}

/**
 * Channels' items fetched in the background before the feed opens, so setup
 * can fetch the channels left on while its later screens show.
 *
 * {@link fetchOnly} names the channels to have, with the filters they will
 * be shown under; at most `FETCH_CONCURRENCY` are fetched at a time. A
 * channel whose fetch fails has no items here and is left to the feed. Once
 * YouTube's daily limit refuses a request, nothing more is requested.
 */
export class Prefetch {
  private readonly fetchAll: (channel: Channel) => Promise<ChannelItems>;
  private readonly addShorts: (
    channel: Channel,
    fetched: ChannelItems,
  ) => Promise<ChannelItems>;
  // every channel waiting, being fetched or fetched, wanted or not
  private readonly entries = new Map<
    string,
    {
      channel: Channel;
      result: Promise<ChannelItems | null>;
      waiting: PrefetchJob | null;
    }
  >();
  private wanted: ReadonlySet<string> = new Set();
  private waiting: PrefetchJob[] = [];
  private running = 0;
  private refused = false;

  /**
   * A prefetch that fetches a channel's items with `fetchAll`, and the
   * Shorts marks fetched uploads lack with `addShorts`; it starts on nothing
   * yet.
   */
  constructor(
    fetchAll: (channel: Channel) => Promise<ChannelItems> = fetchItemsWithToken,
    addShorts: (
      channel: Channel,
      fetched: ChannelItems,
    ) => Promise<ChannelItems> = addShortsMarksWithToken,
  ) {
    this.fetchAll = fetchAll;
    this.addShorts = addShorts;
  }

  /**
   * Have exactly `channels`: what was fetched or is being fetched for them
   * is kept, and added to when a channel's filter now needs more (the Shorts
   * list, or its other content mode); the others among them are queued; and
   * a channel not among them is taken out of the queue and has no items here.
   */
  fetchOnly(channels: readonly Channel[]): void {
    this.wanted = new Set(channels.map(({ channelId }) => channelId));
    for (const job of this.waiting) {
      const { channelId } = job.channel;
      const entry = this.entries.get(channelId);
      if (!this.wanted.has(channelId) && entry) {
        if (job.before) {
          entry.result = job.before;
          entry.waiting = null;
        } else {
          this.entries.delete(channelId);
        }
        job.settle(job.before);
      }
    }
    this.waiting = this.waiting.filter(({ channel }) =>
      this.wanted.has(channel.channelId),
    );
    for (const channel of channels) {
      const entry = this.entries.get(channel.channelId);
      if (entry?.waiting) {
        entry.waiting.channel = channel;
        entry.channel = channel;
      } else if (
        !entry ||
        (entry.channel.filter.contentMode ?? "videos") !==
          (channel.filter.contentMode ?? "videos") ||
        (needsShorts(channel.filter) && !needsShorts(entry.channel.filter))
      ) {
        this.enqueue(channel, entry?.result ?? null);
      }
    }
    this.startWaiting();
  }

  private enqueue(
    channel: Channel,
    before: Promise<ChannelItems | null> | null,
  ): void {
    let settle: PrefetchJob["settle"] = () => undefined;
    const result = new Promise<ChannelItems | null>((resolve) => {
      settle = resolve;
    });
    const job: PrefetchJob = { channel, before, settle };
    this.entries.set(channel.channelId, { channel, result, waiting: job });
    this.waiting.push(job);
  }

  private startWaiting(): void {
    while (this.running < FETCH_CONCURRENCY) {
      const job = this.waiting.shift();
      if (job === undefined) {
        break;
      }
      const entry = this.entries.get(job.channel.channelId);
      if (entry) {
        entry.waiting = null;
      }
      this.running += 1;
      void this.run(job).then((result) => {
        job.settle(result);
        this.running -= 1;
        this.startWaiting();
      });
    }
  }

  private async run(job: PrefetchJob): Promise<ChannelItems | null> {
    // no await without something to wait for, so a first fetch starts at once
    const have = job.before ? await job.before : null;
    if (this.refused) {
      return have;
    }
    try {
      return await completeItems(
        job.channel,
        have,
        this.fetchAll,
        this.addShorts,
      );
    } catch (caught) {
      if (caught instanceof DailyLimitError) {
        this.refused = true;
      }
      console.error(caught);
      return have;
    }
  }

  /** What was fetched for a channel, once its fetches end; null when there is nothing. */
  async items(channelId: string): Promise<ChannelItems | null> {
    if (this.wanted.has(channelId)) {
      return (await this.entries.get(channelId)?.result) ?? null;
    } else {
      return null;
    }
  }
}

let handedOff: { accountId: string; prefetch: Prefetch } | null = null;

/**
 * Give the account's next feed load what setup fetched or is still fetching,
 * so that load doesn't fetch those channels again.
 */
export function handOffPrefetched(accountId: string, prefetch: Prefetch): void {
  handedOff = { accountId, prefetch };
}

function takePrefetched(accountId: string): Prefetch | null {
  const taken = handedOff?.accountId === accountId ? handedOff.prefetch : null;
  handedOff = null;
  return taken;
}

/** What fetching a load's channels came to. */
export interface FetchedChannels {
  /** each fetched channel's items, with the mode they were fetched in */
  fetched: Map<string, ChannelItems>;
  /** channels that weren't fetched without ending the load; any makes it partial */
  failed: Set<string>;
  /** whether YouTube's daily limit refused a request, after which none was sent */
  dailyLimit: boolean;
}

/**
 * Fetch each channel with `fetchOne`, `FETCH_CONCURRENCY` at a time. A
 * channel whose fetch fails is in `failed`; once one is refused for YouTube's
 * daily limit the rest aren't asked for and are in `failed` too. A refused
 * token or a missing permission ends the whole fetch. `onFinished` hears how
 * many channels are finished (fetched, failed or skipped) after each one.
 */
export async function fetchChannels(
  channels: readonly Channel[],
  fetchOne: (channel: Channel) => Promise<ChannelItems>,
  onFinished: (finished: number) => void = () => undefined,
): Promise<FetchedChannels> {
  const fetched = new Map<string, ChannelItems>();
  const failed = new Set<string>();
  let dailyLimit = false;
  let finished = 0;
  await mapWithConcurrency(channels, FETCH_CONCURRENCY, async (channel) => {
    try {
      if (dailyLimit) {
        failed.add(channel.channelId);
      } else {
        fetched.set(channel.channelId, await fetchOne(channel));
      }
    } catch (caught) {
      if (
        caught instanceof TokenExpiredError ||
        caught instanceof InsufficientScopeError
      ) {
        throw caught;
      }
      dailyLimit ||= caught instanceof DailyLimitError;
      failed.add(channel.channelId);
    }
    finished += 1;
    onFinished(finished);
  });
  return { fetched, failed, dailyLimit };
}

/** A load's result, before it is applied. */
interface FeedData extends FetchedChannels {
  subscribed: ChannelInfo[];
  followedInfo: Map<string, ChannelInfo> | undefined;
}

/**
 * The feed: loading, filtering, ordering and watched marks. The feed is every
 * item that passes the filters and the chips, in the chosen order. A load fetches in the background
 * and replaces the items in one go when it finishes; a filter edit only
 * re-filters, fetching just a channel whose items are missing. A video is
 * watched once it has been played to its end (`progress.ts`); one that
 * finishes here stays on screen until the next load, so nothing moves.
 */
export class FeedController {
  /** the channels with their filters, as of the last load plus edits since */
  channels: Map<string, Channel> = $state.raw(new Map());
  /** ids of loaded items that are watched */
  watched: Set<string> = $state.raw(new Set());
  /** how full each loaded video's progress bar is, from 0 to 1; videos with no bar are absent */
  bars: Map<string, number> = $state.raw(new Map());
  /** every loaded item */
  items: FeedItem[] = $state.raw([]);
  /** whether a load is running */
  loading = $state(false);
  /** how far the running load has come, from 0 to 1 (`loadFraction`); null when none runs */
  loadProgress: number | null = $state(null);
  /** how many loads have been shown */
  loadCount = $state(0);
  /** why the last load failed */
  error: string | null = $state(null);
  /** a load that only partly worked */
  notice: string | null = $state(null);
  /** which of watched and unwatched items the page lists; kept for this visit only */
  watchedMode: WatchedMode = $state("unwatched");
  /** the synced settings, as of the last load plus changes made here since */
  settings: Settings = $state.raw(readSettings({}));
  /** a channel page's items, for a channel the feed doesn't load */
  channelItems: (ChannelItems & { id: string }) | null = $state.raw(null);
  /** whether a channel page is loading */
  channelLoading = $state(false);
  /** why a channel page failed to load */
  channelError: string | null = $state(null);

  // became watched or unwatched here since the last full load, filter edit or
  // chip change: these cards stay on screen whatever the watched mode lists
  private staying: Set<string> = $state.raw(new Set());
  // channels waiting for a fetch of their own, and how many are being fetched
  private channelQueue = new Map<string, Channel>();
  private channelFetches = 0;
  // the content modes each channel's items have been fetched in
  private fetchedModes = new Map<string, Set<ContentMode | "shorts">>();
  private loadInFlight = false;
  // fixes the random order until the next full load
  private shuffleSeed = $state(newShuffleSeed());
  // the time the time chips count back from
  private chipClock = $state(Date.now());
  private lastLoadedAt = 0;
  private readonly accountId: string;
  private readonly session: Session;
  private readonly store: SyncStore;
  private readonly router: Router;

  /** The feed of the session's account; call {@link start} once mounted. */
  constructor(session: Session, store: SyncStore, router: Router) {
    this.session = session;
    this.store = store;
    this.router = router;
    this.accountId = session.account?.channelId ?? "";
    this.settings = readSettings(store.settings());
  }

  /** The channel page on screen, or null for the feed. */
  get channelView(): string | null {
    return this.router.route.channel;
  }

  /** The channel shown on the current channel page. */
  get channelEntry(): Channel | undefined {
    const channelId = this.channelView;
    return channelId ? this.channels.get(channelId) : undefined;
  }

  /** Whether the channel page needs its own fetch: the feed doesn't load that channel. */
  get onDemandChannel(): boolean {
    return (
      this.channelView !== null && this.channelEntry?.filter.enabled !== true
    );
  }

  /** Everything the current view could show, watched or not, by id. */
  passing: Map<string, FeedItem> = $derived.by(() => {
    const compiled = new Map(
      Array.from(this.channels.values(), (channel) => [
        channel.channelId,
        compileFilter(channel.filter),
      ]),
    );
    const channelView = this.channelView;
    const mode = this.channelEntry?.filter.contentMode ?? "videos";
    const source = this.onDemandChannel
      ? this.channelItems?.id === channelView && this.channelItems.mode === mode
        ? this.channelItems.items
        : []
      : this.items;
    const shown = new Map<string, FeedItem>();
    for (const item of source) {
      if (channelView && item.channelId !== channelView) {
        continue;
      }
      const filter = compiled.get(item.channelId);
      // the feed shows enabled channels; a channel page shows its channel regardless
      if (!channelView && !filter?.enabled) {
        continue;
      }
      const channelMode = this.channels.get(item.channelId)?.filter.contentMode;
      if (filter && item.kind !== kindFor(channelMode)) {
        continue;
      }
      if (filter && !videoPassesFilter(item, filter)) {
        continue;
      }
      shown.set(feedItemId(item), item);
    }
    return shown;
  });

  /** Every on channel's fetched items that pass its filter, watched or not. */
  private listed: FeedItem[] = $derived(
    passingItems(this.channels.values(), this.items),
  );

  /** Each on channel's unwatched items that pass its filter, counted; channels with none are absent. */
  unwatchedByChannel: Map<string, number> = $derived.by(() => {
    const counts = new Map<string, number>();
    for (const item of this.listed) {
      if (!this.watched.has(feedItemId(item))) {
        counts.set(item.channelId, (counts.get(item.channelId) ?? 0) + 1);
      }
    }
    return counts;
  });

  /** The channel list's topic chips, as category ids in row order. */
  channelTopicChips: string[] = $derived(
    chipRow(this.listed, this.settings.channelTopicChips),
  );

  /** The channels the channel list's chips keep, by id; null while they keep every channel. */
  chipChannels: Set<string> | null = $derived(
    chipKeptChannels(
      this.listed,
      this.settings.channelTimeChip,
      this.settings.channelTopicChips,
      this.chipClock,
    ),
  );

  /** Unwatched items the whole feed would show, whatever page is open or chip selected. */
  unwatchedCount: number = $derived(
    Array.from(this.unwatchedByChannel.values()).reduce(
      (total, count) => total + count,
      0,
    ),
  );

  /** The current view's items before the chips: what the chip row counts. */
  private beforeChips: FeedItem[] = $derived.by(() => {
    return modeFiltered(
      Array.from(this.passing.values()),
      this.watchedMode,
      this.watched,
      this.staying,
    );
  });

  /** The topic chips to show, as category ids in row order. */
  topicChips: string[] = $derived(
    chipRow(this.beforeChips, this.settings.topicChips),
  );

  /** The items on screen, in the chosen order. */
  feed: FeedItem[] = $derived(
    sortFeed(
      chipFiltered(
        this.beforeChips,
        this.settings.timeChip,
        this.settings.topicChips,
        this.chipClock,
      ),
      this.settings.feedSort,
      this.shuffleSeed,
    ),
  );

  /** Change a synced setting, here at once and on every device through Drive. */
  setSetting<Name extends keyof Settings>(
    name: Name,
    value: Settings[Name],
  ): void {
    this.settings = { ...this.settings, [name]: value };
    this.chipClock = Date.now();
    if (name === "timeChip" || name === "topicChips") {
      this.dropStaying();
    }
    this.store.setSetting(name, value);
  }

  /** Whether an empty page is empty because of the chips, not because nothing is left to watch. */
  get emptiedBySelection(): boolean {
    return emptiedBySelection(
      this.watchedMode,
      this.settings.timeChip,
      this.settings.topicChips,
    );
  }

  /** List unwatched items, watched ones, or both. */
  setWatchedMode(mode: WatchedMode): void {
    this.watchedMode = mode;
    this.dropStaying();
  }

  /** What auto-play plays after `endedId` on this page; null when it doesn't move on. */
  autoplayNext(endedId: string): FeedItem | null {
    if (this.settings.autoplay && autoplayAdvances(this.watchedMode)) {
      return nextUnwatched(this.feed, endedId, this.watched);
    } else {
      return null;
    }
  }

  /** Select a topic chip by its category id, or deselect it. */
  toggleTopicChip(categoryId: string): void {
    this.toggleTopicIn("topicChips", categoryId);
  }

  /** Select one of the channel list's topic chips by its category id, or deselect it. */
  toggleChannelTopicChip(categoryId: string): void {
    this.toggleTopicIn("channelTopicChips", categoryId);
  }

  private toggleTopicIn(
    name: "topicChips" | "channelTopicChips",
    categoryId: string,
  ): void {
    const selected = this.settings[name];
    this.setSetting(
      name,
      selected.includes(categoryId)
        ? selected.filter((other) => other !== categoryId)
        : [...selected, categoryId],
    );
  }

  /** Everything fetched for a channel, whatever its filter keeps. */
  channelFetched(channelId: string): FeedItem[] {
    const source =
      this.channelItems?.id === channelId && !this.channels.has(channelId)
        ? this.channelItems.items
        : this.items;
    return source.filter((item) => item.channelId === channelId);
  }

  /** Upload as the tab is hidden, and reload on returning after a while away. */
  start(): () => void {
    const onVisible = () => {
      if (document.visibilityState === "hidden") {
        this.store.flush();
      } else if (
        this.session.ready &&
        Date.now() - this.lastLoadedAt > STALE_AFTER_MS
      ) {
        void this.load();
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }

  /** Let the cards that changed sides since the last time drop out of a mode that doesn't list them. */
  private dropStaying(): void {
    if (this.staying.size > 0) {
      this.staying = new Set();
    }
  }

  private markFetched(channelId: string, { mode, shorts }: ChannelItems): void {
    const marks = this.fetchedModes.get(channelId) ?? new Set();
    marks.add(mode);
    if (mode === "videos" && shorts) {
      marks.add("shorts");
    } else if (mode === "videos") {
      marks.delete("shorts");
    }
    this.fetchedModes.set(channelId, marks);
  }

  /** The uploads the feed holds for a channel, as fetched; null when it has none. */
  private fetchedUploads(channelId: string): ChannelItems | null {
    const marks = this.fetchedModes.get(channelId);
    if (marks?.has("videos")) {
      return {
        mode: "videos",
        shorts: marks.has("shorts"),
        items: this.items.filter(
          (item) => item.channelId === channelId && item.kind === "video",
        ),
      };
    } else {
      return null;
    }
  }

  /*
   * Apply the synced watched state to one batch of items. Marks made here are in
   * the store already, so a batch can't revert one made while it loaded.
   */
  private applyWatchedBatch(batch: FeedItem[]): void {
    const watched = new Set(this.watched);
    const bars = new Map(this.bars);
    for (const item of batch) {
      this.readEntry(feedItemId(item), durationOf(item), watched, bars);
    }
    this.watched = watched;
    this.bars = bars;
  }

  /** Put what the store holds for one item into `watched` and `bars`; says whether it is watched. */
  private readEntry(
    id: string,
    durationSeconds: number,
    watched: Set<string>,
    bars: Map<string, number>,
  ): boolean {
    const entry = this.store.watchedEntry(id);
    const isWatched = isWatchedEntry(entry, durationSeconds);
    const fraction = progressFraction(entry, durationSeconds);
    if (isWatched) {
      watched.add(id);
    } else {
      watched.delete(id);
    }
    if (fraction === null) {
      bars.delete(id);
    } else {
      bars.set(id, fraction);
    }
    return isWatched;
  }

  /** Show an item's entry as just saved; one that became watched stays on screen. */
  private entryChanged(id: string, durationSeconds: number): void {
    const wasWatched = this.watched.has(id);
    const watched = new Set(this.watched);
    const bars = new Map(this.bars);
    const isWatched = this.readEntry(id, durationSeconds, watched, bars);
    this.bars = bars;
    if (isWatched !== wasWatched) {
      this.watched = watched;
      this.staying = new Set(this.staying).add(id);
    }
  }

  private async fetchEverything(
    token: string,
    prefetched: Prefetch | null,
  ): Promise<FeedData> {
    const [subscribed, current] = await Promise.all([
      fetchSubscriptions(token),
      platform(),
      this.store.load(),
    ]);
    const followed = this.store
      .followedIds()
      .filter(
        (channelId) =>
          !subscribed.some((channel) => channel.channelId === channelId),
      );
    const followedInfo =
      followed.length > 0 ? await channelInfo(followed, token) : undefined;
    const enabled = Array.from(
      this.store.channels(subscribed, followedInfo).values(),
    ).filter((channel) => channel.filter.enabled);
    const probe = current?.probeShort;
    const channels = await fetchChannels(
      enabled,
      async (channel) =>
        completeItems(
          channel,
          (await prefetched?.items(channel.channelId)) ?? null,
          (wanted) => fetchChannelItems(wanted, token, probe),
          (wanted, have) =>
            addShortsMarks(wanted.channelId, have, token, probe),
        ),
      (finished) => this.advanceLoad(loadFraction(finished, enabled.length)),
    );
    return { subscribed, followedInfo, ...channels };
  }

  // never backwards: a load that starts over after renewing its token keeps its place
  private advanceLoad(fraction: number): void {
    this.loadProgress = Math.max(this.loadProgress ?? 0, fraction);
  }

  /** Show a finished load: its channels and items replace the old ones at once. */
  private applyLoad(data: FeedData): void {
    // read the filters again, so edits made during the load stay
    const channels = this.store.channels(data.subscribed, data.followedInfo);
    const fresh = Array.from(data.fetched.values()).flatMap(
      ({ items }) => items,
    );
    // a channel the load didn't fetch keeps what it had
    this.items = [
      ...this.items.filter(
        (item) =>
          channels.has(item.channelId) && !data.fetched.has(item.channelId),
      ),
      ...fresh,
    ];
    for (const channelId of this.fetchedModes.keys()) {
      if (!channels.has(channelId)) {
        this.fetchedModes.delete(channelId);
      }
    }
    for (const [channelId, fetched] of data.fetched) {
      this.fetchedModes.delete(channelId);
      this.markFetched(channelId, fetched);
    }
    this.channels = channels;
    this.settings = readSettings(this.store.settings());
    this.shuffleSeed = newShuffleSeed();
    this.chipClock = Date.now();
    this.markBeforeStart(fresh);
    this.store.noteLoaded(fresh.map(feedItemId));
    this.applyWatchedBatch(fresh);
    for (const channelId of data.failed) {
      // so an edit to it fetches it again
      this.fetchedModes.delete(channelId);
    }
    this.dropStaying();
    this.loadCount += 1;
  }

  /** After setup, mark what was fetched from before its starting point watched, as one save. */
  private markBeforeStart(fetched: FeedItem[]): void {
    const ids = startMarks(
      fetched,
      takePendingStart(this.accountId),
      Date.now(),
    ).filter((id) => this.store.watchedEntry(id)?.watched !== true);
    if (ids.length > 0) {
      this.store.setWatchedAll(ids, true);
    }
  }

  /** Load subscriptions, sync files and every enabled channel's items. */
  async load(): Promise<void> {
    if (this.loadInFlight) {
      return;
    }
    this.loadInFlight = true;
    this.loading = true;
    this.loadProgress = loadFraction(0, null);
    this.error = null;
    try {
      let token: string;
      try {
        token = await getValidToken();
      } catch {
        this.session.tokenLost();
        return;
      }
      const prefetched = takePrefetched(this.accountId);
      let data: FeedData;
      try {
        data = await this.fetchEverything(token, prefetched);
      } catch (caught) {
        if (!(caught instanceof TokenExpiredError)) {
          throw caught;
        }
        // the token died mid-load: renew silently and retry once
        data = await this.fetchEverything(await silentRefresh(), prefetched);
      }
      this.applyLoad(data);
      this.notice = data.dailyLimit
        ? DAILY_LIMIT_MESSAGE
        : data.failed.size > 0
          ? "Some channels couldn't be loaded; showing partial results."
          : null;
    } catch (caught) {
      this.handleError(caught);
    } finally {
      this.loading = false;
      this.loadProgress = null;
      this.loadInFlight = false;
      this.lastLoadedAt = Date.now();
      this.pumpChannels();
    }
  }

  private handleError(caught: unknown): void {
    if (caught instanceof ProfileDeletedError) {
      // the session is already on its way back to setup
    } else if (caught instanceof TokenExpiredError) {
      this.session.tokenLost();
    } else if (caught instanceof InsufficientScopeError) {
      this.session.tokenLost();
      this.error = caught.message;
    } else {
      this.error = (caught as Error).message;
    }
  }

  /** The Refresh click: load everything again, and the open page of a channel that is off. */
  refresh(): void {
    void this.load();
    if (this.onDemandChannel) {
      this.channelItems = null;
      void this.ensureChannelItems();
    }
  }

  /** Fetch a channel page's items when the feed doesn't load that channel. */
  async ensureChannelItems(): Promise<void> {
    const channelId = this.channelView;
    if (!channelId || !this.onDemandChannel) {
      return;
    }
    const channel: Channel = this.channelEntry ?? {
      channelId,
      title: channelId,
      thumbnail: "",
      filter: defaultFilter(),
    };
    const have = this.channelItems?.id === channelId ? this.channelItems : null;
    if (have && covers(have, channel.filter)) {
      return;
    }
    this.channelLoading = true;
    this.channelError = null;
    try {
      const fetched = await completeItems(
        channel,
        have,
        fetchItemsWithToken,
        addShortsMarksWithToken,
      );
      if (this.channelView === channelId) {
        this.channelItems = { id: channelId, ...fetched };
        if (this.channels.has(channelId)) {
          // kept, so turning the channel on doesn't fetch it again
          this.addChannelItems(
            channelId,
            fetched.mode,
            fetched.items,
            fetched.shorts,
          );
        } else {
          this.applyWatchedBatch(fetched.items);
        }
      }
    } catch (caught) {
      if (this.channelView === channelId) {
        this.channelError = (caught as Error).message;
      }
    } finally {
      this.channelLoading = false;
    }
  }

  /**
   * Save a channel's filter; it re-filters what is loaded at once and syncs
   * through Drive. Only a channel whose items are missing is fetched.
   */
  updateFilter(channelId: string, filter: ChannelFilter): void {
    const channel = this.channels.get(channelId);
    if (channel) {
      this.channels = new Map(this.channels).set(channelId, {
        ...channel,
        filter,
      });
    }
    this.store.setFilter(channelId, filter);
    this.dropStaying();
    if (channel && filter.enabled && this.isMissing(channelId, filter)) {
      this.channelQueue.set(channelId, { ...channel, filter });
      this.pumpChannels();
    }
  }

  /*
   * Fetch the waiting channels, FETCH_CONCURRENCY at a time. While a full load
   * runs they wait for it to end: it may fetch them itself.
   */
  private pumpChannels(): void {
    while (
      !this.loadInFlight &&
      this.channelFetches < FETCH_CONCURRENCY &&
      this.channelQueue.size > 0
    ) {
      const [channelId] = this.channelQueue.keys();
      this.channelQueue.delete(channelId);
      const channel = this.channels.get(channelId);
      if (
        channel?.filter.enabled &&
        this.isMissing(channelId, channel.filter)
      ) {
        this.channelFetches += 1;
        void this.loadChannel(channel).finally(() => {
          this.channelFetches -= 1;
          this.pumpChannels();
        });
      }
    }
  }

  /**
   * Add items fetched elsewhere, e.g. for a preview, so they needn't be
   * fetched again; `shorts` says whether the channel's Shorts list was read
   * for them.
   */
  addChannelItems(
    channelId: string,
    mode: ContentMode,
    items: FeedItem[],
    shorts = false,
  ): void {
    this.items = replaceChannelItems(this.items, channelId, mode, items);
    this.markFetched(channelId, { mode, shorts, items });
    this.applyWatchedBatch(items);
  }

  /** Whether a filter needs something not fetched for its channel: its mode's items, or the Shorts list. */
  private isMissing(channelId: string, filter: ChannelFilter): boolean {
    const marks = this.fetchedModes.get(channelId);
    return (
      !marks?.has(filter.contentMode ?? "videos") ||
      (needsShorts(filter) && !marks.has("shorts"))
    );
  }

  /** Fetch what a channel's filter lacks into the feed, e.g. after it was switched on or began to filter on Shorts. */
  private async loadChannel(channel: Channel): Promise<void> {
    try {
      const fetched = await completeItems(
        channel,
        this.fetchedUploads(channel.channelId),
        fetchItemsWithToken,
        addShortsMarksWithToken,
      );
      this.addChannelItems(
        channel.channelId,
        fetched.mode,
        fetched.items,
        fetched.shorts,
      );
    } catch (caught) {
      if (caught instanceof DailyLimitError) {
        // every waiting channel would be refused too
        this.channelQueue.clear();
      }
      this.handleError(caught);
    }
  }

  /** The length of a loaded video, in seconds; 0 when it isn't loaded or has none. */
  private lengthOf(id: string): number {
    const item = this.findItem(id);
    return item === undefined ? 0 : durationOf(item);
  }

  /** Mark a video or playlist watched, or unmark it, which forgets a video's position. */
  setWatched(id: string, isWatched: boolean): void {
    this.store.setWatched(id, isWatched);
    this.entryChanged(id, this.lengthOf(id));
  }

  /**
   * Save how far a video has been played: `position` of `playerDuration`
   * seconds, and whether the player reported the end. It is always kept on
   * this device; `upload` says whether Drive gets it after the usual pause
   * ("soon"), at once ("now"), or only with the next upload ("later").
   */
  recordProgress(
    id: string,
    position: number,
    playerDuration: number,
    ended: boolean,
    upload: "later" | "soon" | "now",
  ): void {
    this.store.setProgress(
      id,
      Math.max(0, Math.floor(position)),
      ended,
      upload !== "later",
    );
    if (upload === "now") {
      this.store.flush();
    }
    this.entryChanged(id, this.lengthOf(id) || playerDuration);
  }

  /** Where a video starts when opened, in seconds. */
  resumeAt(id: string): number {
    return resumePosition(this.store.watchedEntry(id), this.lengthOf(id));
  }

  /** Every loaded item with this id, wherever it was loaded. */
  findItem(id: string): FeedItem | undefined {
    const matches = (item: FeedItem) => feedItemId(item) === id;
    return this.items.find(matches) ?? this.channelItems?.items.find(matches);
  }
}
