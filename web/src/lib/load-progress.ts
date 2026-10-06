/** How far the load bar stands while the subscription list is being read. */
export const LOAD_PROGRESS_START = 0.05;

/**
 * How far a full load has come, from 0 to 1: the share of its channels that
 * are finished (fetched, failed or skipped), never under
 * {@link LOAD_PROGRESS_START}. `total` is null until the subscription list
 * says how many channels there are to fetch.
 */
export function loadFraction(finished: number, total: number | null): number {
  if (total === null || total <= 0) {
    return LOAD_PROGRESS_START;
  } else {
    return Math.max(LOAD_PROGRESS_START, Math.min(1, finished / total));
  }
}
