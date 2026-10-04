<script lang="ts">
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

<button
  type="button"
  role="switch"
  aria-checked={checked}
  aria-label={label}
  class="switch"
  class:on={checked}
  onclick={() => onchange(!checked)}
>
  <span class="track"><span class="knob"></span></span>
</button>

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
  }

  .on .track {
    justify-content: flex-end;
    background: var(--sunflower);
  }
</style>
