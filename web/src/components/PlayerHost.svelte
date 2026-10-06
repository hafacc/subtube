<script lang="ts">
  import { onMount, untrack } from "svelte";
  import { prefersReducedMotion } from "svelte/motion";
  import { fade } from "svelte/transition";
  import type { FeedController } from "../lib/feed.svelte";
  import { feedItemId } from "../lib/feed-item";
  import {
    type Box,
    cardHolds,
    clipped,
    largeBox,
    MIN_PLAYER_SIDE,
    minimizedBox,
  } from "../lib/player";
  import type { PlayerController } from "../lib/player.svelte";
  import type { VideoData } from "../lib/youtube-player";
  import Icon from "./Icon.svelte";
  import PlayerFrame from "./PlayerFrame.svelte";

  let {
    player,
    feed,
    narrow,
    beside,
  }: {
    /** what is playing, and where */
    player: PlayerController;
    /** the feed, for the item's title, watched marks and playing positions */
    feed: FeedController;
    /** whether the window is narrow, where the app's panels lie over the player */
    narrow: boolean;
    /** the width of the panel open at the window's right edge, which the minimized player sits beside */
    beside: number;
  } = $props();

  /** How often what lies over the player is looked for. */
  const COVER_CHECK_MS = 250;
  /** How far inside the player's edges that is looked for. */
  const COVER_INSET = 4;

  let wrapper: HTMLElement | null = $state(null);
  let innerWidth = $state(window.innerWidth);
  let innerHeight = $state(window.innerHeight);
  // the frame around the video, shown while the last hover, click or tap was on the video; never in a card
  let framed = $state(false);
  let covered = $state(false);
  let reported = $state<{ id: string; data: VideoData } | null>(null);
  // the playing card's thumbnail box and the scrolling pane it is in
  let slot: { box: Box; view: Box } | null = $state.raw(null);
  const playing = $derived(player.playing);
  const place = $derived(playing?.place ?? null);

  const title = $derived.by(() => {
    const current = playing;
    if (current) {
      return (
        current.queue?.items.find(
          (item) => feedItemId(item) === current.item.id,
        )?.title ??
        feed.findItem(current.item.id)?.title ??
        (reported?.id === current.item.id ? reported.data.title : undefined) ??
        ""
      );
    } else {
      return "";
    }
  });

  const box: Box | null = $derived.by(() => {
    const view = { width: innerWidth, height: innerHeight };
    if (place === "large") {
      return largeBox(view);
    } else if (place === "minimized") {
      return minimizedBox(view, beside);
    } else {
      return slot?.box ?? null;
    }
  });

  // in a card the pane cuts off what scrolls out of it
  const clip = $derived.by(() => {
    const shown =
      place === "card" && slot ? clipped(slot.box, slot.view) : null;
    if (slot && shown) {
      const top = shown.top - slot.box.top;
      const bottom = slot.box.top + slot.box.height - shown.top - shown.height;
      return `inset(${top}px 0 ${bottom}px 0)`;
    } else {
      return "none";
    }
  });

  function boxOf(element: Element): Box {
    const { top, left, width, height } = element.getBoundingClientRect();
    return { top, left, width, height };
  }

  function sameBox(first: Box, second: Box): boolean {
    return (
      first.top === second.top &&
      first.left === second.left &&
      first.width === second.width &&
      first.height === second.height
    );
  }

  function measureSlot(): { box: Box; view: Box } | null {
    const element = document.querySelector("[data-player-slot]");
    const pane = element?.closest("[data-player-view]");
    if (element && pane) {
      return { box: boxOf(element), view: boxOf(pane) };
    } else {
      return null;
    }
  }

  /** The player was given to a card: scroll the card into view, or go large when the card is too small for a player. */
  function settleInCard(): void {
    const element = document.querySelector("[data-player-slot]");
    let measured = measureSlot();
    if (element && measured) {
      if (
        measured.box.width < MIN_PLAYER_SIDE ||
        measured.box.height < MIN_PLAYER_SIDE
      ) {
        player.enlarge();
      } else {
        if (!cardHolds(measured.box, measured.view)) {
          element.closest("[data-card]")?.scrollIntoView({ block: "nearest" });
          measured = measureSlot() ?? measured;
        }
        slot = measured;
      }
    } else {
      player.pageChanged();
    }
  }

  /** Keep the player on its card as the page scrolls and reflows; a card more than half out of view gives it to the corner. */
  function followCard(): void {
    const measured = measureSlot();
    if (measured && cardHolds(measured.box, measured.view)) {
      if (
        !slot ||
        !sameBox(slot.box, measured.box) ||
        !sameBox(slot.view, measured.view)
      ) {
        slot = measured;
      }
    } else {
      player.cardLost();
    }
  }

  /** Whether anything of the page lies over the part of the player that shows. */
  function isCovered(): boolean {
    const host = wrapper;
    if (!host || !box) {
      return false;
    } else {
      const screen: Box = {
        top: 0,
        left: 0,
        width: window.innerWidth,
        height: window.innerHeight,
      };
      const within =
        place === "card" && slot ? clipped(screen, slot.view) : screen;
      const shown = within ? clipped(boxOf(host), within) : null;
      if (!shown) {
        return true;
      } else {
        const lefts = [
          shown.left + COVER_INSET,
          shown.left + shown.width / 2,
          shown.left + shown.width - COVER_INSET,
        ];
        const tops = [
          shown.top + COVER_INSET,
          shown.top + shown.height / 2,
          shown.top + shown.height - COVER_INSET,
        ];
        return lefts.some((pointLeft) =>
          tops.some((pointTop) => {
            const topmost = document.elementFromPoint(pointLeft, pointTop);
            return topmost !== null && !host.contains(topmost);
          }),
        );
      }
    }
  }

  function embed(): HTMLIFrameElement | null {
    return wrapper?.querySelector("iframe") ?? null;
  }

  function showFrame(): void {
    if (place !== "card") {
      framed = true;
    }
  }

  /** Whether the keyboard's focus is on the player or one of the bar's buttons. */
  function keyboardInside(): boolean {
    const focused = document.activeElement;
    return (
      wrapper !== null &&
      focused !== null &&
      focused !== embed() &&
      wrapper.contains(focused) &&
      focused.matches(":focus-visible")
    );
  }

  // the embed keeps its focus, and with it YouTube's keyboard shortcuts
  function hideFrame(): void {
    if (!keyboardInside()) {
      framed = false;
    }
  }

  function focusMoved(): void {
    if (keyboardInside()) {
      showFrame();
    }
  }

  function focusLeft(event: FocusEvent): void {
    const next = event.relatedTarget;
    const stays = next instanceof Node && wrapper?.contains(next) === true;
    if (!stays && !wrapper?.querySelector("[data-player-video]:hover")) {
      framed = false;
    }
  }

  function pointed(event: PointerEvent): void {
    const target = event.target;
    if (wrapper && target instanceof Node && wrapper.contains(target)) {
      if (target instanceof Element && target.closest("[data-player-video]")) {
        showFrame();
      }
    } else {
      hideFrame();
    }
  }

  // a click inside the embed never reaches this page, but the first one takes
  // focus from the window; a later one follows a hover or toggles the video
  function windowBlurred(): void {
    setTimeout(() => {
      const frame = embed();
      if (frame && document.activeElement === frame) {
        showFrame();
      }
    });
  }

  function keyed(event: KeyboardEvent): void {
    if (
      event.key === "Escape" &&
      place === "large" &&
      !event.defaultPrevented
    ) {
      event.preventDefault();
      player.minimize();
    }
  }

  function embedReady(frame: HTMLIFrameElement): void {
    if (place === "card") {
      // so the player's keyboard shortcuts work without a click first
      frame.focus({ preventScroll: true });
    }
  }

  onMount(() => {
    const scrolled = () => hideFrame();
    document.addEventListener("pointerover", pointed, true);
    document.addEventListener("pointerdown", pointed, true);
    document.addEventListener("scroll", scrolled, true);
    const coverTimer = setInterval(() => {
      covered = player.playing !== null && isCovered();
    }, COVER_CHECK_MS);
    return () => {
      document.removeEventListener("pointerover", pointed, true);
      document.removeEventListener("pointerdown", pointed, true);
      document.removeEventListener("scroll", scrolled, true);
      clearInterval(coverTimer);
    };
  });

  $effect(() => {
    const inCard = place === "card";
    void playing?.item.id;
    if (inCard) {
      untrack(settleInCard);
      let frame = requestAnimationFrame(function follow() {
        if (untrack(() => player.playing?.place) === "card") {
          followCard();
          frame = requestAnimationFrame(follow);
        }
      });
      return () => cancelAnimationFrame(frame);
    } else {
      slot = null;
    }
  });

  // the player moved from under the pointer, or is gone; before the next effect, whose focus may show the frame
  $effect(() => {
    void place;
    framed = false;
    if (place === null) {
      covered = false;
    }
  });

  // Escape reaches the page only from outside the embed, so the large player takes focus itself
  $effect(() => {
    if (place === "large") {
      wrapper?.focus({ preventScroll: true });
    }
  });
