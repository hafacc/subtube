<script lang="ts">
  import PageText from "../../../components/PageText.svelte";
  import { INFO_PAGES, updatedLabel } from "../../../lib/pages";

  const page = INFO_PAGES.privacy;
</script>

<svelte:head>
  <title>{page.title}</title>
  <meta name="description" content={page.description}>
</svelte:head>

<h1>{page.title}</h1>
<p class="updated">{updatedLabel(page.updated)}</p>
<PageText {page} />
