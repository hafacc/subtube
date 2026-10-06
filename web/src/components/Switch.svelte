<script lang="ts">
  import { Switch } from "bits-ui";

  let {
    checked,
    label,
    onchange,
  }: {
    /** whether it is on */
    checked: boolean;
    /** accessible name */
    label: string;
    /** called with the new state */
    onchange: (checked: boolean) => void;
  } = $props();
</script>

<Switch.Root
  aria-label={label}
  bind:checked={() => checked, (next) => onchange(next)}
>
  {#snippet child({
    props,
  })}
    <button {...props} type="button" class="switch">
      <span class="track">
        <Switch.Thumb>
          {#snippet child({
            props: thumb,
          })}
            <span {...thumb} class="knob"></span>
          {/snippet}
        </Switch.Thumb>
      </span>
    </button>
  {/snippet}
</Switch.Root>

<style>
  .switch {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 48px;
    height: 40px;
    border: 0;
    padding: 0;
    background: transparent;
  }

  .track {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    width: 36px;
    height: 20px;
    border-radius: 10px;
    background: var(--switch-off);
    padding: 0 2px;
    transition: background 0.15s;
  }

  .knob {
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: #ffffff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
    transition: transform 0.15s;
  }

  .switch[data-state="checked"] .track {
    background: var(--sunflower);
  }

  .knob[data-state="checked"] {
    transform: translateX(16px);
  }

  @media (prefers-reduced-motion: reduce) {
    .track,
    .knob {
      transition: none;
    }
  }
</style>
