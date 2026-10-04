<script lang="ts">
  import { SHORTS_OPTIONS } from "../lib/channel-summary";
  import type { FeedController } from "../lib/feed.svelte";
  import { compileFilter, isValidPattern } from "../lib/filters";
  import type {
    Channel,
    ChannelFilter,
    ContentMode,
    LiveFilter,
  } from "../lib/types";
  import ChoiceRow from "./ChoiceRow.svelte";
  import PatternFields from "./PatternFields.svelte";
  import Switch from "./Switch.svelte";

  let {
    feed,
    channel,
  }: {
    /** the feed the channel belongs to */
    feed: FeedController;
    /** the channel whose filter is edited */
    channel: Channel;
  } = $props();

  const CONTENT_OPTIONS = [
    { value: "videos", label: "Uploads" },
    { value: "playlists", label: "Playlists" },
  ] as const satisfies readonly { value: ContentMode; label: string }[];
  const LIVE_OPTIONS = [
    { value: "all", label: "Show" },
    { value: "normal", label: "Hide" },
    { value: "vod", label: "Only" },
  ] as const satisfies readonly { value: LiveFilter; label: string }[];

  // the pattern as typed; saved only while it is valid
  let patternDraft = $state("");

  const filter = $derived(channel.filter);
  const isPlaylists = $derived(filter.contentMode === "playlists");
  const compiled = $derived(compileFilter(filter));
  const markAll = $derived(feed.markAllFor(channel));

  $effect(() => {
    patternDraft = channel.filter.regex;
  });

  function update(changes: Partial<ChannelFilter>): void {
    feed.updateFilter(channel.channelId, { ...channel.filter, ...changes });
  }

  function setPattern(value: string): void {
    patternDraft = value;
    if (isValidPattern(value)) {
      update({ regex: value });
    }
  }
</script>

<div class="editor">
  <div class="filter-group">
    <div class="switch-row">
      <span>Show in feed</span>
      <Switch
        checked={filter.enabled}
        label={`Show ${channel.title} in feed`}
        onchange={(enabled) => update({ enabled })}
      />
    </div>
    <ChoiceRow
      label="Show"
      options={CONTENT_OPTIONS}
      value={filter.contentMode ?? "videos"}
      onchange={(contentMode) => update({ contentMode })}
    />
  </div>

  <div class="filter-group">
    <PatternFields
      pattern={patternDraft}
      mode={compiled.mode}
      matchIn={compiled.scope}
      onpattern={setPattern}
      onmode={(mode) => update({ mode })}
      onscope={(searchScope) => update({ searchScope })}
    />
    <button
      type="button"
      class="toggle"
      aria-pressed={filter.caseSensitive === true}
      onclick={() => update({ caseSensitive: filter.caseSensitive !== true })}
    >
      Match case
    </button>
  </div>

  {#if !isPlaylists}
    <div class="filter-group">
      <ChoiceRow
        label="Shorts"
        options={SHORTS_OPTIONS}
        value={compiled.shortsFilter}
        onchange={(shortsFilter) => update({ shortsFilter })}
      />
      <ChoiceRow
        label="Live"
        options={LIVE_OPTIONS}
        value={compiled.liveFilter}
        onchange={(liveFilter) => update({ liveFilter })}
      />
      <label class="duration">
        <span>Hide videos under</span>
        <input
          type="number"
          min="0"
          placeholder="0"
          class="text-input"
          value={filter.minDurationSeconds || ""}
          oninput={(event) =>
            update({
              minDurationSeconds: Math.max(
                0,
                Math.floor(Number(event.currentTarget.value)) || 0,
              ),
            })}
        >
        seconds
      </label>
    </div>
  {/if}

  <button
    type="button"
    class="button-outline mark-all"
    disabled={markAll.ids.length === 0}
    onclick={() => feed.markAll(channel)}
  >
    {markAll.watched ? "Mark all as watched" : "Mark all as unwatched"}
  </button>
</div>

<style>
  .editor {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 12px;
  }

  .switch-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px 12px;
    font-weight: 500;
  }

  .toggle {
    padding: 6px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--page);
    font-size: 13px;
  }

  .toggle[aria-pressed="true"] {
    background: var(--sunflower);
    border-color: var(--sunflower);
    color: var(--ink);
    font-weight: 500;
  }

  .mark-all {
    justify-content: center;
    margin-top: 8px;
  }

  .duration {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .duration span {
    flex: 1;
  }

  .duration input {
    width: 72px;
    height: 34px;
    padding: 0 8px;
    text-align: right;
  }
</style>