</script>

<svelte:window
  bind:innerWidth
  bind:innerHeight
  onblur={windowBlurred}
  onkeydown={keyed}
/>

{#if playing}
  {#if place === "large"}
    <button
      type="button"
      class="dim"
      tabindex="-1"
      aria-label="Minimize"
      onclick={() => player.minimize()}
    ></button>
  {/if}
  <!-- svelte-ignore a11y_no_noninteractive_tabindex: Tab stops on the player to show the bar, whose buttons come next -->
  <!-- biome-ignore lint/a11y/useAriaPropsSupportedByRole: aria-modal is set only with the dialog role -->
  <section
    bind:this={wrapper}
    class="player"
    class:framed
    class:large={place === "large"}
    class:card={place === "card"}
    class:under={narrow && place !== "large"}
    class:unplaced={box === null}
    role={place === "large" ? "dialog" : undefined}
    aria-modal={place === "large" ? "true" : undefined}
    aria-label={title || "Player"}
    tabindex={place === "card" ? -1 : 0}
    onfocusin={focusMoved}
    onfocusout={focusLeft}
    style:top={box ? `${box.top}px` : undefined}
    style:left={box ? `${box.left}px` : undefined}
    style:width={box ? `${box.width}px` : undefined}
    style:height={box ? `${box.height}px` : undefined}
    style:clip-path={clip}
  >
    {#if framed}
      <div
        class="frame"
        transition:fade={{ duration: prefersReducedMotion.current ? 0 : 150 }}
      >
        <div class="bar">
          <span class="title">{title}</span>
          {#if place === "minimized"}
            <button
              type="button"
              class="icon-button"
              aria-label="Expand"
              title="Expand"
              onclick={() => player.expand()}
            >
              <Icon name="expand" />
            </button>
          {:else}
            <button
              type="button"
              class="icon-button"
              aria-label="Minimize"
              title="Minimize"
              onclick={() => player.minimize()}
            >
              <Icon name="minimize" />
            </button>
          {/if}
          <button
            type="button"
            class="icon-button"
            aria-label="Close"
            title="Close"
            onclick={() => player.close()}
          >
            <Icon name="close" />
          </button>
        </div>
      </div>
    {/if}
    <div class="video" data-player-video>
      {#key `${playing.item.kind}:${playing.item.id}`}
        <PlayerFrame
          item={playing.item}
          {feed}
          {covered}
          onended={(item) => player.ended(item.id)}
          ondata={(item, data) => {
            reported = { id: item.id, data };
          }}
          ontoggle={showFrame}
          onready={embedReady}
        />
      {/key}
    </div>
  </section>
{/if}

<style>
  .dim {
    position: fixed;
    inset: 0;
    z-index: 29;
    padding: 0;
    border: 0;
    background: var(--scrim-strong);
    cursor: default;
  }

  /* exactly the video's box: the frame is drawn outside it, so the video never moves or resizes */
  .player {
    position: fixed;
    z-index: 30;
    outline: none;
    transition:
      top 0.2s,
      left 0.2s,
      width 0.2s,
      height 0.2s;
  }

  /* in a narrow window the channel list, the details panel and Settings open over it */
  .player.under {
    z-index: 11;
  }

  .player.card {
    transition: none;
  }

  .player.unplaced {
    visibility: hidden;
  }

  .video {
    position: absolute;
    inset: 0;
    overflow: hidden;
    border-radius: 8px;
    background: #0e0c08;
    box-shadow: 0 8px 32px var(--shadow);
  }

  .large .video {
    box-shadow: 0 16px 64px var(--shadow);
  }

  .card .video {
    border-radius: 8px 8px 0 0;
    box-shadow: none;
  }

  .framed .video {
    border-radius: 0 0 7px 7px;
    box-shadow: none;
  }

  .frame {
    position: absolute;
    inset: -37px -1px -1px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--page);
    box-shadow: 0 8px 32px var(--shadow);
  }

  .large .frame {
    box-shadow: 0 16px 64px var(--shadow);
  }

  /* the player itself has no ring: the frame it brings up carries it */
  .player:focus-visible .frame {
    outline: 2px solid var(--gold);
    outline-offset: 2px;
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 2px;
    height: 36px;
    padding: 0 4px 0 12px;
  }

  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
    font-weight: 500;
  }

  @media (prefers-reduced-motion: reduce) {
    .player {
      transition: none;
    }
  }
</style>
