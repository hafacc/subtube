<script lang="ts">
  import { Toggle } from "bits-ui";

  let {
    label,
    pressed = undefined,
    removes = false,
    onclick,
  }: {
    /** the chip's text */
    label: string;
    /** whether a toggle chip is selected; leave out for a chip that isn't a toggle */
    pressed?: boolean;
    /** whether pressing the chip removes it, shown by a × after the text */
    removes?: boolean;
    /** the chip was pressed */
    onclick: () => void;
  } = $props();
</script>

{#snippet content()}
  {label}
  {#if removes}
    <span class="remove" aria-hidden="true">×</span>
  {/if}
{/snippet}

{#if pressed === undefined}
  <button
    type="button"
    class="chip"
    aria-label={removes ? `Remove ${label}` : undefined}
    {onclick}
  >
    {@render content()}
  </button>
{:else}
  <Toggle.Root bind:pressed={() => pressed === true, () => onclick()}>
    {#snippet child({
      props,
    })}
      <button
        {...props}
        type="button"
        class="chip"
        aria-label={removes ? `Remove ${label}` : undefined}
      >
        {@render content()}
      </button>
    {/snippet}
  </Toggle.Root>
{/if}

<style>
  .remove {
    color: var(--text-secondary);
    font-size: 15px;
    line-height: 1;
  }
</style>
