<script lang="ts">
  import { MODE_OPTIONS, SCOPE_OPTIONS } from "../lib/channel-summary";
  import type { FilterMode, FilterScope } from "../lib/types";
  import Chip from "./Chip.svelte";
  import ChoiceRow from "./ChoiceRow.svelte";

  let {
    phrases,
    mode,
    matchIn,
    onphrases,
    onmode,
    onscope,
  }: {
    /** the phrases the filter looks for, in order */
    phrases: readonly string[];
    /** whether matches are hidden or the only ones shown */
    mode: FilterMode;
    /** what the phrases are searched in */
    matchIn: FilterScope;
    /** called with the whole new list when a phrase is added or removed */
    onphrases: (phrases: string[]) => void;
    /** called with a new mode */
    onmode: (mode: FilterMode) => void;
    /** called with a new scope */
    onscope: (scope: FilterScope) => void;
  } = $props();

  const HEADING: Record<FilterScope, string> = {
    title: "Title phrases",
    both: "Text phrases",
    description: "Description phrases",
  };

  // the phrase being typed, not yet a chip
  let draft = $state("");

  function add(typed: readonly string[]): void {
    onphrases([...phrases, ...typed]);
  }

  /** A comma ends a phrase: everything before the last one becomes chips, the rest stays in the field. */
  function typed(value: string): void {
    const parts = value.split(",");
    draft = parts[parts.length - 1];
    if (parts.length > 1) {
      add(parts.slice(0, -1));
    }
  }

  function pressed(event: KeyboardEvent): void {
    if (event.key === "Enter" && !event.isComposing) {
      event.preventDefault();
      add([draft]);
      draft = "";
    } else if (event.key === "Backspace" && draft === "") {
      onphrases(phrases.slice(0, -1));
    }
  }
</script>

<label for="filter-phrase" class="label">{HEADING[matchIn]}</label>
<div class="phrases">
  {#each phrases as phrase (phrase)}
    <Chip
      label={phrase}
      removes
      onclick={() => onphrases(phrases.filter((other) => other !== phrase))}
    />
  {/each}
  <input
    id="filter-phrase"
    class="text-input"
    placeholder="Add a phrase"
    spellcheck="false"
    autocomplete="off"
    value={draft}
    oninput={(event) => typed(event.currentTarget.value)}
    onkeydown={pressed}
  >
</div>
<p class="secondary help">Videos match if they contain any of these phrases.</p>
<ChoiceRow
  label="Matches"
  options={MODE_OPTIONS}
  value={mode}
  onchange={onmode}
/>
<ChoiceRow
  label="Match in"
  options={SCOPE_OPTIONS}
  value={matchIn}
  onchange={onscope}
/>

<style>
  .label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .phrases {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .phrases > :global(.chip) {
    max-width: 100%;
    overflow: hidden;
  }

  input {
    flex: 1 1 120px;
    min-width: 0;
    height: 30px;
  }

  .help {
    margin: 0;
    font-size: 13px;
  }
</style>
