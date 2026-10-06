<script lang="ts">
  import { onMount, untrack } from "svelte";
  import { Playback, type PlaybackFeed } from "../lib/playback";
  import type { RouteItem } from "../lib/router";
  import {
    loadIframeApi,
    type VideoData,
    type YouTubePlayer,
  } from "../lib/youtube-player";

  let {
    item,
    feed,
    focusPlayer = false,
    onended,
    ondata,
  }: {
    /** what to play; a different item needs a new frame */
    item: RouteItem;
    /** the feed, for where to start and to save positions and marks */
    feed: PlaybackFeed;
    /** whether the player takes keyboard focus once it is ready */
    focusPlayer?: boolean;
    /** the item is over */
    onended: () => void;
    /** the player reported its video's title and channel */
    ondata?: (data: VideoData) => void;
  } = $props();

  /** How often the playing position is saved on this device. */
  const PROGRESS_EVERY_MS = 5000;

  // captured once: a later load or mark must not reshape or restart playback
  const opened = untrack(() => item);

  let host: HTMLDivElement;
  let playback: Playback | null = null;
  let loadFailed = $state(false);

  onMount(() => {
    let cancelled = false;
    let player: YouTubePlayer | null = null;
    const onVisibility = () => {
      if (document.visibilityState === "hidden") {
        playback?.save("now");
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    const progressTimer = setInterval(
      () => playback?.tick(),
      PROGRESS_EVERY_MS,
    );

    loadIframeApi()
      .then((namespace) => {
        if (cancelled) {
          return;
        }
        const current = new Playback(
          opened,
          feed,
          namespace.PlayerState,
          onended,
        );
        playback = current;
        const element = document.createElement("div");
        host.appendChild(element);
        player = new namespace.Player(element, {
          width: "100%",
          height: "100%",
          playerVars: current.playerVars,
          events: {
            onReady: (event) => {
              if (!cancelled) {
                current.ready(event.target);
                if (focusPlayer) {
                  // so the player's keyboard shortcuts work without a click first
                  event.target.getIframe().focus({ preventScroll: true });
                }
              }
            },
            onStateChange: (event) => {
              current.stateChanged(event.data, event.target);
              if (current.videoData) {
                ondata?.(current.videoData);
              }
            },
          },
        });
        // read when the frame's page loads, so it must be set before then
        player.getIframe().allowFullscreen = true;
      })
      .catch(() => {
        if (!cancelled) {
          loadFailed = true;
        }
      });

    return () => {
      cancelled = true;
      clearInterval(progressTimer);
      playback?.save("soon");
      player?.destroy();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  });
</script>

<div class="video" bind:this={host}>
  {#if loadFailed}
    <p class="failed">
      Couldn't load the YouTube player. Check your connection or any content
      blockers, then try again.
    </p>
  {/if}
</div>

<style>
  .video {
    position: relative;
    width: 100%;
    aspect-ratio: 16 / 9;
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
</style>
