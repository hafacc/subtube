<script lang="ts">
  import { asset } from "$app/paths";

  let {
    hull = 22,
  }: {
    /** height of the logo's hull in pixels: the line height of the name beside it */
    hull?: number;
  } = $props();

  // the hull's share of the square drawing; it is centred in it, the tower above
  const HULL_HEIGHT = 0.518;
  const HULL_WIDTH = 0.74;

  const size = $derived(hull / HULL_HEIGHT);
  // the box laid out is the hull alone, so the tower rises over the line without moving anything
  const margin = $derived(
    `${(hull - size) / 2}px ${(size * (HULL_WIDTH - 1)) / 2}px`,
  );
</script>

<img
  src={asset("logo.svg")}
  width={size}
  height={size}
  style:margin={margin}
  alt=""
>

<style>
  img {
    flex-shrink: 0;
  }
</style>
