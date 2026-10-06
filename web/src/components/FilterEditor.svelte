<script lang="ts">
  import {
    CASE_OPTIONS,
    CONTENT_OPTIONS,
    LIVE_OPTIONS,
    SHORTS_OPTIONS,
  } from "../lib/channel-summary";
  import { editorTopics, topicLabel } from "../lib/chips";
  import type { FeedController } from "../lib/feed.svelte";
  import { compileFilter } from "../lib/filters";
  import {
    patternToPhrases,
    phrasePatternOnly,
    phrasesToPattern,
  } from "../lib/phrases";
  import type { Channel, ChannelFilter } from "../lib/types";
  import Chip from "./Chip.svelte";
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

  const filter = $derived(channel.filter);
  const isPlaylists = $derived(filter.contentMode === "playlists");
  const compiled = $derived(compileFilter(filter));
  const phrases = $derived(
    patternToPhrases(phrasePatternOnly(filter.regex)) ?? [],
  );
  const topics = $derived(editorTopics(feed.channelFetched(channel.channelId)));

  function update(changes: Partial<ChannelFilter>): void {
    feed.updateFilter(channel.channelId, { ...channel.filter, ...changes });
  }

  function toggleTopic(categoryId: string): void {
    const selected = Array.from(compiled.topics);
    update({
      topics: compiled.topics.has(categoryId)
        ? selected.filter((other) => other !== categoryId)
        : [...selected, categoryId],
    });
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
      {phrases}
      mode={compiled.mode}
      matchIn={compiled.scope}
      onphrases={(list) => update({ regex: phrasesToPattern(list) })}
      onmode={(mode) => update({ mode })}
      onscope={(searchScope) => update({ searchScope })}
    />
    <ChoiceRow
      label="Case"
      options={CASE_OPTIONS}
      value={filter.caseSensitive === true ? "match" : "ignore"}
      onchange={(choice) => update({ caseSensitive: choice === "match" })}
    />
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

    <div class="filter-group">
      <span class="label">Topics</span>
      <div class="chips">
        {#each topics as categoryId (categoryId)}
          <Chip
            label={topicLabel(categoryId) ?? ""}
            pressed={compiled.topics.has(categoryId)}
            onclick={() => toggleTopic(categoryId)}
          />
        {/each}
      </div>
      <p class="secondary help">
        Only videos with a selected topic are shown. None selected shows all.
      </p>
    </div>
  {/if}
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

  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .label {
    font-weight: 500;
  }

  .help {
    margin: 0;
    font-size: 13px;
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
