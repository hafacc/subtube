<script lang="ts" module>
  import type { IconName } from "./Icon.svelte";

  /** The icon that stands for each of YouTube's fifteen topics, by category id. */
  const TOPIC_ICONS: Readonly<Record<string, IconName>> = {
    "1": "clapperboard",
    "2": "car",
    "10": "music",
    "15": "paw",
    "17": "trophy",
    "19": "plane",
    "20": "gamepad",
    "22": "users",
    "23": "laugh",
    "24": "sparkles",
    "25": "newspaper",
    "26": "wrench",
    "27": "graduationCap",
    "28": "flask",
    "29": "heartHandshake",
  };

  /** How many marks fit in the rail between "Feed" and the first channel. */
  const RAIL_MARKS = 2;
</script>

<script lang="ts">
  import { Toggle } from "bits-ui";
  import {
    CHANNEL_SORT_OPTIONS,
    HeldChannelOrder,
    orderChannels,
  } from "../lib/channel-order";
  import { TIME_CHIP_OPTIONS } from "../lib/chips";
  import { privacyUrl, termsUrl } from "../lib/config";
  import type { FeedController } from "../lib/feed.svelte";
  import { chipMarks, chipTitle } from "../lib/groups";
  import Avatar from "./Avatar.svelte";
  import ChipRow from "./ChipRow.svelte";
  import CycleChip from "./CycleChip.svelte";
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
    oneditgroup,
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
    /** open the group editor: for a group by its name, or for a new one (null) */
    oneditgroup: (group: string | null) => void;
  } = $props();

  // the selected groups and topics, which take the heading's place
  const selection = $derived(
    chipTitle(
      feed.groups,
      feed.settings.channelGroupChips,
      feed.channelTopicChips,
      feed.settings.channelTopicChips,
    ),
  );

  // the same selection as the rail shows it, where the chips themselves don't fit
  const marks = $derived(
    chipMarks(
      feed.groups,
      feed.settings.channelGroupChips,
      feed.channelTopicChips,
      feed.settings.channelTopicChips,
      RAIL_MARKS,
    ),
  );

  const held = new HeldChannelOrder();
  const channels = $derived(
    held.arrange(
      orderChannels(
        Array.from(feed.channels.values()),
        feed.items,
        feed.settings.channelSort,
        feed.unwatchedByChannel,
      ),
      JSON.stringify([
        whereabouts,
        feed.loadCount,
        feed.settings.channelSort,
        feed.settings.channelTimeChip,
        feed.settings.channelTopicChips,
        feed.settings.channelGroupChips,
      ]),
      feed.chipChannels,
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
    <div class="filters">
      <div class="rail-marks" aria-hidden="true">
        {#each marks as mark, index (index)}
          <span class="mark">
            {#if mark.kind === "group"}
              {Array.from(mark.name)[0].toLocaleUpperCase()}
            {:else if mark.kind === "topic"}
              <Icon name={TOPIC_ICONS[mark.categoryId]} size={14} />
            {:else}
              +{mark.count}
            {/if}
          </span>
        {/each}
      </div>
      <div class="heading">
        <h2>
          {selection.names.length > 0 ? selection.names.join(", ") : "Channels"}
        </h2>
        {#if selection.names.length > 0}
          {#if selection.edit !== null}
            {@const group = selection.edit}
            <button
              type="button"
              class="icon-button wide-only"
              aria-label="Edit group"
              title="Edit group"
              onclick={() => oneditgroup(group)}
            >
              <Icon name="pencil" size={14} />
            </button>
          {/if}
          <button
            type="button"
            class="icon-button wide-only"
            aria-label="Clear"
            title="Clear"
            onclick={() => feed.clearChips("channels")}
          >
            <Icon name="close" size={14} />
          </button>
        {/if}
      </div>
      <div class="channel-chips wide-only">
        <ChipRow
          groups={feed.groups}
          selectedGroups={feed.settings.channelGroupChips}
          ongroup={(group) => feed.toggleChannelGroupChip(group)}
          onnewgroup={feed.loadCount > 0 ? () => oneditgroup(null) : undefined}
          topics={feed.channelTopicChips}
          selected={feed.settings.channelTopicChips}
          ontopic={(categoryId) => feed.toggleChannelTopicChip(categoryId)}
        >
          {#snippet leading()}
            <CycleChip
              label="Sort"
              options={CHANNEL_SORT_OPTIONS}
              value={feed.settings.channelSort}
              onchange={(channelSort) =>
                feed.setSetting("channelSort", channelSort)}
            />
            <CycleChip
              label="Time"
              options={TIME_CHIP_OPTIONS}
              value={feed.settings.channelTimeChip}
              onchange={(channelTimeChip) =>
                feed.setSetting("channelTimeChip", channelTimeChip)}
            />
          {/snippet}
        </ChipRow>
      </div>
    </div>
    {#if channels.length === 0 &&
      feed.chipChannels !== null &&
      feed.loadCount > 0}
      <p class="empty secondary wide-only">
        No channels for the selected filter.
      </p>
    {/if}
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

  /* the heading and the chip row, which the rail's marks are laid over */
  .filters {
    position: relative;
    flex-shrink: 0;
    min-width: 0;
  }

  .channel-chips {
    --chip-row-rule: 0;
    --chip-row-padding: 4px 8px 6px;
    margin-top: 2px;
    min-width: 0;
  }

  /* in the rows' icon column, in the room the hidden heading and chips leave */
  .rail-marks {
    visibility: hidden;
    position: absolute;
    inset: 8px auto 0 8px;
    width: 24px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    pointer-events: none;
  }

  .mark {
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--tint);
    color: var(--tint-text);
    font-size: 11px;
    font-weight: 600;
    line-height: 1;
  }

  /* after the rule that hides them, so the rail shows them */
  @container (max-width: 120px) {
    .rail-marks {
      visibility: visible;
    }
  }

  .empty {
    flex-shrink: 0;
    margin: 0;
    padding: 32px 16px;
    text-align: center;
  }

  /* as tall as the heading's line, so the buttons beside it don't move the list */
  .heading {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 2px;
    height: 15px;
    margin: 14px 0 4px 8px;
  }

  h2 {
    flex: 1;
    min-width: 0;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12px;
    line-height: 15px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .heading .icon-button {
    padding: 4px;
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
