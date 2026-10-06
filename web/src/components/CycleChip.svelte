<script lang="ts" generics="Value extends string">
  let {
    label,
    options,
    value,
    onchange,
  }: {
    /** what the chip sets, read out before the current choice */
    label: string;
    /** the choices, in the order the chip moves through them */
    options: readonly { value: Value; label: string }[];
    /** the current one, whose label the chip shows */
    value: Value;
    /** called with the next choice when the chip is pressed */
    onchange: (value: Value) => void;
  } = $props();

  function next(): Value {
    const index = options.findIndex((option) => option.value === value);
    return options[(index + 1) % options.length].value;
  }

  const current = $derived(
    options.find((option) => option.value === value)?.label ?? "",
  );
</script>

<button
  type="button"
  class="chip cycle"
  aria-label={`${label}: ${current}`}
  onclick={() => onchange(next())}
>
  {#each options as option (option.value)}
    <span
      class:other={option.value !== value}
      aria-hidden={option.value !== value}
    >
      {option.label}
    </span>
  {/each}
</button>

<style>
  /* every label lies in the one cell, so the chip is as wide as its widest and never resizes */
  .cycle {
    display: inline-grid;
    justify-items: center;
  }

  span {
    grid-area: 1 / 1;
    transition:
      opacity 0.15s,
      visibility 0.15s;
  }

  .other {
    opacity: 0;
    visibility: hidden;
  }

  @media (prefers-reduced-motion: reduce) {
    span {
      transition: none;
    }
  }
</style>
