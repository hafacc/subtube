<script lang="ts" generics="Value extends string">
  let {
    options,
    value,
    onchange,
    label,
  }: {
    /** the choices, in order */
    options: readonly { value: Value; label: string }[];
    /** the chosen one */
    value: Value;
    /** called with a new choice */
    onchange: (value: Value) => void;
    /** accessible name of the group */
    label: string;
  } = $props();
</script>

<fieldset class="segmented" aria-label={label}>
  {#each options as option (option.value)}
    <button
      type="button"
      aria-pressed={option.value === value}
      onclick={() => onchange(option.value)}
    >
      {option.label}
    </button>
  {/each}
</fieldset>

<style>
  .segmented {
    min-inline-size: 0;
    margin: 0;
    padding: 0;
    display: flex;
    align-self: flex-start;
    border: 1px solid var(--border);
    border-radius: 6px;
    overflow: hidden;
  }

  button {
    padding: 7px 10px;
    border: 0;
    background: var(--page);
    color: var(--text);
    font-size: 13px;
  }

  button[aria-pressed="true"] {
    background: var(--sunflower);
    color: var(--ink);
    font-weight: 500;
  }
</style>
