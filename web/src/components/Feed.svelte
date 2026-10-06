<script lang="ts">
  import { onMount, tick, untrack } from "svelte";
  import { AUTOPLAY_OPTIONS } from "../lib/autoplay";
  import { TIME_CHIP_OPTIONS } from "../lib/chips";
  import { videoCount } from "../lib/duration";
  import { FeedController } from "../lib/feed.svelte";
  import { feedItemId } from "../lib/feed-item";
  import { FEED_SORT_OPTIONS } from "../lib/feed-order";
  import type { RouteItem } from "../lib/router";
  import type { Router } from "../lib/router.svelte";
  import type { Session } from "../lib/session.svelte";
  import type { SyncStore } from "../lib/sync-store";
  import { cycleTheme, readTheme, type Theme } from "../lib/theme";
  import type { FeedItem } from "../lib/types";
  import { WATCHED_MODE_OPTIONS } from "../lib/watched-mode";
  import Avatar from "./Avatar.svelte";
  import ChannelSidebar from "./ChannelSidebar.svelte";
  import ChipRow from "./ChipRow.svelte";
  import CycleChip from "./CycleChip.svelte";
  import FeedCard from "./FeedCard.svelte";
  import FeedCardSkeleton from "./FeedCardSkeleton.svelte";
  import FilterEditor from "./FilterEditor.svelte";
  import Icon, { type IconName } from "./Icon.svelte";
  import LoadBar from "./LoadBar.svelte";
  import Player from "./Player.svelte";
  import PlayerFrame from "./PlayerFrame.svelte";
  import Settings from "./Settings.svelte";
  import YouTubeAttribution from "./YouTubeAttribution.svelte";

  let {
    session,
    store,
    router,
  }: {
    /** who is signed in */
    session: Session;
    /** the account's synced edits */
    store: SyncStore;
    /** where the app is */
    router: Router;
  } = $props();

  const THEME_NAME: Record<Theme, string> = {
    system: "System",
    light: "Light",
    dark: "Dark",
  };
  const THEME_ICON: Record<Theme, IconName> = {
    system: "themeSystem",
    light: "themeLight",
    dark: "themeDark",
  };

  // svelte-ignore state_referenced_locally
  const feed = new FeedController(session, store, router);
  /** localStorage key: set while the left sidebar is collapsed to its icons. */
  const SIDEBAR_COLLAPSED = "subtube.sidebarCollapsed";
  const NARROW = window.matchMedia("(max-width: 760px)");
  const REDUCED_MOTION = window.matchMedia("(prefers-reduced-motion: reduce)");

  function readCollapsed(): boolean {
    try {
      return localStorage.getItem(SIDEBAR_COLLAPSED) !== null;
    } catch {
      return false;
    }
  }

  // the left sidebar as a drawer, in windows too narrow to keep it in place
  let showSidebar = $state(false);
  let narrow = $state(NARROW.matches);
  // the left sidebar as a rail of icons that widens over the grid on hover
  let collapsed = $state(readCollapsed());
  let showDetails = $state(false);
  let showSettings = $state(false);
  // the card playing in place of its thumbnail, in a narrow window
  let inlineItem: RouteItem | null = $state(null);
  let theme: Theme = $state(readTheme());

  const account = $derived(session.account);
  const route = $derived(router.route);
  // enough skeleton cards to fill a large window
  const SKELETONS = Array.from({ length: 24 }, (_, index) => index);

  // loading with nothing to show yet, on the feed or on a channel's own load
  const firstLoad = $derived(
    feed.feed.length === 0 &&
      (feed.loading || session.checking || feed.channelLoading),
  );

  const title = $derived(
    route.channel
      ? (feed.channelEntry?.title ??
          feed.channelItems?.items[0]?.channelTitle ??
          "")
      : "Feed",
  );

  // changes whenever the user goes somewhere, which lets the channel list be put in order again
  const whereabouts = $derived(
    JSON.stringify([
      route.channel,
      route.item !== null,
      showSettings,
      narrow && showSidebar,
    ]),
  );

  function routeItem(item: FeedItem): RouteItem {
    return { kind: item.kind, id: feedItemId(item) };
  }

  function cardOf(id: string): HTMLElement | null {
    return document.querySelector<HTMLElement>(
      `[data-card="${CSS.escape(id)}"]`,
    );
  }

  /** Play a card: in place of its thumbnail in a narrow window, otherwise in the player over the app. */
  function play(item: FeedItem): void {
    if (narrow) {
      inlineItem = routeItem(item);
    } else {
      inlineItem = null;
      router.open({ channel: router.route.channel, item: routeItem(item) });
    }
  }

  /** The card playing in place ended: auto-play's next card takes over, scrolled into view. */
  function inlineEnded(endedId: string): void {
    const next = feed.autoplayNext(endedId);
    inlineItem = next ? routeItem(next) : null;
    if (next) {
      void tick().then(() => {
        cardOf(feedItemId(next))?.scrollIntoView({
          block: "nearest",
          behavior: REDUCED_MOTION.matches ? "auto" : "smooth",
        });
      });
    }
  }

  /** The player over the app ended: auto-play's next item plays in it. */
  function overlayEnded(endedId: string): void {
    const next = feed.autoplayNext(endedId);
    if (next) {
      router.replace({ channel: router.route.channel, item: routeItem(next) });
    }
  }

  /** Show the feed (null) or a channel's page. */
  function open(channelId: string | null): void {
    showSidebar = false;
    if (router.route.channel !== channelId || router.route.item) {
      router.open({ channel: channelId, item: null });
    }
  }

  function refresh(): void {
    if (session.ready) {
      feed.refresh();
    }
  }

  /** A sidebar row: go there, or refresh when it is where the app already is. */
  function select(channelId: string | null): void {
    if (router.route.channel === channelId && !router.route.item) {
      showSidebar = false;
      refresh();
    } else {
      open(channelId);
    }
  }

  /** The logo: the feed, refreshed. */
  function home(): void {
    open(null);
    refresh();
  }

  function toggleSidebar(): void {
    if (narrow) {
      showSidebar = !showSidebar;
    } else {
      collapsed = !collapsed;
      try {
        if (collapsed) {
          localStorage.setItem(SIDEBAR_COLLAPSED, "1");
        } else {
          localStorage.removeItem(SIDEBAR_COLLAPSED);
        }
      } catch {
        // applies for this visit only
      }
    }
  }

  onMount(() => {
    const stop = feed.start();
    void session.restore();
    const onNarrow = () => {
      narrow = NARROW.matches;
      showSidebar = false;
    };
    NARROW.addEventListener("change", onNarrow);
    return () => {
      NARROW.removeEventListener("change", onNarrow);
      stop();
    };
  });

  // a load runs once a token is at hand: on start, and after signing in again
  $effect(() => {
    if (session.ready) {
      untrack(() => void feed.load());
    }
  });

  // a card that left the list stops playing; unmounting it saved its position
  $effect(() => {
    const playing = inlineItem;
    if (playing && !feed.feed.some((item) => feedItemId(item) === playing.id)) {
      inlineItem = null;
    }
  });

  // focus goes back to the card of whatever the closed player last played
  let overlayId: string | null = null;
  $effect(() => {
    const openId = router.route.item?.id ?? null;
    if (openId === null && overlayId !== null) {
      cardOf(overlayId)?.querySelector("button")?.focus();
    }
    overlayId = openId;
  });

  $effect(() => {
    void router.route.channel;
    void feed.channels;
    untrack(() => void feed.ensureChannelItems());
  });
