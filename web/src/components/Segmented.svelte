<script lang="ts" generics="Value extends string">
  import { RadioGroup } from "bits-ui";

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

<RadioGroup.Root
  orientation="horizontal"
  aria-label={label}
  bind:value={() => value, (next) => onchange(next as Value)}
>
  {#snippet child({
    props,
  })}
    <fieldset {...props} class="segmented">
      {#each options as option (option.value)}
        <RadioGroup.Item value={option.value}>
          {#snippet child({
            props: item,
          })}
            <button {...item} type="button">{option.label}</button>
          {/snippet}
        </RadioGroup.Item>
      {/each}
    </fieldset>
  {/snippet}
</RadioGroup.Root>

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
    transition:
      background-color 0.15s,
      color 0.15s;
  }

  button[data-state="checked"] {
    background: var(--sunflower);
    color: var(--ink);
    font-weight: 500;
  }

  @media (prefers-reduced-motion: reduce) {
    button {
      transition: none;
    }
  }
</style>
