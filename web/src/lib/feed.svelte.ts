import { getValidToken, silentRefresh, withToken } from "./auth";
import { channelInfo } from "./channel-info";
import { feedItemId } from "./feed-item";
import { byNewest } from "./feed-order";
import { compileFilter, videoPassesFilter } from "./filters";
import { type MarkAll, markAllChoice } from "./mark-all";
import { platform } from "./platform";
import type { Router } from "./router.svelte";
import type { Session } from "./session.svelte";
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
  fetchPlaylists,
  fetchSubscriptions,
  fetchUploads,
  InsufficientScopeError,
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

/** The kind of feed entry a content mode shows. */
function kindFor(mode: ContentMode | undefined): FeedItem["kind"] {
  return mode === "playlists" ? "playlist" : "video";
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

/** A channel's newest items: uploads or playlists, as its filter says. */
export async function fetchChannelItems(
  channel: Channel,
  token: string,
  probe?: (videoId: string) => Promise<boolean | null>,
): Promise<FeedItem[]> {
  if (channel.filter.contentMode === "playlists") {
    return fetchPlaylists(channel.channelId, channel.title, token);
  } else {
    return fetchUploads(
      channel.channelId,
      channel.title,
      token,
      UPLOADS_PER_CHANNEL,
      probe,
    );
  }
}

/** Items fetched before the feed opened, by channel, with the mode they were fetched in. */
export type Prefetched = Map<string, { mode: ContentMode; items: FeedItem[] }>;

let handedOff: { accountId: string; fetched: Prefetched } | null = null;

/**
 * Give the account's next feed load items setup already fetched, so that load
 * doesn't fetch those channels again.
 */
export function handOffPrefetched(
  accountId: string,
  fetched: Prefetched,
): void {
  handedOff = { accountId, fetched };
}

function takePrefetched(accountId: string): Prefetched {
  const taken = handedOff?.accountId === accountId ? handedOff.fetched : null;
  handedOff = null;
  return taken ?? new Map();
}

/** A load's result, before it is applied. */
interface FeedData {
  subscribed: ChannelInfo[];
  followedInfo: Map<string, ChannelInfo> | undefined;
  /** each fetched channel's items, with the mode they were fetched in */
  fetched: Prefetched;
  /** channels whose fetch failed without ending the load; any makes it partial */
  failed: Set<string>;
}

/**
 * The feed: loading, filtering, ordering and watched marks. The feed is every
 * item that passes the filters, newest first. A load fetches in the background
 * and replaces the items in one go when it finishes; a filter edit only
 * re-filters, fetching just a channel whose items are missing. Cards marked
 * watched stay until the next load or change of view, so nothing moves.
 */
export class FeedController {
  /** the channels with their filters, as of the last load plus edits since */
  channels: Map<string, Channel> = $state.raw(new Map());
  /** ids of loaded items that are marked watched */
  watched: Set<string> = $state.raw(new Set());
  /** every loaded item */
  items: FeedItem[] = $state.raw([]);
  /** whether a load is running */
  loading = $state(false);
  /** why the last load failed */
  error: string | null = $state(null);
  /** a load that only partly worked */
  notice: string | null = $state(null);
  /** whether watched cards are shown */
  showWatched = $state(false);
  /** a channel page's items, for a channel the feed doesn't load */
  channelItems: {
    id: string;
    mode: ContentMode;
    items: FeedItem[];
  } | null = $state.raw(null);
  /** whether a channel page is loading */
  channelLoading = $state(false);
  /** why a channel page failed to load */
  channelError: string | null = $state(null);

  // marked watched here since the last full load, watched toggle or filter edit:
  // these cards stay on screen, dimmed, while watched cards are hidden
  private justWatched: Set<string> = $state.raw(new Set());
  // channels waiting for a fetch of their own, and how many are being fetched
  private channelQueue = new Map<string, Channel>();
  private channelFetches = 0;
  // the content modes each channel's items have been fetched in
  private fetchedModes = new Map<string, Set<ContentMode>>();
  private loadInFlight = false;
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

  /** Unwatched items the whole feed would show, whatever page is open. */
  unwatchedCount: number = $derived.by(() => {
    const enabled = new Map(
      Array.from(this.channels.values())
        .filter((channel) => channel.filter.enabled)
        .map((channel) => [
          channel.channelId,
          {
            kind: kindFor(channel.filter.contentMode),
            filter: compileFilter(channel.filter),
          },
        ]),
    );
    return this.items.filter((item) => {
      const entry = enabled.get(item.channelId);
      return (
        entry !== undefined &&
        item.kind === entry.kind &&
        !this.watched.has(feedItemId(item)) &&
        videoPassesFilter(item, entry.filter)
      );
    }).length;
  });

  /** The items on screen, newest first. */
  feed: FeedItem[] = $derived.by(() => {
    const { showWatched, watched, justWatched } = this;
    return Array.from(this.passing.values())
      .filter((item) => {
        const id = feedItemId(item);
        return showWatched || !watched.has(id) || justWatched.has(id);
      })
      .sort(byNewest);
  });

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

  /** Let the cards marked watched since the last time drop out, where watched cards are hidden. */
  private dropJustWatched(): void {
    if (this.justWatched.size > 0) {
      this.justWatched = new Set();
    }
  }

  private markFetched(channelId: string, mode: ContentMode): void {
    const modes = this.fetchedModes.get(channelId);
    if (modes) {
      modes.add(mode);
    } else {
      this.fetchedModes.set(channelId, new Set([mode]));
    }
  }

  /*
   * Apply the synced watched state to one batch of items. Marks made here are in
   * the store already, so a batch can't revert one made while it loaded.
   */
  private applyWatchedBatch(batch: FeedItem[]): void {
    const next = new Set(this.watched);
    for (const id of batch.map(feedItemId)) {
      if (this.store.isWatched(id)) {
        next.add(id);
      } else {
        next.delete(id);
      }
    }
    this.watched = next;
  }

  private async fetchEverything(
    token: string,
    prefetched: Prefetched,
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
    const failed = new Set<string>();
    const fetched: Prefetched = new Map();
    const toFetch = enabled.filter((channel) => {
      const mode = channel.filter.contentMode ?? "videos";
      const ready = prefetched.get(channel.channelId);
      if (ready?.mode === mode) {
        fetched.set(channel.channelId, ready);
        return false;
      } else {
        return true;
      }
    });
    await mapWithConcurrency(toFetch, FETCH_CONCURRENCY, async (channel) => {
      try {
        fetched.set(channel.channelId, {
          mode: channel.filter.contentMode ?? "videos",
          items: await fetchChannelItems(channel, token, current?.probeShort),
        });
      } catch (caught) {
        if (
          caught instanceof TokenExpiredError ||
          caught instanceof InsufficientScopeError
        ) {
          throw caught;
        }
        failed.add(channel.channelId);
      }
    });
    return { subscribed, followedInfo, fetched, failed };
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
    for (const [channelId, { mode }] of data.fetched) {
      this.fetchedModes.set(channelId, new Set([mode]));
    }
    this.channels = channels;
    this.applyWatchedBatch(fresh);
    for (const channelId of data.failed) {
      // so an edit to it fetches it again
      this.fetchedModes.delete(channelId);
    }
    this.dropJustWatched();
  }

  /** Load subscriptions, sync files and every enabled channel's items. */
  async load(): Promise<void> {
    if (this.loadInFlight) {
      return;
    }
    this.loadInFlight = true;
    this.loading = true;
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
      this.notice =
        data.failed.size > 0
          ? "Some channels couldn't be loaded; showing partial results."
          : null;
    } catch (caught) {
      this.handleError(caught);
    } finally {
      this.loading = false;
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

  /** Show or hide watched cards. */
  toggleShowWatched(): void {
    this.showWatched = !this.showWatched;
    this.dropJustWatched();
  }

  /** Fetch a channel page's items when the feed doesn't load that channel. */
  async ensureChannelItems(): Promise<void> {
    const channelId = this.channelView;
    if (!channelId || !this.onDemandChannel) {
      return;
    }
    const mode = this.channelEntry?.filter.contentMode ?? "videos";
    if (
      this.channelItems?.id === channelId &&
      this.channelItems.mode === mode
    ) {
      return;
    }
    const channel: Channel = this.channelEntry ?? {
      channelId,
      title: channelId,
      thumbnail: "",
      filter: defaultFilter(),
    };
    this.channelLoading = true;
    this.channelError = null;
    try {
      const probe = (await platform())?.probeShort;
      const fetched = await withToken((token) =>
        fetchChannelItems(channel, token, probe),
      );
      if (this.channelView === channelId) {
        this.channelItems = { id: channelId, mode, items: fetched };
        if (this.channels.has(channelId)) {
          // kept, so turning the channel on doesn't fetch it again
          this.addChannelItems(channelId, mode, fetched);
        } else {
          this.applyWatchedBatch(fetched);
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
    this.dropJustWatched();
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

  /** Add items fetched elsewhere, e.g. for a preview, so they needn't be fetched again. */
  addChannelItems(
    channelId: string,
    mode: ContentMode,
    items: FeedItem[],
  ): void {
    this.items = replaceChannelItems(this.items, channelId, mode, items);
    this.markFetched(channelId, mode);
    this.applyWatchedBatch(items);
  }

  private isMissing(channelId: string, filter: ChannelFilter): boolean {
    return !this.fetchedModes
      .get(channelId)
      ?.has(filter.contentMode ?? "videos");
  }

  /** Fetch one channel's items into the feed, e.g. after it was switched on. */
  private async loadChannel(channel: Channel): Promise<void> {
    try {
      const probe = (await platform())?.probeShort;
      const fetched = await withToken((token) =>
        fetchChannelItems(channel, token, probe),
      );
      this.addChannelItems(
        channel.channelId,
        channel.filter.contentMode ?? "videos",
        fetched,
      );
    } catch (caught) {
      this.handleError(caught);
    }
  }

  private recordWatched(id: string, isWatched: boolean): void {
    this.store.setWatched(id, isWatched);
  }

  /** Whether a video or playlist is marked watched. */
  isWatched(id: string): boolean {
    return this.watched.has(id) || this.store.isWatched(id);
  }

  /** Mark or unmark an item. */
  setWatched(id: string, isWatched: boolean): void {
    const next = new Set(this.watched);
    if (isWatched) {
      next.add(id);
    } else {
      next.delete(id);
    }
    this.watched = next;
    if (isWatched) {
      this.justWatched = new Set(this.justWatched).add(id);
    }
    this.recordWatched(id, isWatched);
  }

  /** What a channel's "Mark all" button would do now, over its cards on screen. */
  markAllFor(channel: Channel): MarkAll {
    return markAllChoice(
      this.feed.filter((item) => item.channelId === channel.channelId),
      this.watched,
    );
  }

  /** Do what a channel's "Mark all" button says, as one save. */
  markAll(channel: Channel): void {
    const { watched, ids } = this.markAllFor(channel);
    if (ids.length === 0) {
      return;
    }
    const next = new Set(this.watched);
    for (const id of ids) {
      if (watched) {
        next.add(id);
      } else {
        next.delete(id);
      }
    }
    this.watched = next;
    if (watched) {
      this.justWatched = new Set([...this.justWatched, ...ids]);
    }
    this.store.setWatchedAll(ids, watched);
  }

  /** Flip an item's watched mark, from its card. */
  toggleWatched(item: FeedItem): void {
    const id = feedItemId(item);
    this.setWatched(id, !this.watched.has(id));
  }

  /** Every loaded item with this id, wherever it was loaded. */
  findItem(id: string): FeedItem | undefined {
    const matches = (item: FeedItem) => feedItemId(item) === id;
    return this.items.find(matches) ?? this.channelItems?.items.find(matches);
  }
}
