<script lang="ts">
  import type { Snippet } from "svelte";
  import { privacyUrl, supportUrl, termsUrl } from "../lib/config";
  import { infoPage } from "../lib/info-page.svelte";
  import type { InfoPageName } from "../lib/pages";

  let { page, children }: { page: InfoPageName; children: Snippet } = $props();

  const urls: Record<InfoPageName, string> = {
    privacy: privacyUrl,
    terms: termsUrl,
    support: supportUrl,
  };
  const href = $derived(urls[page]);

  function open(event: MouseEvent): void {
    // a new tab or window still gets the website's page
    if (
      event.button === 0 &&
      !event.metaKey &&
      !event.ctrlKey &&
      !event.shiftKey &&
      !event.altKey
    ) {
      event.preventDefault();
      infoPage.open = page;
    }
  }
</script>

<a {href} onclick={open}>{@render children()}</a>