</script>

<div class="app">
  <div class="left" class:open={showSidebar} class:collapsed>
    <div class="panel">
      <ChannelSidebar
        {feed}
        selected={route.channel}
        {whereabouts}
        onselect={select}
        onhome={home}
        collapsed={!narrow && collapsed}
        ontoggle={toggleSidebar}
      />
    </div>
  </div>
  {#if showSidebar}
    <button
      type="button"
      class="scrim"
      aria-label="Close channels"
      onclick={() => {
        showSidebar = false;
      }}
    ></button>
  {/if}

  <div class="main">
    <header>
      {#if narrow}
        <button
          type="button"
          class="icon-button sidebar-toggle"
          aria-label="Channels"
          title="Channels"
          aria-expanded={showSidebar}
          onclick={toggleSidebar}
        >
          <Icon name="sidebarLeft" />
        </button>
      {/if}
      <div class="titles">
        <h1 id="page-title">{title}</h1>
        {#if !route.channel && !firstLoad}
          <span class="secondary subtitle">{videoCount(feed.feed.length)}</span>
        {/if}
      </div>
      <div class="tools">
        <button
          type="button"
          class="icon-button"
          aria-label={`Theme: ${THEME_NAME[theme]}`}
          title={`Theme: ${THEME_NAME[theme]}`}
          onclick={() => {
            theme = cycleTheme(theme);
          }}
        >
          <Icon name={THEME_ICON[theme]} />
        </button>
        <button
          type="button"
          class="icon-button"
          aria-label={showDetails ? "Hide details" : "Show details"}
          title={showDetails ? "Hide details" : "Show details"}
          aria-expanded={showDetails}
          onclick={() => {
            showDetails = !showDetails;
          }}
        >
          <Icon name="sidebarRight" />
        </button>
      </div>
      {#if account}
        <button
          type="button"
          class="account"
          class:open={showSettings}
          aria-label="Account and settings"
          aria-expanded={showSettings}
          data-settings-toggle
          onclick={() => {
            showSettings = !showSettings;
          }}
        >
          <Avatar
            title={account.title}
            thumbnail={account.thumbnail}
            size={28}
            tint
          />
        </button>
      {/if}
    </header>

    {#if showSettings && account}
      <Settings
        {account}
        lastSynced={store.lastSynced}
        onclose={() => {
          showSettings = false;
        }}
        onsignout={() => {
          showSettings = false;
          void session.signOut();
        }}
        ondelete={() => session.deleteProfile()}
      />
    {/if}

    <ChipRow
      topics={feed.topicChips}
      selected={feed.settings.topicChips}
      ontopic={(categoryId) => feed.toggleTopicChip(categoryId)}
      onclear={() => feed.setSetting("topicChips", [])}
    >
      {#snippet leading()}
        <CycleChip
          options={AUTOPLAY_OPTIONS}
          value={feed.settings.autoplay ? "on" : "off"}
          onchange={(autoplay) =>
            feed.setSetting("autoplay", autoplay === "on")}
        />
        <CycleChip
          options={FEED_SORT_OPTIONS}
          value={feed.settings.feedSort}
          onchange={(feedSort) => feed.setSetting("feedSort", feedSort)}
        />
        <CycleChip
          options={TIME_CHIP_OPTIONS}
          value={feed.settings.timeChip}
          onchange={(timeChip) => feed.setSetting("timeChip", timeChip)}
        />
        <CycleChip
          options={WATCHED_MODE_OPTIONS}
          value={feed.watchedMode}
          onchange={(mode) => feed.setWatchedMode(mode)}
        />
      {/snippet}
    </ChipRow>

    <div class="body">
      <div class="pane">
        <div class="content">
          {#if !session.ready && !session.checking && !session.connecting}
            <div class="banner">
              <span>
                {session.expired
                  ? "Your Google session ended. Sign in again to refresh."
                  : "Sign in again to load your feed."}
              </span>
              <button
                type="button"
                class="button-small"
                onclick={() => void session.signIn()}
              >
                Sign in
              </button>
            </div>
          {/if}
          {#if session.error || feed.error}
            <div class="banner error" role="alert">
              <span>{feed.error ?? session.error}</span>
            </div>
          {/if}
          {#if feed.notice}
            <div class="banner" role="status">
              <span>{feed.notice}</span>
              <button
                type="button"
                class="icon-button"
                aria-label="Dismiss"
                onclick={() => {
                  feed.notice = null;
                }}
              >
                <Icon name="close" />
              </button>
            </div>
          {/if}

          <main
            class:stale={feed.loading}
            class:shimmer={firstLoad}
            inert={feed.loading || firstLoad}
            aria-busy={feed.loading || firstLoad}
          >
            {#if firstLoad}
              {#each SKELETONS as index (index)}
                <FeedCardSkeleton />
              {/each}
            {/if}
            {#each feed.feed as item (feedItemId(item))}
              {@const id = feedItemId(item)}
              <FeedCard
                {item}
                watched={feed.watched.has(id)}
                progress={feed.bars.get(id) ?? null}
                player={inlineItem?.id === id ? inlinePlayer : undefined}
                onopen={() => play(item)}
                onopenchannel={() => open(item.channelId)}
              />
            {/each}
          </main>

          {#if feed.feed.length === 0}
            {#if firstLoad}
              <!-- the skeleton cards above stand in for the list -->
            {:else if feed.channelError}
              <p class="empty error-text">{feed.channelError}</p>
            {:else if session.ready}
              <p class="empty secondary">
                {feed.emptiedBySelection
                  ? "No videos for selected filter"
                  : "Nothing new. You're caught up."}
              </p>
            {/if}
          {/if}
          {#if !firstLoad}
            <div class="attribution">
              <YouTubeAttribution />
            </div>
          {/if}
        </div>
        {#if feed.loading && !firstLoad}
          <div class="shimmer-band"></div>
        {/if}
        <LoadBar progress={feed.loadProgress} labelledby="page-title" />
      </div>

      <aside
        class="right"
        class:open={showDetails}
        inert={!showDetails}
        aria-label={feed.channelEntry
          ? `Filters for ${feed.channelEntry.title}`
          : "Details"}
      >
        <div class="right-panel">
          {#if feed.channelEntry}
            {#key feed.channelEntry.channelId}
              <FilterEditor {feed} channel={feed.channelEntry} />
            {/key}
          {:else}
            <p class="secondary none">Select a channel to edit its filters.</p>
          {/if}
        </div>
      </aside>
    </div>
  </div>
</div>

{#snippet inlinePlayer()}
  {#if inlineItem}
    {@const playing = inlineItem}
    <PlayerFrame
      item={playing}
      {feed}
      focusPlayer
      onended={() => inlineEnded(playing.id)}
    />
  {/if}
{/snippet}

{#if route.item}
  {@const playing = route.item}
  <Player
    item={playing}
    {feed}
    onclose={() => router.close()}
    onended={() => overlayEnded(playing.id)}
  />
{/if}

<style>
  .app {
    display: flex;
    height: 100dvh;
    overflow: hidden;
  }

  .left {
    position: relative;
    flex-shrink: 0;
    width: 240px;
    transition: width 0.2s;
  }

  .left.collapsed {
    width: 56px;
  }

  /* laid over the grid when it widens from the rail, so the grid doesn't reflow */
  .panel {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    z-index: 13;
    width: 240px;
    overflow: clip;
    border-right: 1px solid var(--border);
    transition:
      width 0.2s,
      box-shadow 0.2s;
  }

  .left.collapsed .panel {
    width: 56px;
  }

  /* :focus-visible, not :focus-within: a clicked row must not hold it open */
  .left.collapsed:hover .panel,
  .left.collapsed:has(:global(:focus-visible)) .panel {
    width: 240px;
    box-shadow: 8px 0 32px var(--shadow);
  }

  .scrim {
    display: none;
  }

  .main {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  header {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    background: var(--header);
  }

  .titles {
    min-width: 0;
    display: flex;
    align-items: baseline;
    gap: 10px;
  }

  h1 {
    margin: 0;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 18px;
    font-weight: 700;
  }

  .subtitle {
    flex-shrink: 0;
    font-size: 13px;
  }

  .tools {
    margin-left: auto;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .account {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
  }

  .account.open {
    box-shadow: 0 0 0 2px var(--gold);
  }

  .body {
    position: relative;
    flex: 1;
    min-height: 0;
    display: flex;
    overflow: hidden;
  }

  .pane {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
  }

  .content {
    flex: 1;
    min-width: 0;
    overflow-y: auto;
  }

  .right {
    flex-shrink: 0;
    width: 0;
    overflow: hidden;
    visibility: hidden;
    transition:
      width 0.2s,
      transform 0.2s,
      visibility 0s 0.2s;
  }

  .right.open {
    width: 320px;
    visibility: visible;
    transition:
      width 0.2s,
      transform 0.2s;
  }

  .right-panel {
    width: 320px;
    height: 100%;
    padding-bottom: 24px;
    overflow-y: auto;
    border-left: 1px solid var(--border);
    background: var(--page);
  }

  .none {
    margin: 0;
    padding: 48px 24px;
    text-align: center;
    font-size: 14px;
  }

  .banner {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 44px;
    padding: 6px 16px;
    background: var(--tint);
    color: var(--tint-text);
    font-size: 14px;
  }

  .banner > :first-child {
    flex: 1;
  }

  .banner.error {
    color: var(--error);
  }

  main {
    max-width: 1280px;
    margin: 0 auto;
    padding: 16px;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr));
    gap: 16px;
  }

  main.stale > :global(.card) {
    opacity: 0.4;
    transition: opacity 0.2s;
  }

  .empty {
    display: flex;
    justify-content: center;
    margin: 0;
    padding: 32px 16px;
    text-align: center;
  }

  .attribution {
    display: flex;
    justify-content: center;
    padding: 16px 16px 24px;
  }

  /* too narrow for three columns: the filter editor lies over the grid */
  @media (max-width: 1100px) {
    .right,
    .right.open {
      position: absolute;
      top: 0;
      right: 0;
      bottom: 0;
      z-index: 12;
      width: min(320px, 100%);
    }

    .right {
      transform: translateX(100%);
    }

    .right.open {
      transform: none;
      box-shadow: -8px 0 32px var(--shadow);
    }

    .right-panel {
      width: 100%;
    }
  }

  /* too narrow for the channel list: it becomes a drawer */
  @media (max-width: 760px) {
    .left,
    .left.collapsed {
      position: fixed;
      top: 0;
      bottom: 0;
      left: 0;
      z-index: 21;
      width: min(280px, 85vw);
      transform: translateX(-100%);
      visibility: hidden;
      transition: none;
    }

    .left .panel,
    .left.collapsed .panel,
    .left.collapsed:hover .panel,
    .left.collapsed:has(:global(:focus-visible)) .panel {
      width: 100%;
      box-shadow: none;
      transition: none;
    }

    .left.open {
      transform: none;
      visibility: visible;
      box-shadow: 8px 0 32px var(--shadow);
    }

    .scrim {
      display: block;
      position: fixed;
      inset: 0;
      z-index: 20;
      border: 0;
      background: var(--scrim);
      cursor: default;
    }

    .subtitle {
      display: none;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .left,
    .panel,
    .right,
    .right.open {
      transition: none;
    }
  }
</style>
