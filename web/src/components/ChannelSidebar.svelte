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
    filtersChannel,
    onselect,
    onfilters,
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
    /** the channel whose filters the details panel shows, or null */
    filtersChannel: string | null;
    /** a row was clicked: the feed (null) or a channel; the current one again refreshes */
    onselect: (channelId: string | null) => void;
    /** a row's filters button was clicked: open that channel's filters, or close them when they show */
    onfilters: (channelId: string) => void;
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
        <Logo loading={feed.loading} />
        <span class="wide-only">SubTube</span>
      </button>
      <Toggle.Root
        aria-label={collapsed ? "Show channels" : "Hide channels"}
        title={collapsed ? "Show channels" : "Hide channels"}
        aria-expanded={!collapsed}
        bind:pressed={() => !collapsed, () => ontoggle()}
      >
        {#snippet child({
          props,
        })}
          <button {...props} type="button" class="icon-button">
            <Icon name="channels" />
          </button>
        {/snippet}
      </Toggle.Root>
    </div>
    <div class="row feed" class:current={selected === null}>
      <button
        type="button"
        class="go"
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
    </div>
    <h2>Channels</h2>
    {#each channels as channel (channel.channelId)}
      {@const current = channel.channelId === selected}
      {@const unwatched = channel.filter.enabled
        ? (feed.unwatchedByChannel.get(channel.channelId) ?? 0)
        : 0}
      <div class="row" class:current class:off={!channel.filter.enabled}>
        <button
          type="button"
          class="go"
          aria-current={current ? "page" : undefined}
          onclick={() => onselect(channel.channelId)}
        >
          <Avatar
            title={channel.title}
            thumbnail={channel.thumbnail}
            size={24}
          />
          <span class="names">
            <span class="title">{channel.title}</span>
            {#if !channel.filter.enabled}
              <span class="detail">Off</span>
            {:else if unwatched > 0}
              <span class="detail">{unwatched} unwatched</span>
            {/if}
          </span>
        </button>
        <button
          type="button"
          class="filters wide-only"
          class:shown={channel.channelId === filtersChannel}
          aria-label={`Filters for ${channel.title}`}
          title="Filters"
          aria-expanded={channel.channelId === filtersChannel}
          onclick={() => onfilters(channel.channelId)}
        >
          <Icon name="filterLines" />
        </button>
      </div>
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
    .names,
    .feed .title,
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

  /* beside the name the body sits on its line; alone in the rail all of the logo is centered */
  .home :global(.logo) {
    transition: translate 0.2s;
  }

  @media (prefers-reduced-motion: reduce) {
    .home :global(.logo) {
      transition: none;
    }
  }

  @container (max-width: 120px) {
    /* the body's center is 12.07% of the drawing below the whole logo's */
    .home :global(.logo) {
      translate: 0 12.07%;
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
    position: relative;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    height: 44px;
    border-radius: 8px;
    color: var(--text);
    font-size: 14px;
  }

  .row.feed {
    height: 36px;
  }

  .row:hover {
    background: var(--surface);
  }

  .row.current {
    background: var(--sunflower);
    color: var(--ink);
  }

  .go {
    flex: 1;
    min-width: 0;
    align-self: stretch;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 8px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
  }

  .row.off > .go > :global(*) {
    opacity: 0.45;
  }

  .names {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .detail {
    font-size: 12px;
    line-height: 15px;
    color: var(--text-secondary);
  }

  .row.current .detail {
    color: var(--ink);
  }

  /* drawn only for the row under the pointer, the keyboard's, the open page's and the one whose filters show */
  .filters {
    position: absolute;
    top: 8px;
    right: 6px;
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    padding: 0;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--text-secondary);
    opacity: 0;
  }

  .row:hover > .filters,
  .row.current > .filters,
  .filters.shown,
  .row:has(:focus-visible) > .filters {
    opacity: 1;
  }

  /* the name gives the button room only while it is drawn */
  .row:hover > .go,
  .row.current > .go,
  .row:has(:focus-visible) > .go,
  .row:has(.filters.shown) > .go {
    padding-right: 40px;
  }

  .filters:hover {
    background: var(--border);
  }

  .row.current > .filters {
    color: var(--ink);
  }

  .row.current > .filters:hover {
    background: rgb(0 0 0 / 0.1);
  }

  /* a touch screen has no pointer to be under */
  @media (hover: none) {
    .filters {
      opacity: 1;
    }

    .row:not(.feed) > .go {
      padding-right: 40px;
    }
  }

  .feed-icon {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 24px;
    color: var(--gold);
  }

  .row.current .feed-icon {
    color: var(--ink);
  }

  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .names .title {
    font-weight: 500;
  }

  .count {
    font-size: 12px;
    font-weight: 600;
  }
</style>
