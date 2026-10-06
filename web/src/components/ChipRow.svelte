<script lang="ts">
  import type { Snippet } from "svelte";
  import { knownTopics, topicLabel } from "../lib/chips";
  import Chip from "./Chip.svelte";
  import Icon from "./Icon.svelte";

  let {
    leading,
    topics,
    selected,
    ontopic,
    onclear,
  }: {
    /** the chips before the divider */
    leading: Snippet;
    /** the topic chips' category ids, in order */
    topics: readonly string[];
    /** the selected topics' category ids */
    selected: readonly string[];
    /** called with a pressed topic chip's category id */
    ontopic: (categoryId: string) => void;
    /** called to deselect every topic */
    onclear: () => void;
  } = $props();

  let scroller: HTMLDivElement;
  // whether chips are scrolled out of sight past each edge
  let hiddenBefore = $state(false);
  let hiddenAfter = $state(false);

  function measure(): void {
    const { scrollLeft, clientWidth, scrollWidth } = scroller;
    // a zoomed page reports fractions of a pixel at either end
    hiddenBefore = scrollLeft > 1;
    hiddenAfter = scrollLeft + clientWidth < scrollWidth - 1;
  }

  $effect(() => {
    const observer = new ResizeObserver(measure);
    observer.observe(scroller);
    return () => observer.disconnect();
  });

  $effect(() => {
    // the topic chips are the only ones that come and go
    void topics.length;
    measure();
  });
</script>

<div class="chip-row">
  <div
    class="chips"
    class:hidden-before={hiddenBefore}
    class:hidden-after={hiddenAfter}
    bind:this={scroller}
    onscroll={measure}
  >
    {@render leading()}
    {#if topics.length > 0}
      <span class="divider" aria-hidden="true"></span>
      <button
        type="button"
        class="chip clear"
        aria-label="Clear topics"
        title="Clear topics"
        disabled={knownTopics(selected).size === 0}
        onclick={onclear}
      >
        <Icon name="close" size={14} />
      </button>
    {/if}
    {#each topics as categoryId (categoryId)}
      <Chip
        label={topicLabel(categoryId) ?? ""}
        pressed={selected.includes(categoryId)}
        onclick={() => ontopic(categoryId)}
      />
    {/each}
  </div>
</div>

<style>
  /* a parent sets --chip-row-rule and --chip-row-padding to fit the row in */
  .chip-row {
    flex-shrink: 0;
    min-width: 0;
    border-bottom: var(--chip-row-rule, 1px solid var(--border));
  }

  .chips {
    --fade-before: 0px;
    --fade-after: 0px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: var(--chip-row-padding, 8px 16px);
    overflow-x: auto;
    scrollbar-width: none;
    mask-image: linear-gradient(
      to right,
      transparent,
      #000 var(--fade-before),
      #000 calc(100% - var(--fade-after)),
      transparent
    );
  }

  .chips.hidden-before {
    --fade-before: 40px;
  }

  .chips.hidden-after {
    --fade-after: 40px;
  }

  .clear {
    justify-content: center;
    width: 30px;
    height: 30px;
    padding: 0;
    border-radius: 50%;
  }

  .divider {
    flex-shrink: 0;
    width: 1px;
    height: 20px;
    background: var(--border);
  }
</style>
