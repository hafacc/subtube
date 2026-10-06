<script lang="ts">
  import type { Snippet } from "svelte";
  import { topicLabel } from "../lib/chips";
  import Chip from "./Chip.svelte";
  import Icon from "./Icon.svelte";

  let {
    leading,
    groups = [],
    selectedGroups = [],
    ongroup = () => undefined,
    onnewgroup = undefined,
    topics,
    selected,
    ontopic,
  }: {
    /** the chips before the divider */
    leading: Snippet;
    /** the group chips' names, in order */
    groups?: readonly string[];
    /** the selected groups' names */
    selectedGroups?: readonly string[];
    /** called with a pressed group chip's name */
    ongroup?: (group: string) => void;
    /** called by the "New group" chip; the row has that chip only when this is given */
    onnewgroup?: () => void;
    /** the topic chips' category ids, in order */
    topics: readonly string[];
    /** the selected topics' category ids */
    selected: readonly string[];
    /** called with a pressed topic chip's category id */
    ontopic: (categoryId: string) => void;
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
    // the chips that come and go
    void topics.length;
    void groups.length;
    void onnewgroup;
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
    {#if onnewgroup || groups.length > 0 || topics.length > 0}
      <span class="divider" aria-hidden="true"></span>
    {/if}
    {#if onnewgroup}
      <button
        type="button"
        class="chip new-group"
        aria-label="New group"
        title="New group"
        onclick={onnewgroup}
      >
        <Icon name="plus" size={14} />
      </button>
    {/if}
    {#each groups as group (group)}
      <Chip
        label={group}
        pressed={selectedGroups.includes(group)}
        onclick={() => ongroup(group)}
      />
    {/each}
    {#if (onnewgroup || groups.length > 0) && topics.length > 0}
      <span class="divider" aria-hidden="true"></span>
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

  .new-group {
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
