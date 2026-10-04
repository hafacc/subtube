<script lang="ts">
  import { onMount, untrack } from "svelte";
  import { formatDuration, videoCount } from "../lib/duration";
  import type { FeedController } from "../lib/feed.svelte";
  import type { RouteItem } from "../lib/router";
  import type { FeedItem } from "../lib/types";
  import {
    loadIframeApi,
    type VideoData,
    type YouTubePlayer,
  } from "../lib/youtube-player";
  import Icon from "./Icon.svelte";
  import Logo from "./Logo.svelte";

  let {
    item,
    feed,
    onclose,
    onopenchannel,
  }: {
    /** what to play */
    item: RouteItem;
    /** the feed, for item details and watched marks */
    feed: FeedController;
    /** leave the player */
    onclose: () => void;
    /** go to a channel's page */
    onopenchannel: (channelId: string) => void;
  } = $props();

  const DATE_FORMAT = new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  });

  // Captured once: a later load or a mark made while playing must not reshape
  // or restart playback. Opening something else mounts a new player.
  const opened = untrack(() => item);
  const kind: "video" | "playlist" =
    opened.kind === "playlist" ? "playlist" : "video";
  const playlistId = opened.kind === "playlist" ? opened.id : "";
  const videoIds = opened.kind === "video" ? [opened.id] : [];

  let host: HTMLDivElement;
  let player: YouTubePlayer | null = null;
  let loadFailed = $state(false);
  let currentVideoId = $state<string | null>(videoIds[0] ?? null);
  let videoData = $state<VideoData | null>(null);
  // marks taken off by hand here; leaving doesn't put them back
  const unmarked = new Set<string>();

  const entry: FeedItem | undefined = $derived.by(() => {
    return feed.findItem(opened.id);
  });

  const markTarget: string | null = $derived.by(() => {
    if (opened.kind === "playlist") {
      return playlistId;
    } else {
      return currentVideoId;
    }
  });

  const markedWatched = $derived(
    markTarget !== null && feed.watched.has(markTarget),
  );

  const title = $derived(entry?.title ?? videoData?.title ?? "");
  const channelTitle = $derived(entry?.channelTitle ?? videoData?.author ?? "");
  const meta = $derived.by(() => {
    if (!entry) {
      return "";
    }
    const parts = ["", DATE_FORMAT.format(new Date(entry.publishedAt))];
    if (entry.kind === "playlist") {
      parts.push(videoCount(entry.itemCount));
    } else if (entry.durationSeconds) {
      parts.push(formatDuration(entry.durationSeconds));
    }
    return parts.join(" · ");
  });

  const youtubeUrl = $derived(
    opened.kind === "playlist"
      ? `https://www.youtube.com/playlist?list=${encodeURIComponent(playlistId)}`
      : `https://www.youtube.com/watch?v=${encodeURIComponent(currentVideoId ?? "")}`,
  );

  function leave(videoId: string): void {
    if (!unmarked.has(videoId) && !feed.watched.has(videoId)) {
      feed.setWatched(videoId, true);
    }
  }

  function toggleMark(): void {
    if (markTarget === null) {
      return;
    } else if (markedWatched) {
      unmarked.add(markTarget);
      feed.setWatched(markTarget, false);
    } else {
      unmarked.delete(markTarget);
      feed.setWatched(markTarget, true);
    }
  }

  onMount(() => {
    let cancelled = false;
    // whether playback ever started; a bare open marks nothing
    let started = false;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onclose();
      }
    };
    window.addEventListener("keydown", onKeyDown);

    loadIframeApi()
      .then((namespace) => {
        if (cancelled) {
          return;
        }
        const element = document.createElement("div");
        host.appendChild(element);
        player = new namespace.Player(element, {
          width: "100%",
          height: "100%",
          // a video list is loaded in onReady: combining videoId with the
          // `playlist` param drops the first id
          playerVars:
            kind === "playlist"
              ? { autoplay: 1, rel: 0, listType: "playlist", list: playlistId }
              : { rel: 0 },
          events: {
            onReady: (event) => {
              if (cancelled) {
                return;
              }
              if (kind === "video") {
                event.target.loadPlaylist(videoIds, 0);
              }
              // so the player's keyboard shortcuts work without a click first
              event.target.getIframe().focus({ preventScroll: true });
            },
            onStateChange: (event) => {
              if (event.data === namespace.PlayerState.PLAYING) {
                started = true;
              }
              videoData = event.target.getVideoData();
              if (kind === "playlist") {
                // a real playlist is marked once its last video ends; the
                // player's own list already skips unavailable videos
                const loaded = event.target.getPlaylist();
                if (
                  event.data === namespace.PlayerState.ENDED &&
                  loaded &&
                  event.target.getPlaylistIndex() === loaded.length - 1 &&
                  !unmarked.has(playlistId)
                ) {
                  feed.setWatched(playlistId, true);
                }
                return;
              }
              const nextId = videoData?.video_id;
              if (nextId && nextId !== currentVideoId) {
                if (currentVideoId && started) {
                  leave(currentVideoId);
                }
                currentVideoId = nextId;
              }
            },
          },
        });
      })
      .catch(() => {
        if (!cancelled) {
          loadFailed = true;
        }
      });

    return () => {
      cancelled = true;
      if (started && kind === "video" && currentVideoId) {
        leave(currentVideoId);
      }
      player?.destroy();
      window.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  });
