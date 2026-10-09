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
  import type { Channel, ChannelFilter, FilterScope } from "../lib/types";
  import Avatar from "./Avatar.svelte";
  import Chip from "./Chip.svelte";
  import ChoiceRow from "./ChoiceRow.svelte";
  import Icon from "./Icon.svelte";
  import PatternFields from "./PatternFields.svelte";
  import Switch from "./Switch.svelte";

  let {
    feed,
    channel,
    onclose,
  }: {
    /** the feed the channel belongs to */
    feed: FeedController;
    /** the channel whose filter is edited */
    channel: Channel;
    /** called when the × is pressed */
    onclose: () => void;
  } = $props();

  const PHRASES_HEADING: Record<FilterScope, string> = {
    title: "Title phrases",
    both: "Text phrases",
    description: "Description phrases",
  };

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

<header>
  <Avatar title={channel.title} thumbnail={channel.thumbnail} size={36} />
  <div class="names">
    <h2>{channel.title}</h2>
    <span class="secondary">Subscribed on YouTube</span>
  </div>
  <button
    type="button"
    class="close"
    aria-label="Close"
    title="Close"
    onclick={onclose}
  >
    <Icon name="close" size={12} strokeWidth={2.5} />
  </button>
</header>

<div class="editor">
  <div class="card">
    <div class="row lead">
      <span>Show in feed</span>
      <Switch
        checked={filter.enabled}
        label={`Show ${channel.title} in feed`}
        onchange={(enabled) => update({ enabled })}
      />
    </div>
  </div>

  <section>
    <h3>Videos</h3>
    <div class="card">
      <ChoiceRow
        label="Show"
        options={CONTENT_OPTIONS}
        value={filter.contentMode ?? "videos"}
        onchange={(contentMode) => update({ contentMode })}
      />
      {#if !isPlaylists}
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
        <label class="row duration">
          <span>Hide videos under</span>
          <input
            type="number"
            min="0"
            placeholder="0"
            class="text-input"
            value={filter.minDurationSeconds || ""}
            onchange={(event) =>
              update({
                minDurationSeconds: Math.max(
                  0,
                  Math.floor(Number(event.currentTarget.value)) || 0,
                ),
              })}
          >
          <span class="secondary">seconds</span>
        </label>
      {/if}
    </div>
  </section>

  <section>
    <h3>
      <label for="filter-phrase">{PHRASES_HEADING[compiled.scope]}</label>
    </h3>
    <div class="card">
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
  </section>

  {#if !isPlaylists}
    <section>
      <h3>Topics</h3>
      <div class="card">
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
    </section>
  {/if}
</div>

<style>
  header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 12px 12px;
  }

  .names {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
    font-size: 13px;
  }

  h2 {
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 17px;
    line-height: 22px;
    font-weight: 700;
  }

  .close {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 50%;
    background: transparent;
    color: var(--text-secondary);
  }

  .close:hover {
    background: var(--surface);
  }

  .editor {
    display: flex;
    flex-direction: column;
    padding: 0 12px;
    font-size: 14px;
  }

  h3 {
    margin: 16px 0 6px 12px;
    font-size: 13px;
    line-height: 16px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  /* a quiet rounded fill around related rows, with no lines between them */
  .card {
    display: flex;
    flex-direction: column;
    padding: 4px 12px;
    border-radius: 10px;
    background: var(--surface);
  }

  .card > :global(.row),
  .row {
    min-height: 36px;
    padding: 3px 0;
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px 12px;
  }

  .lead {
    font-weight: 600;
  }

  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding-top: 8px;
  }

  .help {
    margin: 8px 0;
    font-size: 13px;
  }

  .duration {
    justify-content: flex-start;
    gap: 6px;
  }

  .duration > :first-child {
    flex: 1;
  }

  .duration input {
    width: 56px;
    height: 30px;
    padding: 0 8px;
    text-align: right;
  }
</style>
