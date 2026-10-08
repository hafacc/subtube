<script lang="ts">
  import { Toggle } from "bits-ui";
  import { HeldChannelOrder, orderChannels } from "../lib/channel-order";
  import { privacyUrl, termsUrl } from "../lib/config";
  import type { FeedController } from "../lib/feed.svelte";
  import Avatar from "./Avatar.svelte";
  import Icon from "./Icon.svelte";
  import Logo from "./Logo.svelte";
  import YouTubeAttribution from "./YouTubeAttribution.svelte";

  let {
    feed,
    selected,
    whereabouts,
    onselect,
    onhome,
    collapsed,
    ontoggle,
  }: {
    /** the feed whose channels these are */
    feed: FeedController;
    /** the channel whose page is open, or null for the feed */
    selected: string | null;
    /** where the user is in the app; the list is put in order again when it changes */
    whereabouts: string;
    /** a row was clicked: the feed (null) or a channel; the current one again refreshes */
    onselect: (channelId: string | null) => void;
    /** the logo was clicked: show the feed and refresh it */
    onhome: () => void;
    /** whether the sidebar is collapsed to its icons, widening only on hover */
    collapsed: boolean;
    /** collapse the sidebar, or pin it open */
    ontoggle: () => void;
  } = $props();

  const held = new HeldChannelOrder();
  const channels = $derived(
    held.arrange(
      orderChannels(
        Array.from(feed.channels.values()),
        feed.items,
        "newestUnwatched",
        feed.unwatched,
      ),
      JSON.stringify([whereabouts, feed.loadCount]),
    ),
  );
</script>

<nav aria-label="Channels">
  <div class="list">
    <div class="head">
      <button
        type="button"
        class="brand home"
        aria-label="Refresh"
        onclick={onhome}
      >
        <Logo />
        <span class="wide-only">SubTube</span>
      </button>
      <Toggle.Root
        aria-label="Channels"
        title="Channels"
        aria-expanded={!collapsed}
        bind:pressed={() => !collapsed, () => ontoggle()}
      >
        {#snippet child({
          props,
        })}
          <button {...props} type="button" class="icon-button">
            <Icon name="sidebarLeft" />
          </button>
        {/snippet}
      </Toggle.Root>
    </div>
    <button
      type="button"
      class="row"
      class:current={selected === null}
      aria-current={selected === null ? "page" : undefined}
      onclick={() => onselect(null)}
    >
      <span class="feed-icon"><Icon name="tray" size={18} /></span>
      <span class="title">Feed</span>
      {#if feed.unwatchedCount > 0}
        <span class="count wide-only" aria-hidden="true"
          >{feed.unwatchedCount}</span
        >
        <span class="visually-hidden">{feed.unwatchedCount} unwatched</span>
      {/if}
    </button>
    <h2>Channels</h2>
    {#each channels as channel (channel.channelId)}
      {@const current = channel.channelId === selected}
      {@const unwatched = channel.filter.enabled
        ? (feed.unwatchedByChannel.get(channel.channelId) ?? 0)
        : 0}
      <button
        type="button"
        class="row"
        class:current
        class:off={!channel.filter.enabled}
        aria-current={current ? "page" : undefined}
        onclick={() => onselect(channel.channelId)}
      >
        <Avatar title={channel.title} thumbnail={channel.thumbnail} size={24} />
        <span class="title">{channel.title}</span>
        {#if unwatched > 0}
          <span class="count wide-only" aria-hidden="true">{unwatched}</span>
          <span class="visually-hidden">{unwatched} unwatched</span>
        {/if}
      </button>
    {/each}
    <div class="foot wide-only">
      <div class="legal">
        <a href={privacyUrl} target="_blank" rel="noopener noreferrer">
          Privacy policy
        </a>
        <a href={termsUrl} target="_blank" rel="noopener noreferrer">Terms</a>
      </div>
      <div class="attribution">
        <YouTubeAttribution />
      </div>
    </div>
  </div>
</nav>

<style>
  nav {
    height: 100%;
    /* clip, not hidden: focusing the button past the rail's edge must not scroll it */
    overflow: clip;
    background: var(--surface-raised);
    container-type: inline-size;
  }

  /*
   * Collapsed to a rail of icons. The list keeps its full width and is only
   * clipped, and nothing here changes layout, so no icon moves as it widens.
   */
  @container (max-width: 120px) {
    .wide-only,
    .title,
    h2 {
      visibility: hidden;
    }

    /* the highlight is a box around the icon, not a row running off the rail */
    .row {
      align-self: flex-start;
      width: 40px;
      overflow: hidden;
    }
  }

  .list {
    width: max(100%, 240px);
    height: 100%;
    overflow: hidden auto;
    scrollbar-gutter: stable;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 12px 8px;
  }

  .foot {
    flex-shrink: 0;
    margin-top: auto;
    padding-top: 16px;
  }

  .legal {
    display: flex;
    gap: 12px;
    padding: 0 8px;
    font-size: 12px;
  }

  .attribution {
    padding: 8px 8px 0;
  }

  .head {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin: 0 0 10px;
  }

  .home {
    padding: 4px 8px;
    border: 0;
    background: transparent;
    color: var(--text);
  }

  /* beside the name the hull sits on its line; alone in the rail all of the logo is centred */
  .home :global(img) {
    transition: translate 0.2s;
  }

  @media (prefers-reduced-motion: reduce) {
    .home :global(img) {
      transition: none;
    }
  }

  @container (max-width: 120px) {
    /* the hull's centre is 12.04% of the drawing below the whole logo's */
    .home :global(img) {
      translate: 0 12.04%;
    }
  }

  h2 {
    flex-shrink: 0;
    margin: 14px 0 4px 8px;
    font-size: 12px;
    line-height: 15px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .row {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 36px;
    padding: 4px 8px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--text);
    font-size: 14px;
    text-align: left;
  }

  .row:hover {
    background: var(--surface);
  }

  .row.current {
    background: var(--tint);
    color: var(--tint-text);
    font-weight: 500;
  }

  .row.off > :global(*) {
    opacity: 0.45;
  }

  .feed-icon {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 24px;
    color: var(--gold);
  }

  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .count {
    font-size: 12px;
    font-weight: 600;
  }
</style>
