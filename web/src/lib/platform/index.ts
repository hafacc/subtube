import { extensionId } from "../config";
import { extensionInstalled, extensionPlatform } from "./extension";
import type { Platform } from "./types";

export type { Platform, Token } from "./types";

let detected: Promise<Platform | null> | null = null;

/**
 * The extension, which the web app requires: a page with no server gets only
 * hour-long Google tokens and can't renew them, and can't ask /shorts/{id}
 * directly. Null when it isn't installed.
 */
export function platform(): Promise<Platform | null> {
  detected ??= (async () => {
    if (extensionId && (await extensionInstalled(extensionId))) {
      return extensionPlatform(extensionId);
    } else {
      return null;
    }
  })();
  return detected;
}

/** Look for the extension again, e.g. while setup waits for it to be added. */
export async function recheckPlatform(): Promise<Platform | null> {
  if ((await platform()) === null) {
    detected = null;
  }
  return platform();
}
