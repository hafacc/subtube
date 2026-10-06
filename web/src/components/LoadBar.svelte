<script lang="ts">
  import { Progress } from "bits-ui";
  import { untrack } from "svelte";

  let {
    progress,
    labelledby,
  }: {
    /** how far the running load has come, from 0 to 1; null when none runs */
    progress: number | null;
    /** id of the element that names what is loading */
    labelledby: string;
  } = $props();

  // the fill's 0.2s to reach the end, then the 0.3s fade
  const LEAVE_MS = 500;

  // what the bar shows: the load's progress, then full while it fades out
  let shown: number | null = $state(null);
  let leaving = $state(false);

  $effect(() => {
    if (progress !== null) {
      shown = progress;
      leaving = false;
      return undefined;
    } else if (untrack(() => shown) !== null) {
      shown = 1;
      leaving = true;
      const timer = setTimeout(() => {
        shown = null;
        leaving = false;
      }, LEAVE_MS);
      return () => clearTimeout(timer);
    } else {
      return undefined;
    }
  });
</script>

{#if shown !== null}
  <Progress.Root value={Math.round(shown * 100)} aria-labelledby={labelledby}>
    {#snippet child({
      props,
    })}
      <div {...props} class="load-bar" class:leaving={leaving}>
        <div
          class="fill"
          style:width={`${shown === null ? 0 : shown * 100}%`}
        ></div>
      </div>
    {/snippet}
  </Progress.Root>
{/if}

<style>
  .load-bar {
    position: absolute;
    top: 0;
    right: 0;
    left: 0;
    z-index: 1;
    height: 3px;
    pointer-events: none;
  }

  .load-bar.leaving {
    opacity: 0;
    transition: opacity 0.3s 0.2s;
  }

  .fill {
    height: 100%;
    background: var(--sunflower);
    transition: width 0.2s ease-out;
  }

  @media (prefers-reduced-motion: reduce) {
    .fill {
      transition: none;
    }
  }
</style>
