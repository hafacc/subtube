<script lang="ts">
  import { MODE_OPTIONS, SCOPE_OPTIONS } from "../lib/channel-summary";
  import { isValidPattern } from "../lib/filters";
  import type { FilterMode, FilterScope } from "../lib/types";
  import ChoiceRow from "./ChoiceRow.svelte";

  let {
    pattern,
    mode,
    matchIn,
    onpattern,
    onmode,
    onscope,
  }: {
    /** the pattern as typed, valid or not */
    pattern: string;
    /** whether matches are hidden or the only ones shown */
    mode: FilterMode;
    /** what the pattern is searched in */
    matchIn: FilterScope;
    /** called with everything typed, valid or not */
    onpattern: (pattern: string) => void;
    /** called with a new mode */
    onmode: (mode: FilterMode) => void;
    /** called with a new scope */
    onscope: (scope: FilterScope) => void;
  } = $props();

  const HEADING: Record<FilterScope, string> = {
    title: "Title pattern",
    both: "Text pattern",
    description: "Description pattern",
  };

  const valid = $derived(isValidPattern(pattern));
</script>

<label for="filter-pattern" class="label">{HEADING[matchIn]}</label>
<input
  id="filter-pattern"
  class="text-input pattern"
  class:invalid={!valid}
  aria-invalid={!valid}
  spellcheck="false"
  autocomplete="off"
  value={pattern}
  oninput={(event) => onpattern(event.currentTarget.value)}
>
{#if !valid}
  <p class="error-text">SubTube can't use this pattern, so it isn't saved.</p>
{/if}
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

  .pattern {
    width: 100%;
    font-family: var(--mono);
  }

  .pattern.invalid {
    border-color: var(--error);
  }
</style>
