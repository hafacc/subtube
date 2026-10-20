import { describe, expect, test } from "bun:test";
import {
  type DetectionDeps,
  detectExtension,
  EXTENSION_WAIT_MS,
  QUICK_PING_MS,
  RELOAD_AFTER_MS,
  RELOAD_GAP_MS,
} from "./detect";

interface Fake {
  deps: DetectionDeps;
  pings: number[];
  reloads: number[];
  seen: boolean;
  waited: boolean;
}

/** A browser on a fake clock whose extension answers from `answersAt` on (ms), with `chrome.runtime` from `runtimeAt`. */
function fakeBrowser(options: {
  seen: boolean;
  answersAt?: number;
  runtimeAt?: number;
  lastReload?: number | null;
}): Fake {
  const { answersAt = Infinity, runtimeAt = 0, lastReload = null } = options;
  let clock = 0;
  const fake: Fake = {
    pings: [],
    reloads: [],
    seen: options.seen,
    waited: false,
    deps: {
      ping: async (timeoutMs) => {
        fake.pings.push(timeoutMs);
        return clock >= answersAt && clock >= runtimeAt;
      },
      hasRuntime: () => clock >= runtimeAt,
      seenBefore: () => fake.seen,
      setSeen: (seen) => {
        fake.seen = seen;
      },
      lastReload: () => lastReload,
      reload: (at) => {
        fake.reloads.push(at);
      },
      sleep: async (ms) => {
        clock += ms;
      },
      now: () => clock,
      onWaiting: () => {
        fake.waited = true;
      },
    },
  };
  return fake;
}

/** Settles with the result, or "pending" when the promise is left hanging. */
async function settled(
  promise: Promise<boolean>,
): Promise<boolean | "pending"> {
  return Promise.race([
    promise,
    new Promise<"pending">((resolve) =>
      setTimeout(() => resolve("pending"), 20),
    ),
  ]);
}

describe("detectExtension", () => {
  test("an extension that answers at once is found and remembered", async () => {
    const fake = fakeBrowser({ seen: false, answersAt: 0 });
    expect(await detectExtension(fake.deps)).toBe(true);
    expect(fake.pings).toEqual([QUICK_PING_MS]);
    expect(fake.seen).toBe(true);
    expect(fake.waited).toBe(false);
  });

  test("a browser that never had it gives up after one ping", async () => {
    const fake = fakeBrowser({ seen: false });
    expect(await detectExtension(fake.deps)).toBe(false);
    expect(fake.pings).toHaveLength(1);
    expect(fake.waited).toBe(false);
  });

  test("a browser that had it waits until it starts", async () => {
    const fake = fakeBrowser({ seen: true, answersAt: 1_500 });
    expect(await detectExtension(fake.deps)).toBe(true);
    expect(fake.waited).toBe(true);
    expect(fake.reloads).toEqual([]);
    expect(fake.seen).toBe(true);
  });

  test("a browser that had it gives up after the wait and forgets it", async () => {
    const fake = fakeBrowser({ seen: true });
    expect(await detectExtension(fake.deps)).toBe(false);
    expect(fake.waited).toBe(true);
    expect(fake.seen).toBe(false);
    expect(fake.reloads).toEqual([]);
    expect(fake.pings.length).toBeGreaterThan(3);
  });

  test("no ping is made after the wait ends", async () => {
    const fake = fakeBrowser({ seen: true });
    await detectExtension(fake.deps);
    expect(fake.pings.every((timeoutMs) => timeoutMs > 0)).toBe(true);
  });

  test("a page loaded before the extension reloads once to reach it", async () => {
    const fake = fakeBrowser({ seen: true, runtimeAt: Infinity });
    expect(await settled(detectExtension(fake.deps))).toBe("pending");
    expect(fake.reloads).toHaveLength(1);
    const [reloadAt] = fake.reloads;
    expect(reloadAt).toBeGreaterThanOrEqual(RELOAD_AFTER_MS);
    expect(reloadAt).toBeLessThan(EXTENSION_WAIT_MS);
  });

  test("a page that reloaded just now waits instead of reloading again", async () => {
    const fake = fakeBrowser({
      seen: true,
      runtimeAt: Infinity,
      lastReload: -1_000,
    });
    expect(await detectExtension(fake.deps)).toBe(false);
    expect(fake.reloads).toEqual([]);
  });

  test("a reload long ago doesn't stop another", async () => {
    const fake = fakeBrowser({
      seen: true,
      runtimeAt: Infinity,
      lastReload: -RELOAD_GAP_MS,
    });
    expect(await settled(detectExtension(fake.deps))).toBe("pending");
    expect(fake.reloads).toHaveLength(1);
  });

  test("a page whose runtime comes up in time doesn't reload", async () => {
    const fake = fakeBrowser({
      seen: true,
      runtimeAt: 1_000,
      answersAt: 1_000,
    });
    expect(await detectExtension(fake.deps)).toBe(true);
    expect(fake.reloads).toEqual([]);
  });
});
