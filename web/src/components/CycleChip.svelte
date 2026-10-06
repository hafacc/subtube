<script lang="ts" generics="Value extends string">
  let {
    options,
    value,
    onchange,
  }: {
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
</script>

<button type="button" class="chip cycle" onclick={() => onchange(next())}>
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
  }

  .other {
    visibility: hidden;
  }
</style>
