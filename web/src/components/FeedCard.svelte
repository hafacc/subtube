<script module lang="ts">
  // the module is also loaded where the page is built, which has no window
  const NARROW = globalThis.window?.matchMedia("(max-width: 760px)");
  const REDUCED_MOTION = globalThis.window?.matchMedia(
    "(prefers-reduced-motion: reduce)",
  );
  /** How long after a swipe a click is taken as its release, in milliseconds. */
  const SWIPE_CLICK_MS = 100;
</script>

<script lang="ts">
  import { formatDuration, shortDate } from "../lib/duration";
  import { feedItemId } from "../lib/feed-item";
  import { swipeIntent, swipeOffset, swipePasses } from "../lib/swipe";
  import type { FeedItem } from "../lib/types";
  import Icon from "./Icon.svelte";

  let {
    item,
    watched,
    progress,
    playing = false,
    holdsPlayer = false,
    onopen,
    onmark,
    onopenchannel,
  }: {
    /** the video or playlist */
    item: FeedItem;
    /** whether it is watched */
    watched: boolean;
    /** how full its progress bar is, from 0 to 1; null for no bar */
    progress: number | null;
    /** whether the player is playing it, wherever the player is drawn; it then can't be marked */
    playing?: boolean;
    /** whether the player lies over the thumbnail's box, which is then left empty */
    holdsPlayer?: boolean;
    /** play it */
    onopen: () => void;
    /** mark it watched, or unmark it when it is */
    onmark: () => void;
    /** go to its channel's page */
    onopenchannel: () => void;
  } = $props();

  const titleId = $props.id();

  /** A pointer that went down on the card and may be swiping it. */
  interface Press {
    /** the pointer */
    pointerId: number;
    /** where it went down */
    downX: number;
    downY: number;
    /** where it was when it became a swipe; null until then */
    swipeX: number | null;
  }

  let press: Press | null = null;
  let swallowClick = false;
  // how far the swipe has gone, which under reduced motion is not how far the card is drawn
  let distance = $state(0);
  let offset = $state(0);
  let swiping = $state(false);
  let settling = $state(false);
  // what the swipe does, kept while the card slides back after the mark has changed
  let swipeUnmarks = $state(false);
  // whether the strip shows at the card's right edge, kept while the card slides back
  let uncoversRight = $state(false);

  const markLabel = $derived(watched ? "Mark unwatched" : "Mark watched");
  // the card's width when the swipe began
  let cardWidth = $state(0);
  const armed = $derived(swiping && swipePasses(distance, cardWidth));

  function pressed(event: PointerEvent) {
    swallowClick = false;
    if (!playing && event.isPrimary && event.button === 0 && NARROW?.matches) {
      press = {
        pointerId: event.pointerId,
        downX: event.clientX,
        downY: event.clientY,
        swipeX: null,
      };
    } else {
      press = null;
    }
  }

  function moved(event: PointerEvent & { currentTarget: HTMLElement }) {
    if (press?.pointerId !== event.pointerId) {
      return;
    }
    if (press.swipeX === null) {
      const intent = swipeIntent(
        event.clientX - press.downX,
        event.clientY - press.downY,
      );
      if (intent === "scroll") {
        press = null;
      } else if (intent === "swipe") {
        press.swipeX = event.clientX;
        cardWidth = event.currentTarget.offsetWidth;
        swipeUnmarks = watched;
        swiping = true;
        settling = false;
        event.currentTarget.setPointerCapture(event.pointerId);
        // a mouse has begun selecting the title by now
        getSelection()?.removeAllRanges();
      }
    }
    if (press !== null && press.swipeX !== null) {
      distance = swipeOffset(event.clientX - press.swipeX, cardWidth);
      offset = REDUCED_MOTION?.matches ? 0 : distance;
      uncoversRight = distance < 0;
    }
  }

  function released(event: PointerEvent, cancelled: boolean) {
    if (press?.pointerId !== event.pointerId) {
      return;
    }
    const marks =
      !cancelled && press.swipeX !== null && swipePasses(distance, cardWidth);
    if (press.swipeX !== null) {
      swallowClick = true;
      setTimeout(() => {
        swallowClick = false;
      }, SWIPE_CLICK_MS);
    }
    press = null;
    swiping = false;
    settling = offset !== 0;
    distance = 0;
    offset = 0;
    if (marks) {
      onmark();
    }
  }

  function settled(event: TransitionEvent) {
    // the bar's own transitions end inside the card too
    if (event.target === event.currentTarget) {
      settling = false;
    }
  }

  function clicked(event: MouseEvent) {
    if (swallowClick) {
      swallowClick = false;
      event.preventDefault();
      event.stopPropagation();
    }
  }

  const badge = $derived(
    item.kind === "playlist"
      ? String(item.itemCount)
      : item.durationSeconds
        ? formatDuration(item.durationSeconds)
        : null,
  );
