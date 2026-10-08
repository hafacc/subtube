<script lang="ts">
  import { Popover } from "bits-ui";
  import { TIME_CHIP_OPTIONS } from "../lib/chips";
  import type { FeedController } from "../lib/feed.svelte";
  import { FEED_SORT_CHIPS, type FeedSort } from "../lib/feed-order";
  import { DEFAULT_SETTINGS } from "../lib/settings";
  import {
    DEFAULT_WATCHED_MODE,
    WATCHED_MODE_OPTIONS,
  } from "../lib/watched-mode";
  import Chip from "./Chip.svelte";
  import CycleChip from "./CycleChip.svelte";
  import Icon from "./Icon.svelte";

  let {
    feed,
  }: {
    /** the feed whose order and filters the menu sets */
    feed: FeedController;
  } = $props();

  let open = $state(false);
  // the order each sort chip showed when another chip took over, by the chip's place in the row
  let lastShown: Record<number, FeedSort> = $state({});

  const sort = $derived(feed.settings.feedSort);
  const activeChip = $derived(
    FEED_SORT_CHIPS.findIndex((options) =>
      options.some((option) => option.value === sort),
    ),
  );
  const timeNarrows = $derived(
    feed.settings.timeChip !== DEFAULT_SETTINGS.timeChip,
  );
  const watchedNarrows = $derived(feed.watchedMode !== DEFAULT_WATCHED_MODE);

  /** The order the sort chip at `index` shows. */
  function shownSort(index: number): FeedSort {
    if (index === activeChip) {
      return sort;
    } else {
      return lastShown[index] ?? FEED_SORT_CHIPS[index][0].value;
    }
  }

  /** A sort chip was pressed for `next`; the active order again means Random asking for another shuffle. */
  function choose(next: FeedSort): void {
    if (next === sort) {
      feed.reshuffle();
    } else {
      lastShown[activeChip] = sort;
      feed.setSetting("feedSort", next);
    }
  }
</script>

<Popover.Root bind:open>
  <Popover.Trigger aria-label="Sort and filter">
    {#snippet child({
      props,
    })}
      <button
        {...props}
        type="button"
        class="chip round trigger"
        class:filled={timeNarrows || watchedNarrows}
        class:open
        title="Sort and filter"
      >
        <Icon name="sliders" size={14} />
      </button>
    {/snippet}
  </Popover.Trigger>
  <Popover.ContentStatic trapFocus={false}>
    {#snippet child({
      props,
    })}
      <section
        {...props}
        class="fades menu"
        aria-label="Sort and filter"
        style:contain="none"
      >
        <div class="options">
          <Chip
            label="Auto-play"
            pressed={feed.settings.autoplay}
            onclick={() => feed.setSetting("autoplay", !feed.settings.autoplay)}
          />
          <CycleChip
            label="Time"
            options={TIME_CHIP_OPTIONS}
            value={feed.settings.timeChip}
            filled={timeNarrows}
            onchange={(timeChip) => feed.setSetting("timeChip", timeChip)}
          />
          <CycleChip
            label="Show"
            options={WATCHED_MODE_OPTIONS}
            value={feed.watchedMode}
            filled={watchedNarrows}
            onchange={(mode) => feed.setWatchedMode(mode)}
          />
        </div>
        <div class="options sorts">
          {#each FEED_SORT_CHIPS as options, index (index)}
            <CycleChip
              label="Sort"
              {options}
              value={shownSort(index)}
              pressed={index === activeChip}
              onchange={choose}
            />
          {/each}
        </div>
      </section>
    {/snippet}
  </Popover.ContentStatic>
</Popover.Root>

<style>
  .trigger {
    transition:
      background-color 0.15s,
      border-color 0.15s,
      color 0.15s,
      box-shadow 0.15s;
  }

  .trigger.open {
    box-shadow: 0 0 0 2px var(--gold);
  }

  .menu {
    position: absolute;
    top: calc(100% + 4px);
    left: 12px;
    z-index: 15;
    max-width: calc(100% - 24px);
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 12px;
    background: var(--page);
    box-shadow: 0 12px 32px var(--shadow);
  }

  .options {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .sorts {
    padding-top: 10px;
    border-top: 1px solid var(--border);
  }

  @media (prefers-reduced-motion: reduce) {
    .trigger {
      transition: none;
    }
  }
</style>
