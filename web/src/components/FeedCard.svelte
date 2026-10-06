<script lang="ts">
  import type { Snippet } from "svelte";
  import { formatDuration } from "../lib/duration";
  import { feedItemId } from "../lib/feed-item";
  import type { FeedItem } from "../lib/types";
  import Icon from "./Icon.svelte";

  let {
    item,
    watched,
    progress,
    player,
    onopen,
    onopenchannel,
  }: {
    /** the video or playlist */
    item: FeedItem;
    /** whether it is watched */
    watched: boolean;
    /** how full its progress bar is, from 0 to 1; null for no bar */
    progress: number | null;
    /** the playing video, drawn in place of the thumbnail */
    player?: Snippet;
    /** play it */
    onopen: () => void;
    /** go to its channel's page */
    onopenchannel: () => void;
  } = $props();

  const DATE_FORMAT = new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  });

  const badge = $derived(
    item.kind === "playlist"
      ? String(item.itemCount)
      : item.durationSeconds
        ? formatDuration(item.durationSeconds)
        : null,
  );
</script>

<div class="card" data-card={feedItemId(item)}>
  {#if player}
    <div class="thumb">{@render player()}</div>
  {:else}
    <button
      type="button"
      class="thumb"
      aria-label={`Play ${item.title}`}
      onclick={onopen}
    >
      {#if item.thumbnail}
        <img src={item.thumbnail} alt="" loading="lazy">
      {/if}
      {#if item.kind === "video" && item.isShort}
        <span class="tag top-left">Short</span>
      {/if}
      {#if watched}
        <span class="tag bottom-left">watched</span>
      {/if}
      {#if badge}
        <span class="tag bottom-right">
          {#if item.kind === "playlist"}
            <Icon name="playAll" size={14} />
          {/if}
          {badge}
        </span>
      {/if}
      {#if progress !== null && progress > 0}
        <span class="progress" style:width={`${progress * 100}%`}></span>
      {/if}
    </button>
  {/if}
  <div class="text">
    <p class="title" title={item.title}>{item.title}</p>
    <div class="byline">
      <button type="button" class="channel" onclick={onopenchannel}>
        {item.channelTitle}
      </button>
      <span class="date">{DATE_FORMAT.format(new Date(item.publishedAt))}</span>
    </div>
  </div>
</div>

<style>
  .card {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border-radius: 8px;
    background: var(--surface);
  }

  .thumb {
    position: relative;
    display: block;
    width: 100%;
    aspect-ratio: 16 / 9;
    border: 0;
    padding: 0;
    background: var(--placeholder);
    overflow: hidden;
  }

  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .tag {
    position: absolute;
    display: flex;
    align-items: center;
    gap: 4px;
    border-radius: 4px;
    background: rgba(0, 0, 0, 0.7);
    padding: 2px 4px;
    color: #ffffff;
    font-size: 12px;
  }

  .top-left {
    top: 4px;
    left: 4px;
  }

  .bottom-left {
    bottom: 8px;
    left: 4px;
    padding: 2px 6px;
  }

  .bottom-right {
    right: 4px;
    bottom: 8px;
  }

  .progress {
    position: absolute;
    bottom: 0;
    left: 0;
    height: 4px;
    background: var(--sunflower);
  }

  .text {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 4px;
    padding: 12px;
  }

  .title {
    margin: 0;
    font-size: 14px;
    line-height: 20px;
    font-weight: 500;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .byline {
    display: flex;
    align-items: baseline;
    gap: 8px;
    color: var(--text-secondary);
    font-size: 12px;
    line-height: 16px;
  }

  .channel {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    border: 0;
    padding: 0;
    background: transparent;
    color: inherit;
    font-size: inherit;
    line-height: inherit;
    text-align: left;
  }

  .channel:hover {
    color: var(--text);
    text-decoration: underline;
  }

  .date {
    flex-shrink: 0;
    margin-left: auto;
    white-space: nowrap;
  }
</style>
