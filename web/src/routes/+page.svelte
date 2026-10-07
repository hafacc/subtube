<script lang="ts">
  import { browser } from "$app/env";
  import { asset } from "$app/paths";
  import App from "../App.svelte";
</script>

<svelte:head>
  <title>SubTube</title>
  <meta
    name="description"
    content="Your subscriptions, your filters, no algorithm."
  >
  <link rel="manifest" href={asset("manifest.webmanifest")}>
</svelte:head>

<!-- the app reads the browser as it starts, so the built page holds none of it -->
{#if browser}
  <App />
{/if}