</script>

<div class="player-page" role="dialog" aria-label={title || "Player"}>
  <header>
    <button
      type="button"
      class="icon-button"
      aria-label="Close player"
      onclick={onclose}
    >
      <Icon name="back" />
    </button>
    <span class="brand"><Logo /> SubTube</span>
  </header>

  <main>
    <div class="video" bind:this={host}>
      {#if loadFailed}
        <p class="failed">
          Couldn't load the YouTube player. Check your connection or any content
          blockers, then close and reopen.
        </p>
      {/if}
    </div>

    <div class="details">
      <div class="heading">
        <h1>{title}</h1>
        <p class="secondary">
          {#if entry}
            <a
              href={`?channel=${encodeURIComponent(entry.channelId)}`}
              onclick={(event) => {
                event.preventDefault();
                if (entry) {
                  onopenchannel(entry.channelId);
                }
              }}
              >{channelTitle}</a
            >
          {:else}
            {channelTitle}
          {/if}
          {meta}
        </p>
      </div>
      <div class="actions">
        <button
          type="button"
          class="button-outline"
          disabled={markTarget === null}
          onclick={toggleMark}
        >
          <Icon name={markedWatched ? "eyeOff" : "eye"} />
          {markedWatched ? "Mark unwatched" : "Mark watched"}
        </button>
        <a
          class="button-outline"
          href={youtubeUrl}
          target="_blank"
          rel="noopener noreferrer"
        >
          <Icon name="external" />
          Open on YouTube
        </a>
        {#if opened.kind === "playlist"}
          <button
            type="button"
            class="button-small"
            onclick={() => player?.nextVideo()}
          >
            Next
            <Icon name="next" />
          </button>
        {/if}
      </div>
    </div>
  </main>
</div>

<style>
  .player-page {
    position: fixed;
    inset: 0;
    z-index: 30;
    overflow-y: auto;
    background: var(--page);
  }

  header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
  }

  main {
    max-width: 960px;
    margin: 0 auto;
    padding: 24px 16px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .video {
    position: relative;
    width: 100%;
    aspect-ratio: 16 / 9;
    border-radius: 8px;
    overflow: hidden;
    background: #0e0c08;
  }

  .video :global(iframe) {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border: 0;
  }

  .failed {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    margin: 0;
    padding: 24px;
    text-align: center;
    color: #b5ae9e;
    font-size: 14px;
  }

  .details {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    gap: 12px;
  }

  .heading {
    flex: 1 1 400px;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  h1 {
    margin: 0;
    font-size: 20px;
    line-height: 28px;
    font-weight: 600;
  }

  .heading p {
    margin: 0;
    font-size: 14px;
  }

  .heading a {
    color: var(--text-secondary);
    text-decoration: none;
  }

  .heading a:hover {
    color: var(--text);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
</style>
