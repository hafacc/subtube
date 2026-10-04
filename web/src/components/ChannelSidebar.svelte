<script lang="ts">
  import { orderChannels } from "../lib/channel-order";
  import { privacyUrl } from "../lib/config";
  import type { FeedController } from "../lib/feed.svelte";
  import Avatar from "./Avatar.svelte";
  import Icon from "./Icon.svelte";
  import Logo from "./Logo.svelte";

  let {
    feed,
    selected,
    onselect,
    collapsed,
    ontoggle,
  }: {
    /** the feed whose channels these are */
    feed: FeedController;
    /** the channel whose page is open, or null for the feed */
    selected: string | null;
    /** open the feed (null) or a channel's page */
    onselect: (channelId: string | null) => void;
    /** whether the sidebar is collapsed to its icons, widening only on hover */
    collapsed: boolean;
    /** collapse the sidebar, or pin it open */
    ontoggle: () => void;
  } = $props();

  const channels = $derived(
    orderChannels(Array.from(feed.channels.values()), feed.items),
  );
</script>

<nav aria-label="Channels">
  <div class="list">
    <div class="head">
      <button type="button" class="brand home" onclick={() => onselect(null)}>
        <Logo />
        <span class="wide-only">SubTube</span>
      </button>
      <button
        type="button"
        class="icon-button"
        aria-label="Channels"
        title="Channels"
        aria-expanded={!collapsed}
        aria-pressed={!collapsed}
        onclick={ontoggle}
      >
        <Icon name="sidebarLeft" />
      </button>
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
      </button>
    {/each}
    <a
      class="privacy wide-only"
      href={privacyUrl}
      target="_blank"
      rel="noopener noreferrer"
    >
      Privacy policy
    </a>
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

  .privacy {
    flex-shrink: 0;
    margin-top: auto;
    padding: 16px 8px 0;
    font-size: 12px;
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

  h2 {
    margin: 14px 8px 4px;
    font-size: 12px;
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
