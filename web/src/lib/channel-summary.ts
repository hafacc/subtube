import type { FilterMode, FilterScope, ShortsFilter } from "./types";

/** Whether a pattern's matches are hidden or the only ones shown, in order. */
export const MODE_OPTIONS = [
  { value: "exclude", label: "Hide" },
  { value: "include", label: "Show" },
] as const satisfies readonly { value: FilterMode; label: string }[];

/** Where a pattern is searched, in order. */
export const SCOPE_OPTIONS = [
  { value: "title", label: "Title" },
  { value: "both", label: "Both" },
  { value: "description", label: "Description" },
] as const satisfies readonly { value: FilterScope; label: string }[];

/** The Shorts setting most of these filters have; a tie reads as all. */
export function mostCommonShorts(
  filters: readonly { shortsFilter?: ShortsFilter }[],
): ShortsFilter {
  const counts = new Map<ShortsFilter, number>();
  for (const filter of filters) {
    const value = filter.shortsFilter ?? "all";
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  const most = Math.max(0, ...counts.values());
  const winners = Array.from(counts).filter(([, count]) => count === most);
  return winners.length === 1 ? winners[0][0] : "all";
}

/** The Shorts choices, in order, as the filter editor and setup show them. */
export const SHORTS_OPTIONS = [
  { value: "all", label: "Show" },
  { value: "normal", label: "Hide" },
  { value: "shorts", label: "Only" },
] as const satisfies readonly { value: ShortsFilter; label: string }[];
