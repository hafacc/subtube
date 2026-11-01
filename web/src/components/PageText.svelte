<script lang="ts">
  import { type InfoPage, textParts } from "../lib/pages";

  let { page, level = 2 }: { page: InfoPage; level?: number } = $props();
</script>

{#snippet text(value: string)}
  {#each textParts(value) as part, index (index)}
    {#if part.href === undefined}
      {part.text}
    {:else if part.href.startsWith("mailto:")}
      <a href={part.href}>{part.text}</a>
    {:else}
      <a href={part.href} target="_blank" rel="noopener noreferrer"
        >{part.text}</a
      >
    {/if}
  {/each}
{/snippet}

{#each page.intro as paragraph, index (index)}
  <p>{@render text(paragraph)}</p>
{/each}
{#each page.sections as section (section.heading)}
  <svelte:element this={`h${level}`}>{section.heading}</svelte:element>
  <ul>
    {#each section.items as item, index (index)}
      <li>{@render text(item)}</li>
    {/each}
  </ul>
{/each}
