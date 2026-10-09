<script lang="ts">
  import { onDestroy } from "svelte";
  import { HULL, TRIANGLE } from "../lib/logo-drawing";
  import { BESIDE, LOGO_STILL, logoAt, MIDLINE } from "../lib/logo-motion";

  let {
    hull = 17.6,
    loading = false,
  }: {
    /** height of the logo's body in pixels: four fifths of the line height of the name beside it */
    hull?: number;
    /** whether the app is loading: the triangle gives way to rolling windows and the bubbles rise */
    loading?: boolean;
  } = $props();

  // the share of the square drawing that fin and body take; they are centered in it,
  // with the tower and bubbles above
  const BODY_HEIGHT = 0.4908;
  const BODY_WIDTH = 0.851;
  const SQRT3 = Math.sqrt(3);
  const framing = `translate(${BESIDE.across} ${BESIDE.down}) scale(${BESIDE.scale})`;

  const clipId = $props.id();
  const size = $derived(hull / BODY_HEIGHT);
  // the box laid out is fin and body alone, so the rest rises without moving anything
  const margin = $derived(
    `${(hull - size) / 2}px ${(size * (BODY_WIDTH - 1)) / 2}px`,
  );

  let frame = $state.raw(LOGO_STILL);
  // when the load being drawn began and ended, in milliseconds; null for none
  let began: number | null = null;
  let ended: number | null = null;
  let request = 0;

  function draw(now: number): void {
    if (began !== null) {
      const next = logoAt(
        (now - began) / 1000,
        ended === null ? null : (ended - began) / 1000,
      );
      if (next.done && loading) {
        // another load began while the last one's end played out
        began = now;
        ended = null;
        request = requestAnimationFrame(draw);
      } else if (next.done) {
        began = null;
        frame = LOGO_STILL;
      } else {
        frame = next;
        request = requestAnimationFrame(draw);
      }
    }
  }

  $effect(() => {
    const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (loading && began === null && !still) {
      began = performance.now();
      ended = null;
      request = requestAnimationFrame(draw);
    } else if (!loading && began !== null && ended === null) {
      ended = performance.now();
    }
  });

  onDestroy(() => {
    if (typeof cancelAnimationFrame === "function") {
      cancelAnimationFrame(request);
    }
  });

  const cut = $derived(frame.piece.cut * frame.piece.radius);
</script>

<svg
  class="logo"
  viewBox="0 0 24 24"
  width={size}
  height={size}
  style:margin={margin}
  aria-hidden="true"
>
  <path class="hull" d={HULL} />
  <g class="hull" transform={framing}>
    {#each frame.bubbles as bubble}
      <circle cx={bubble.x} cy={bubble.y} r={bubble.radius} />
    {/each}
  </g>
  {#if frame.triangle}
    <path d={TRIANGLE} />
  {:else}
    <g transform={framing}>
      <clipPath id={clipId}>
        <polygon
          points="{frame.piece.x + 2 * cut},{MIDLINE} {frame.piece.x -
            cut},{MIDLINE + SQRT3 * cut} {frame.piece.x - cut},{MIDLINE -
            SQRT3 * cut}"
        />
      </clipPath>
      {#each frame.windows as window}
        <circle cx={window.x} cy={MIDLINE} r={window.radius} />
      {/each}
      <circle
        cx={frame.piece.x}
        cy={MIDLINE}
        r={frame.piece.radius}
        clip-path="url(#{clipId})"
      />
    </g>
  {/if}
</svg>

<style>
  .logo {
    flex-shrink: 0;
    fill: var(--ink);
  }

  .hull {
    fill: var(--sunflower);
  }
</style>
