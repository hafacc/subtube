import { keysWith, readText, writeText } from "./storage";

/** localStorage key prefix: set, per account, once first-run setup is finished on this browser. */
export const SETUP_DONE_PREFIX = "subtube.setupDone.";
/** localStorage key prefix: an account's unsent edits. */
export const SYNC_PREFIX = "subtube.sync.";
/** localStorage key prefix: the id of an account's uploaded Drive file. */
export const UPLOADED_PREFIX = "subtube.uploaded.";
/** localStorage key prefix: first run's starting point while channels still wait for it. */
export const PENDING_START_PREFIX = "subtube.startFrom.";

const PREFIXES = [
  SETUP_DONE_PREFIX,
  SYNC_PREFIX,
  UPLOADED_PREFIX,
  PENDING_START_PREFIX,
];

// earlier versions filed an account's entries under its YouTube channel id
const CHANNEL_ID = /^UC[\w-]{22}$/;

/** The YouTube channel ids that entries of earlier versions are still filed under. */
export function oldAccountIds(): string[] {
  const ids = PREFIXES.flatMap((prefix) =>
    keysWith(prefix).map((key) => key.slice(prefix.length)),
  );
  return [...new Set(ids.filter((id) => CHANNEL_ID.test(id)))];
}

/** File everything kept under `oldId` under `newId`; what `newId` already has stays. */
export function moveAccountEntries(oldId: string, newId: string): void {
  for (const prefix of PREFIXES) {
    const value = readText(prefix + oldId);
    if (value !== null) {
      if (readText(prefix + newId) === null) {
        writeText(prefix + newId, value);
      }
      writeText(prefix + oldId, null);
    }
  }
}