</script>

{#snippet bar()}
  <span class="track">
    <span class="progress" style:width={`${(progress ?? 0) * 100}%`}></span>
  </span>
{/snippet}

<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events (the swipe repeats the bar button, which a keyboard reaches) -->
<div
  class="card"
  class:swiping
  data-card={feedItemId(item)}
  onpointerdown={pressed}
  onpointermove={moved}
  onpointerup={(event) => released(event, false)}
  onpointercancel={(event) => released(event, true)}
  onclickcapture={clicked}
>
  {#if swiping || settling}
    <div
      class="behind"
      class:trailing={uncoversRight}
      class:armed={armed}
      aria-hidden="true"
    >
      <Icon name={swipeUnmarks ? "eyeOff" : "eye"} size={20} />
      {swipeUnmarks ? "Mark unwatched" : "Mark watched"}
    </div>
  {/if}
  <div
    class="face"
    class:settling
    style:translate={swiping || settling ? `${offset}px 0` : undefined}
    ontransitionend={settled}
    ontransitioncancel={settled}
  >
    <div class="picture">
      {#if holdsPlayer}
        <div class="thumb" data-player-slot></div>
      {:else}
        <button
          type="button"
          class="thumb"
          aria-label={`Play ${item.title}`}
          onclick={onopen}
        >
          {#if item.thumbnail}
            <img src={item.thumbnail} alt="" loading="lazy" draggable="false">
          {/if}
          {#if item.kind === "video" && item.isShort}
            <span class="tag top-left">Short</span>
          {/if}
          {#if watched}
            <span class="tag bottom-left">Watched</span>
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
        {#if playing}
          {@render bar()}
        {:else}
          <button
            type="button"
            class="mark"
            aria-label={markLabel}
            aria-describedby={titleId}
            title={markLabel}
            onclick={onmark}
          >
            {@render bar()}
          </button>
        {/if}
      {/if}
    </div>
    <div class="text">
      <p class="title" id={titleId} title={item.title}>{item.title}</p>
      <div class="byline">
        <button type="button" class="channel" onclick={onopenchannel}>
          {item.channelTitle}
        </button>
        <span class="date">{shortDate(item.publishedAt)}</span>
      </div>
    </div>
  </div>
</div>

<style>
  .card {
    position: relative;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border-radius: 8px;
  }

  .swiping {
    user-select: none;
  }

  .face {
    position: relative;
    display: flex;
    flex: 1;
    flex-direction: column;
    background: var(--surface);
  }

  .settling {
    transition: translate 0.2s;
  }

  /* the strip a swipe uncovers, naming what releasing it does on the side that shows */
  .behind {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 16px;
    background: var(--placeholder);
    color: var(--text-secondary);
    font-size: 14px;
    font-weight: 500;
    white-space: nowrap;
    transition: color 0.15s;
  }

  .trailing {
    justify-content: flex-end;
  }

  .armed {
    color: var(--text);
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

  .picture {
    position: relative;
  }

  /* the strip along the picture's bottom edge that takes the press; the bar itself is .track */
  .mark {
    --below: 0px;
    position: absolute;
    right: 0;
    bottom: calc(-1 * var(--below));
    left: 0;
    height: 18px;
    border: 0;
    padding: 0;
    background: transparent;
    cursor: pointer;
  }

  .track {
    position: absolute;
    right: 0;
    bottom: var(--below, 0px);
    left: 0;
    height: 4px;
    transition:
      height 0.15s,
      background-color 0.15s;
  }

  .mark:focus-visible .track {
    height: 7px;
    background: color-mix(in srgb, var(--text-secondary) 60%, transparent);
  }

  /* a touch leaves :hover on what it tapped, so only a pointer that can hover gets it */
  @media (hover: hover) {
    .mark:hover .track {
      height: 7px;
      background: color-mix(in srgb, var(--text-secondary) 60%, transparent);
    }
  }

  .progress {
    display: block;
    height: 100%;
    background: var(--sunflower);
    transition: width 0.2s;
  }

  /* touch: the strip is 44px high, half over the picture and half over the text, and the card swipes sideways */
  @media (max-width: 760px) {
    .card {
      touch-action: pan-y pinch-zoom;
    }

    .mark {
      --below: 22px;
      height: 44px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .track,
    .progress,
    .behind {
      transition: none;
    }
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
