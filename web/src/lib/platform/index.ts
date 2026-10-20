import { extensionId } from "../config";
import { readText, writeText } from "../storage";
import { detectExtension, QUICK_PING_MS } from "./detect";
import { extensionInstalled, extensionPlatform, hasRuntime } from "./extension";
import type { Platform } from "./types";

export type { Platform, Token } from "./types";

/** localStorage key: set once the extension has answered on this browser. */
const EXTENSION_SEEN = "subtube.extensionSeen";
/** sessionStorage key: when this tab last reloaded to reach the extension. */
const EXTENSION_RELOAD = "subtube.extensionReload";

let detected: Promise<Platform | null> | null = null;

function lastReload(): number | null {
  try {
    const at = Number(sessionStorage.getItem(EXTENSION_RELOAD));
    return at > 0 ? at : null;
  } catch {
    return null;
  }
}

function reload(at: number): void {
  try {
    sessionStorage.setItem(EXTENSION_RELOAD, String(at));
  } catch {
    // without the mark the next page may reload once more, then gives up
  }
  window.location.reload();
}

function setSeen(seen: boolean): void {
  writeText(EXTENSION_SEEN, seen ? "1" : null);
}

/**
 * The extension, which the web app requires: a page with no server gets only
 * hour-long Google tokens and can't renew them, and can't ask /shorts/{id}
 * directly. Null when it isn't installed. A browser that has had it waits
 * for it after a restart (`detectExtension`), calling `onWaiting` when that
 * begins.
 */
export function platform(onWaiting?: () => void): Promise<Platform | null> {
  detected ??= (async () => {
    if (
      extensionId &&
      (await detectExtension({
        ping: (timeoutMs) => extensionInstalled(extensionId, timeoutMs),
        hasRuntime,
        seenBefore: () => readText(EXTENSION_SEEN) !== null,
        setSeen,
        lastReload,
        reload,
        sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
        now: () => Date.now(),
        onWaiting,
      }))
    ) {
      return extensionPlatform(extensionId);
    } else {
      return null;
    }
  })();
  return detected;
}

/** Look for the extension again, e.g. while setup waits for it to be added. */
export async function recheckPlatform(): Promise<Platform | null> {
  if ((await platform()) === null && extensionId) {
    if (await extensionInstalled(extensionId, QUICK_PING_MS)) {
      setSeen(true);
      detected = Promise.resolve(extensionPlatform(extensionId));
    }
  }
  return platform();
}
