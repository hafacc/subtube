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
    covered = false,
    onended,
    ondata,
    ontoggle,
    onready,
  }: {
    /** what to play; a different item needs a new frame */
    item: RouteItem;
    /** the feed, for where to start and to save positions and marks */
    feed: PlaybackFeed;
    /** whether something lies over the player, which pauses it meanwhile */
    covered?: boolean;
    /** the item is over */
    onended: (item: RouteItem) => void;
    /** the player reported its video's title and channel */
    ondata?: (item: RouteItem, data: VideoData) => void;
    /** the user paused the video, or played it again */
    ontoggle?: () => void;
    /** the player is ready, in this frame */
    onready?: (frame: HTMLIFrameElement) => void;
  } = $props();

  /** How often the playing position is saved on this device. */
  const PROGRESS_EVERY_MS = 5000;

  // captured once: a later load or mark must not reshape or restart playback
  const opened = untrack(() => item);

  let host: HTMLDivElement;
  let playback: Playback | null = $state.raw(null);
  let loadFailed = $state(false);

  $effect(() => {
    playback?.cover(covered);
  });

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
          () => onended(opened),
          () => ontoggle?.(),
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
                onready?.(event.target.getIframe());
              }
            },
            onStateChange: (event) => {
              // before the end is passed on, which may be this frame's last moment
              const data = event.target.getVideoData();
              if (data) {
                ondata?.(opened, data);
              }
              current.stateChanged(event.data, event.target);
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

<div class="embed" bind:this={host}>
  {#if loadFailed}
    <p class="failed">
      Couldn't load the YouTube player. Check your connection or any content
      blockers, then try again.
    </p>
  {/if}
</div>

<style>
  .embed {
    position: relative;
    width: 100%;
    height: 100%;
    background: #0b0c0f;
  }

  .embed :global(iframe) {
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
    color: #abb0b9;
    font-size: 14px;
  }
</style>
