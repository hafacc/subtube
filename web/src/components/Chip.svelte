<script lang="ts">
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

<button type="button" class="chip" aria-pressed={pressed} {onclick}>
  {label}
  {#if removes}
    <span class="remove">×</span>
  {/if}
</button>

<style>
  .remove {
    color: var(--text-secondary);
    font-size: 15px;
    line-height: 1;
  }
</style>
