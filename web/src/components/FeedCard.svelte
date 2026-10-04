<script lang="ts">
  import { formatDuration } from "../lib/duration";
  import type { FeedItem } from "../lib/types";
  import Icon from "./Icon.svelte";

  let {
    item,
    watched,
    onopen,
    onopenchannel,
    ontogglewatched,
  }: {
    /** the video or playlist */
    item: FeedItem;
    /** whether it is marked watched (dims the card) */
    watched: boolean;
    /** play it */
    onopen: () => void;
    /** go to its channel's page */
    onopenchannel: () => void;
    /** flip its watched mark */
    ontogglewatched: () => void;
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

<div class="card" class:watched>
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
  </button>
  <div class="text">
    <p class="title" title={item.title}>{item.title}</p>
    <button type="button" class="channel" onclick={onopenchannel}>
      {item.channelTitle}
    </button>
    <div class="meta">
      <span>{DATE_FORMAT.format(new Date(item.publishedAt))}</span>
      <button
        type="button"
        class="watch"
        aria-label={watched ? "Mark as unwatched" : "Mark as watched"}
        title={watched ? "Mark as unwatched" : "Mark as watched"}
        onclick={ontogglewatched}
      >
        <Icon name={watched ? "eyeOff" : "eye"} />
      </button>
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

  .watched {
    opacity: 0.4;
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
    bottom: 4px;
    left: 4px;
    padding: 2px 6px;
  }

  .bottom-right {
    right: 4px;
    bottom: 4px;
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

  .channel {
    align-self: flex-start;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    border: 0;
    padding: 0;
    background: transparent;
    color: var(--text-secondary);
    font-size: 12px;
    text-align: left;
  }

  .channel:hover {
    color: var(--text);
    text-decoration: underline;
  }

  .meta {
    margin-top: auto;
    padding-top: 8px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: var(--text-secondary);
    font-size: 12px;
  }

  .watch {
    display: flex;
    align-items: center;
    border: 0;
    padding: 0;
    background: transparent;
    color: var(--text-secondary);
  }

  .watch:hover {
    color: var(--text);
  }
</style>
