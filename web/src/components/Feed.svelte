<script lang="ts">
  import { Popover } from "bits-ui";
  import { onMount, untrack } from "svelte";
  import { prefersReducedMotion } from "svelte/motion";
  import { fade } from "svelte/transition";
  import { videoCount } from "../lib/duration";
  import { FeedController } from "../lib/feed.svelte";
  import { feedItemId } from "../lib/feed-item";
  import { chipTitle } from "../lib/groups";
  import { MINIMIZED_ROOM } from "../lib/player";
  import { PlayerController } from "../lib/player.svelte";
  import type { Router } from "../lib/router.svelte";
  import type { Session } from "../lib/session.svelte";
  import { readText, writeText } from "../lib/storage";
  import type { SyncStore } from "../lib/sync-store";
  import { cycleTheme, readTheme, type Theme } from "../lib/theme";
  import Avatar from "./Avatar.svelte";
  import ChannelSidebar from "./ChannelSidebar.svelte";
  import ChipRow from "./ChipRow.svelte";
  import FeedCard from "./FeedCard.svelte";
  import FeedCardSkeleton from "./FeedCardSkeleton.svelte";
  import FilterEditor from "./FilterEditor.svelte";
  import FilterMenu from "./FilterMenu.svelte";
  import GroupEditor from "./GroupEditor.svelte";
  import Icon, { type IconName } from "./Icon.svelte";
  import LoadBar from "./LoadBar.svelte";
  import PlayerHost from "./PlayerHost.svelte";
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
  /** The width of the details panel, which the minimized player sits beside. */
  const DETAILS_WIDTH = 320;
  /** How long the window may keep its full-screen size after full screen has ended. */
  const FULL_SCREEN_SETTLE_MS = 500;
  let fullScreenEnded = Number.NEGATIVE_INFINITY;
  // svelte-ignore state_referenced_locally
  const player = new PlayerController(
    feed,
    router,
    () => NARROW.matches,
    () =>
      document.fullscreenElement !== null ||
      performance.now() - fullScreenEnded < FULL_SCREEN_SETTLE_MS,
  );

  // the left sidebar as a drawer, in windows too narrow to keep it in place
  let showSidebar = $state(false);
  let narrow = $state(NARROW.matches);
  // the left sidebar as a rail of icons that widens over the grid on hover
  let collapsed = $state(readText(SIDEBAR_COLLAPSED) !== null);
  let showDetails = $state(false);
  let showSettings = $state(false);
  // the group editor, which takes the filter editor's place in the right panel
  // until it closes or the page changes: the group's name (null for a new
  // one) and a count that makes each opening a fresh editor
  let groupEdit: { group: string | null; opening: number } | null =
    $state(null);
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

  // the row's selected groups and topics; a channel's page has no group chips
  const selection = $derived(
    chipTitle(
      route.channel ? [] : feed.groups,
      feed.settings.groupChips,
      feed.topicChips,
      feed.settings.topicChips,
    ),
  );

  // they take the feed's title's place; a channel's page keeps its name
  const title = $derived(
    route.channel
      ? (feed.channelEntry?.title ??
          feed.channelItems?.items[0]?.channelTitle ??
          "")
      : selection.names.length > 0
        ? selection.names.join(", ")
        : "Feed",
  );

  // the channel whose filters the details panel shows
  const filtersChannel = $derived(
    showDetails && groupEdit === null ? route.channel : null,
  );

  // a page with nothing to show and nothing wrong
  const showsEmptyState = $derived(
    feed.feed.length === 0 &&
      !firstLoad &&
      !feed.channelError &&
      session.ready &&
      !feed.error &&
      !session.error,
  );

  // the cards have scrolled under the heading, so they fade out at their top edge
  let scrolled = $state(false);

  // changes whenever the user goes somewhere, which lets the channel list be put in order again
  const whereabouts = $derived(
    JSON.stringify([
      route.channel,
      route.item !== null,
      showSettings,
      narrow && showSidebar,
    ]),
  );

  function cardOf(id: string): HTMLElement | null {
    return document.querySelector<HTMLElement>(
      `[data-card="${CSS.escape(id)}"]`,
    );
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

  /** Open the group editor in the right panel: for a group by its name, or for a new one (null). */
  function editGroup(group: string | null): void {
    groupEdit = { group, opening: (groupEdit?.opening ?? 0) + 1 };
    showDetails = true;
    showSidebar = false;
  }

  /** A sidebar row's filters button: that channel's page with its filters beside it, or the panel closed when it already shows them. */
  function toggleFilters(channelId: string): void {
    if (filtersChannel === channelId) {
      showDetails = false;
    } else {
      open(channelId);
      // after the page change, which ends a group edit
      groupEdit = null;
      showDetails = true;
    }
  }

  function toggleSidebar(): void {
    if (narrow) {
      showSidebar = !showSidebar;
    } else {
      collapsed = !collapsed;
      writeText(SIDEBAR_COLLAPSED, collapsed ? "1" : null);
    }
  }

  onMount(() => {
    const stop = feed.start();
    void session.restore();
    const onNarrow = () => {
      narrow = NARROW.matches;
      showSidebar = false;
    };
    let settleTimer: ReturnType<typeof setTimeout> | undefined;
    const onFullScreen = () => {
      if (document.fullscreenElement === null) {
        fullScreenEnded = performance.now();
        clearTimeout(settleTimer);
        // a window still wide by then is wide
        settleTimer = setTimeout(
          () => player.pageChanged(),
          FULL_SCREEN_SETTLE_MS,
        );
      }
    };
    NARROW.addEventListener("change", onNarrow);
    document.addEventListener("fullscreenchange", onFullScreen);
    return () => {
      NARROW.removeEventListener("change", onNarrow);
      document.removeEventListener("fullscreenchange", onFullScreen);
      clearTimeout(settleTimer);
      stop();
    };
  });

  // a load runs once a token is at hand: on start, and after signing in again
  $effect(() => {
    if (session.ready) {
      untrack(() => void feed.load());
    }
  });

  $effect(() => {
    const item = router.route.item;
    untrack(() => player.routeChanged(item));
  });

  $effect(() => {
    void router.route.channel;
    void feed.feed;
    void narrow;
    untrack(() => player.pageChanged());
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

  // going to another page leaves the group editor, unsaved edits and all
  $effect(() => {
    void router.route.channel;
    const channel = router.route.channel;
    untrack(() => {
      groupEdit = null;
      // the panel has only a channel's filters to show
      if (channel === null) {
        showDetails = false;
      }
      feed.pageChanged();
    });
  });
</script>

<div class="app" inert={player.playing?.place === "large"}>
  <div class="left" class:open={showSidebar} class:collapsed>
    <div class="panel">
      <ChannelSidebar
        {feed}
        selected={route.channel}
        {whereabouts}
        {filtersChannel}
        onselect={select}
        onfilters={toggleFilters}
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
      transition:fade={{ duration: prefersReducedMotion.current ? 0 : 200 }}
      onclick={() => {
        showSidebar = false;
      }}
    ></button>
  {/if}

  <div class="main">
    <div class="center">
      <LoadBar progress={feed.loadProgress} labelledby="page-title" />
      <Popover.Root bind:open={showSettings}>
        <header>
          {#if narrow}
            <button
              type="button"
              class="icon-button sidebar-toggle"
              aria-label="Show channels"
              title="Show channels"
              aria-expanded={showSidebar}
              onclick={toggleSidebar}
            >
              <Icon name="channels" />
            </button>
          {/if}
          <div class="heading">
            <div class="titles">
              <h1 id="page-title">{title}</h1>
              {#if selection.names.length > 0}
                {#if selection.edit !== null}
                  {@const group = selection.edit}
                  <button
                    type="button"
                    class="icon-button"
                    aria-label="Edit group"
                    title="Edit group"
                    onclick={() => editGroup(group)}
                  >
                    <Icon name="pencil" />
                  </button>
                {/if}
                <button
                  type="button"
                  class="icon-button"
                  aria-label="Clear"
                  title="Clear"
                  onclick={() => {
                    if (route.channel) {
                      feed.setSetting("topicChips", []);
                    } else {
                      feed.clearChips();
                    }
                  }}
                >
                  <Icon name="close" />
                </button>
              {/if}
            </div>
            <!-- a count of the stand-in cards would be none -->
            <span class="secondary subtitle" class:unknown={firstLoad}
              >{videoCount(feed.feed.length)}</span
            >
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
            {#if account}
              <Popover.Trigger aria-label="Account and settings">
                {#snippet child({
                  props,
                })}
                  <button
                    {...props}
                    type="button"
                    class="account"
                    class:open={showSettings}
                  >
                    <Avatar
                      title={account.title}
                      thumbnail={account.thumbnail}
                      size={28}
                      tint
                    />
                  </button>
                {/snippet}
              </Popover.Trigger>
            {/if}
          </div>
        </header>

        {#if account}
          <Settings
            {account}
            lastSynced={store.lastSynced}
            onsignout={() => {
              showSettings = false;
              void session.signOut();
            }}
            ondelete={() => session.deleteProfile()}
          />
        {/if}
      </Popover.Root>

      <ChipRow
        groups={route.channel ? [] : feed.groups}
        selectedGroups={feed.settings.groupChips}
        ongroup={(group) => feed.toggleGroupChip(group)}
        onnewgroup={!route.channel && feed.loadCount > 0
          ? () => editGroup(null)
          : undefined}
        topics={feed.topicChips}
        selected={feed.settings.topicChips}
        ontopic={(categoryId) => feed.toggleTopicChip(categoryId)}
      >
        {#snippet menu()}
          <FilterMenu {feed} />
        {/snippet}
      </ChipRow>

      <div class="body">
        <div class="pane">
          <div
            class="content"
            class:scrolled={scrolled}
            class:vacant={showsEmptyState}
            onscroll={(event) => {
              scrolled = event.currentTarget.scrollTop > 1;
            }}
            data-player-view
            style:padding-bottom={player.playing?.place === "minimized"
              ? `${MINIMIZED_ROOM}px`
              : undefined}
          >
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
                  playing={player.isPlaying(id)}
                  holdsPlayer={player.inCard(id)}
                  onopen={() => player.play(item)}
                  onmark={() => feed.setWatched(id, !feed.watched.has(id))}
                  onopenchannel={() => open(item.channelId)}
                />
              {/each}
            </main>

            {#if feed.feed.length === 0}
              {#if firstLoad}
                <!-- the skeleton cards above stand in for the list -->
              {:else if feed.channelError}
                <p class="empty error-text">{feed.channelError}</p>
              {:else if showsEmptyState}
                <div class="empty-state">
                  <span class="disk">
                    <Icon name="check" size={28} strokeWidth={2.5} />
                  </span>
                  <h2>
                    {feed.emptiedBySelection
                      ? "No videos for the selected filter."
                      : "Nothing new. You're caught up."}
                  </h2>
                  <button
                    type="button"
                    class="button-compact"
                    onclick={refresh}
                  >
                    Refresh
                  </button>
                </div>
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
        </div>
      </div>
    </div>
    <aside
      class="right"
      class:open={showDetails}
      inert={!showDetails}
      aria-label={groupEdit
        ? groupEdit.group === null
          ? "New group"
          : "Edit group"
        : `Filters for ${feed.channelEntry?.title ?? ""}`}
    >
      <div class="right-panel">
        {#if groupEdit}
          {#key groupEdit.opening}
            <GroupEditor
              {feed}
              group={groupEdit.group}
              onclose={() => {
                showDetails = false;
              }}
            />
          {/key}
        {:else if feed.channelEntry}
          {#key feed.channelEntry.channelId}
            <FilterEditor
              {feed}
              channel={feed.channelEntry}
              onclose={() => {
                showDetails = false;
              }}
            />
          {/key}
        {/if}
      </div>
    </aside>
  </div>
</div>

<PlayerHost
  {player}
  {feed}
  {narrow}
  beside={!narrow && showDetails ? DETAILS_WIDTH : 0}
/>

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
    overflow: hidden;
  }

  .center {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  /* no line under it: the cards fade out where they meet the chips */
  header {
    flex-shrink: 0;
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 14px 20px 2px;
  }

  .heading {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .titles {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  h1 {
    margin: 0 4px 0 0;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 28px;
    line-height: 34px;
    font-weight: 700;
  }

  .subtitle {
    font-size: 14px;
  }

  .subtitle.unknown {
    visibility: hidden;
  }

  .tools {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
  }

  .sidebar-toggle {
    margin-top: 3px;
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

  .content.scrolled {
    mask-image: linear-gradient(to bottom, transparent, #000 16px);
  }

  /* the empty state stands in the middle, the attribution at the foot */
  .content.vacant {
    display: flex;
    flex-direction: column;
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
    padding: 12px 20px 20px;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr));
    gap: 16px;
  }

  .content.vacant > main {
    display: none;
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

  .empty-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 14px;
    padding: 32px 20px;
    text-align: center;
  }

  .disk {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: var(--sunflower);
    color: var(--ink);
  }

  .empty-state h2 {
    margin: 0;
    font-size: 20px;
    line-height: 26px;
    font-weight: 600;
    text-wrap: balance;
  }

  .empty-state .button-compact {
    padding: 0 18px;
    background: var(--surface);
  }

  .empty-state .button-compact:hover {
    background: var(--border);
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
      transition:
        transform 0.2s,
        visibility 0s 0.2s;
    }

    .left .panel,
    .left.collapsed .panel,
    .left.collapsed:hover .panel,
    .left.collapsed:has(:global(:focus-visible)) .panel {
      width: 100%;
      box-shadow: none;
      transition: none;
    }

    .right,
    .right.open {
      width: 100%;
    }

    .left.open {
      transform: none;
      visibility: visible;
      box-shadow: 8px 0 32px var(--shadow);
      transition: transform 0.2s;
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

    header {
      padding: 10px 16px 2px;
    }

    h1 {
      font-size: 24px;
      line-height: 30px;
    }

    main {
      padding: 12px 16px 16px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .left,
    .left.collapsed,
    .left.open,
    .panel,
    .right,
    .right.open {
      transition: none;
    }
  }
</style>
