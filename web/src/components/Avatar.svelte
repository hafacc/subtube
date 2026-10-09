<script lang="ts">
  let {
    title,
    thumbnail,
    size = 32,
    dim = false,
    tint = false,
  }: {
    /** whose avatar; its first letter stands in for a missing picture */
    title: string;
    /** picture URL; empty for none */
    thumbnail: string;
    /** diameter in pixels */
    size?: number;
    /** shown at half strength, for a channel that is off */
    dim?: boolean;
    /** the account's yellow tint instead of the neutral one */
    tint?: boolean;
  } = $props();

  let broken = $state(false);
</script>

<span
  class="avatar"
  class:tint={tint}
  style:width="{size}px"
  style:height="{size}px"
  style:font-size="{Math.round(size * 0.4)}px"
  style:opacity={dim ? 0.5 : 1}
  aria-hidden="true"
>
  {#if thumbnail && !broken}
    <img
      src={thumbnail}
      alt=""
      loading="lazy"
      decoding="async"
      referrerpolicy="no-referrer"
      onerror={() => {
        broken = true;
      }}
    >
  {:else}
    {title.trim().charAt(0).toUpperCase()}
  {/if}
</span>

<style>
  .tint {
    background: var(--tint);
    color: var(--tint-text);
    font-weight: 400;
  }
</style>
