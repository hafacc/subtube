<script lang="ts">
  import { onMount } from "svelte";
  import type { FeedController } from "../lib/feed.svelte";
  import type { RouteItem } from "../lib/router";
  import type { VideoData } from "../lib/youtube-player";
  import PlayerFrame from "./PlayerFrame.svelte";

  let {
    item,
    feed,
    onclose,
    onended,
  }: {
    /** what to play; changing it plays the new item in the same overlay */
    item: RouteItem;
    /** the feed, for the item's title, watched marks and playing positions */
    feed: FeedController;
    /** leave the player */
    onclose: () => void;
    /** the item is over */
    onended: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  let reported = $state<{ id: string; data: VideoData } | null>(null);

  const title = $derived(
    feed.findItem(item.id)?.title ??
      (reported?.id === item.id ? reported.data.title : undefined) ??
      "",
  );

  onMount(() => {
    // modal: the browser dims and disables the app behind and keeps focus inside
    dialog.showModal();
    // not the embed, which showModal picks: Escape never reaches the page from inside it
    dialog.focus();
  });
</script>

<!-- biome-ignore lint/a11y/useKeyWithClickEvents: the keyboard closes it with Escape, through the cancel event -->
<dialog
  bind:this={dialog}
  tabindex="-1"
  aria-label={title || "Player"}
  oncancel={(event) => {
    event.preventDefault();
    onclose();
  }}
  onclick={(event) => {
    // only the dimmed area around the video is the dialog element itself
    if (event.target === dialog) {
      onclose();
    }
  }}
>
  {#key `${item.kind}:${item.id}`}
    <PlayerFrame
      {item}
      {feed}
      {onended}
      ondata={(data) => {
        reported = { id: item.id, data };
      }}
    />
  {/key}
</dialog>

<style>
  dialog {
    --margin: clamp(16px, 4vw, 48px);
    /* the widest 16:9 video that fits inside the margins */
    width: min(
      100vw -
      2 *
      var(--margin),
      (100dvh - 2 * var(--margin)) *
      16 / 9
    );
    max-width: none;
    max-height: none;
    padding: 0;
    border: 0;
    border-radius: 8px;
    overflow: hidden;
    background: transparent;
    box-shadow: 0 16px 64px var(--shadow);
    outline: none;
  }

  dialog::backdrop {
    background: var(--scrim-strong);
  }
</style>
