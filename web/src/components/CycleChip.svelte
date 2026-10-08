<script lang="ts" generics="Value extends string">
  let {
    label,
    options,
    value,
    pressed = undefined,
    filled = false,
    onchange,
  }: {
    /** what the chip sets, read out before the current choice */
    label: string;
    /** the choices, in the order the chip moves through them */
    options: readonly { value: Value; label: string }[];
    /** the current one, whose label the chip shows */
    value: Value;
    /** whether a chip that is one of a set is the selected one; leave out for a chip that only cycles */
    pressed?: boolean;
    /** whether a chip that only cycles is drawn as selected */
    filled?: boolean;
    /** called on a press with the next choice, or with the current one by a chip that was not `pressed` */
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
  class:filled={filled}
  aria-label={`${label}: ${current}`}
  aria-pressed={pressed}
  onclick={() => onchange(pressed === false ? value : next())}
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
