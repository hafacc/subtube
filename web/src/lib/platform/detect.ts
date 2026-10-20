/*
 * Chrome has no way to ask whether extensions are still starting. After a
 * restart it restores tabs before the extensions are up, so the first ping
 * goes unanswered, and a page that loaded before any extension listing it
 * gets no `chrome.runtime` at all until it reloads. A browser that has had the
 * extension before therefore keeps asking for a while, reloading once when
 * the page has no way to reach it.
 */

/** How long a browser that has had the extension keeps asking for it. */
export const EXTENSION_WAIT_MS = 10_000;
/** How long the page waits for `chrome.runtime` before reloading to get it. */
export const RELOAD_AFTER_MS = 2_000;
/** How long after one reload another is not tried, so a page never reloads in a loop. */
export const RELOAD_GAP_MS = 30_000;
// pauses between pings while waiting; the last repeats
const RETRY_DELAYS_MS = [250, 500, 1_000, 2_000];

/** What detection needs from the browser. */
export interface DetectionDeps {
  /** ask the extension once, with this timeout; whether it answered */
  ping(timeoutMs: number): Promise<boolean>;
  /** whether the page can message extensions at all */
  hasRuntime(): boolean;
  /** whether this browser has had the extension answer before */
  seenBefore(): boolean;
  /** remember whether the extension answered on this browser */
  setSeen(seen: boolean): void;
  /** when the page last reloaded to look for the extension, in ms; null for never */
  lastReload(): number | null;
  /** reload the page, noting when */
  reload(at: number): void;
  /** wait this long */
  sleep(ms: number): Promise<void>;
  /** the time in ms */
  now(): number;
  /** called once the quick check missed and a longer wait begins */
  onWaiting?(): void;
}

/**
 * The timeout of the first ping. A missing extension is reported at once, so
 * this only bounds an installed one whose service worker is slow to wake.
 */
export const QUICK_PING_MS = 3_000;
// a waking service worker can take longer than the quick ping allows
const WAITING_PING_MS = 2_000;

/**
 * Whether the extension is there, waiting for it after a browser restart.
 *
 * One quick ping decides for a browser that has never had the extension. One
 * that has keeps pinging for up to {@link EXTENSION_WAIT_MS}, reloading once
 * after {@link RELOAD_AFTER_MS} when the page has no `chrome.runtime`
 * (the promise then never settles). A wait that ends with no answer forgets
 * the extension, so the next page load checks quickly again.
 */
export async function detectExtension(deps: DetectionDeps): Promise<boolean> {
  if (await deps.ping(QUICK_PING_MS)) {
    deps.setSeen(true);
    return true;
  } else if (!deps.seenBefore()) {
    return false;
  } else {
    deps.onWaiting?.();
    const start = deps.now();
    for (let attempt = 0; deps.now() - start < EXTENSION_WAIT_MS; attempt++) {
      await deps.sleep(
        RETRY_DELAYS_MS[Math.min(attempt, RETRY_DELAYS_MS.length - 1)],
      );
      const elapsed = deps.now() - start;
      const remaining = EXTENSION_WAIT_MS - elapsed;
      if (
        remaining > 0 &&
        (await deps.ping(Math.min(WAITING_PING_MS, remaining)))
      ) {
        return true;
      }
      const lastReload = deps.lastReload();
      if (
        !deps.hasRuntime() &&
        deps.now() - start >= RELOAD_AFTER_MS &&
        (lastReload === null || deps.now() - lastReload >= RELOAD_GAP_MS)
      ) {
        deps.reload(deps.now());
        return new Promise<boolean>(() => undefined);
      }
    }
    deps.setSeen(false);
    return false;
  }
}
