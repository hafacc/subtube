<script lang="ts" generics="Value extends string">
  import Segmented from "./Segmented.svelte";

  let {
    label,
    options,
    value,
    onchange,
  }: {
    /** what is being chosen, shown beside the buttons */
    label: string;
    /** the choices, in order */
    options: readonly { value: Value; label: string }[];
    /** the chosen one */
    value: Value;
    /** called with a new choice */
    onchange: (value: Value) => void;
  } = $props();
</script>

<div class="row">
  <span>{label}</span>
  <Segmented {label} {options} {value} {onchange} />
</div>

<style>
  /* a group too wide to sit beside its label drops below it, still on the right */
  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px 12px;
  }

  .row > :global(.segmented) {
    margin-left: auto;
  }
</style>
