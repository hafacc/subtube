<script lang="ts">
  import { onMount, untrack } from "svelte";
  import { videoCount } from "../lib/duration";
  import { FeedController } from "../lib/feed.svelte";
  import { feedItemId } from "../lib/feed-item";
  import type { Router } from "../lib/router.svelte";
  import type { Session } from "../lib/session.svelte";
  import type { SyncStore } from "../lib/sync-store";
  import { cycleTheme, readTheme, type Theme } from "../lib/theme";
  import Avatar from "./Avatar.svelte";
  import ChannelSidebar from "./ChannelSidebar.svelte";
  import FeedCard from "./FeedCard.svelte";
  import FilterEditor from "./FilterEditor.svelte";
  import Icon, { type IconName } from "./Icon.svelte";
  import Player from "./Player.svelte";
  import Settings from "./Settings.svelte";

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
  let theme: Theme = $state(readTheme());

  const account = $derived(session.account);
  const route = $derived(router.route);
  const spinning = $derived(
    feed.loading ||
      session.checking ||
      session.connecting ||
      feed.channelLoading,
  );

  const title = $derived(
    route.channel
      ? (feed.channelEntry?.title ??
          feed.channelItems?.items[0]?.channelTitle ??
          "")
      : "Feed",
  );

  /** Show the feed (null) or a channel's page. */
  function select(channelId: string | null): void {
    showSidebar = false;
    if (router.route.channel !== channelId || router.route.item) {
      router.open({ channel: channelId, item: null });
    }
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
        onselect={select}
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
        <h1>{title}</h1>
        {#if !route.channel}
          <span class="secondary subtitle">{videoCount(feed.feed.length)}</span>
        {/if}
      </div>
      <div class="tools">
        <button
          type="button"
          class="icon-button"
          aria-label="Refresh"
          title="Refresh"
          aria-busy={spinning}
          disabled={!session.ready}
          onclick={() => feed.refresh()}
        >
          <span class:spinning><Icon name="refresh" /></span>
        </button>
        <button
          type="button"
          class="icon-button"
          aria-label={feed.showWatched ? "Hide watched" : "Show watched"}
          title={feed.showWatched ? "Hide watched" : "Show watched"}
          onclick={() => feed.toggleShowWatched()}
        >
          <Icon name={feed.showWatched ? "eye" : "eyeOff"} />
        </button>
        <button
          type="button"
          class="icon-button"
          aria-label={`Theme: ${theme}`}
          title={`Theme: ${theme}`}
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

    <div class="body">
      <div class="content">
        {#if !session.ready && !session.checking && !session.connecting}
          <div class="banner">
            <span>Sign in again to load your feed.</span>
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
          inert={feed.loading}
          aria-busy={feed.loading}
        >
          {#each feed.feed as item (feedItemId(item))}
            <FeedCard
              {item}
              watched={feed.watched.has(feedItemId(item))}
              onopen={() =>
                router.open({
                  channel: route.channel,
                  item:
                    item.kind === "playlist"
                      ? { kind: "playlist", id: item.playlistId }
                      : { kind: "video", id: item.videoId },
                })}
              onopenchannel={() => select(item.channelId)}
              ontogglewatched={() => feed.toggleWatched(item)}
            />
          {/each}
        </main>

        {#if feed.feed.length === 0}
          {#if feed.hydrating ||
            feed.loading ||
            session.checking ||
            feed.channelLoading}
            <p class="empty secondary">
              <span class="spinning"><Icon name="refresh" size={20} /></span>
            </p>
          {:else if feed.channelError}
            <p class="empty error-text">{feed.channelError}</p>
          {:else if session.ready}
            <p class="empty secondary">Nothing new. You're caught up.</p>
          {/if}
        {/if}
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

{#if route.item}
  {#key `${route.item.kind}:${route.item.id}`}
    <Player
      item={route.item}
      {feed}
      onclose={() => router.close()}
      onopenchannel={(channelId) =>
        router.open({ channel: channelId, item: null })}
    />
  {/key}
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

  .spinning {
    display: flex;
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

  main.stale {
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
