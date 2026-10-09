import { phrasePatternOnly } from "./phrases";
import type { Channel, ChannelFilter, ChannelInfo } from "./types";

/**
 * One device's edits, as kept in its own file in the Drive app folder. The
 * format is shared/schema/device-file.schema.json; fields this version doesn't
 * know are kept, so a newer client's additions survive this one's saves.
 */
export interface DeviceFile {
  version: 1;
  /** The last filter saved for each channel, with when it was saved. */
  channels: Record<string, { at: number; filter: ChannelFilter }>;
  /** The last watched mark for each video or playlist, with when it was made. */
  watched: Record<string, WatchedEntry>;
  /** The last value saved for each synced setting, with when it was saved. */
  settings?: Record<string, SettingEntry>;
  /** Fields from a newer client, kept as they were. */
  [unknown: string]: unknown;
}

/** One video's or playlist's watched mark as a device last saved it; `progress.ts` reads it. */
export interface WatchedEntry {
  /** when it was saved, in epoch milliseconds */
  at: number;
  /** true for a mark, or a video whose player reported the end */
  watched: boolean;
  /** how far a video has been played, in seconds; kept whatever it holds */
  position?: unknown;
  /** when this device last had it among a full load's items, in epoch milliseconds; kept whatever it holds */
  seen?: unknown;
  /** fields from a newer client, kept as they were */
  [unknown: string]: unknown;
}

/** One synced setting as a device last saved it; what a value means is read in `settings.ts`. */
export interface SettingEntry {
  /** when it was saved, in epoch milliseconds */
  at: number;
  /** the saved value, kept whatever it is */
  value: unknown;
  /** fields from a newer client, kept as they were */
  [unknown: string]: unknown;
}

/** One device's file together with the id in its name. */
export interface DeviceSource {
  /** The `<id>` in `device-<id>.json`. */
  deviceId: string;
  /** The parsed file. */
  file: DeviceFile;
}

/** A watched entry neither saved nor loaded for this long is dropped when its device next saves. */
export const WATCHED_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/** How old an entry's `seen` gets before a load writes a new one. */
export const SEEN_REFRESH_MS = 24 * 60 * 60 * 1000;

const DEVICE_FILE_NAME = /^device-([A-Za-z0-9_-]+)\.json$/;

/** The device id in a sync file's name, or null when it isn't a device file. */
export function deviceIdFromName(name: string): string | null {
  return DEVICE_FILE_NAME.exec(name)?.[1] ?? null;
}

/**
 * Whether an app folder holding these file names is an account already set
 * up: any device's file. A device asks this of the other devices' files only,
 * so its own file, written part-way through setup, never counts.
 */
export function hasProfile(fileNames: readonly string[]): boolean {
  return fileNames.some((name) => deviceIdFromName(name) !== null);
}

/**
 * An entry of a device's own file after an edit: the new time and values, with
 * whatever else a newer client wrote beside them kept.
 */
export function editedEntry<Entry extends { at: number }>(
  prior: Entry | undefined,
  edit: Entry,
): Entry {
  return { ...prior, ...edit };
}

/**
 * A watched entry after a mark: marking watched keeps its position, unmarking
 * drops it, or a position near the end would read as watched again.
 */
export function markedEntry(
  prior: WatchedEntry | undefined,
  at: number,
  watched: boolean,
): WatchedEntry {
  const { position, ...rest } = editedEntry(prior, { at, watched });
  return watched && position !== undefined ? { ...rest, position } : rest;
}

/**
 * A watched entry after its video played to `position` seconds; `ended` when
 * the player reported the end, which alone marks it watched here.
 */
export function playedEntry(
  prior: WatchedEntry | undefined,
  at: number,
  position: number,
  ended: boolean,
): WatchedEntry {
  return editedEntry(prior, { at, watched: ended, position });
}

/** An empty file of the current version. */
export function emptyDeviceFile(): DeviceFile {
  return { version: 1, channels: {}, watched: {} };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isTime(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 0 &&
    value <= Number.MAX_SAFE_INTEGER
  );
}

function entries<Entry>(
  raw: unknown,
  isEntry: (entry: Record<string, unknown>) => boolean,
): Record<string, Entry> {
  if (!isObject(raw)) {
    return {};
  } else {
    return Object.fromEntries(
      Object.entries(raw).filter(
        ([, entry]) => isObject(entry) && isTime(entry.at) && isEntry(entry),
      ),
    ) as Record<string, Entry>;
  }
}

/**
 * Read a downloaded file. A file that isn't version 1 (older, newer or not a
 * device file at all) reads as null; malformed entries are dropped and unknown
 * fields kept. `settings` is read only when the file has one.
 */
export function parseDeviceFile(raw: unknown): DeviceFile | null {
  if (!isObject(raw) || raw.version !== 1) {
    return null;
  } else {
    return {
      ...raw,
      version: 1,
      channels: entries(raw.channels, (entry) => isObject(entry.filter)),
      watched: entries(
        raw.watched,
        (entry) => typeof entry.watched === "boolean",
      ),
      ...(raw.settings === undefined
        ? {}
        : { settings: entries(raw.settings, (entry) => "value" in entry) }),
    };
  }
}

function newest<Entry extends { at: number }>(
  records: { deviceId: string; record: Record<string, Entry> }[],
): Map<string, Entry> {
  const merged = new Map<string, { deviceId: string; entry: Entry }>();
  for (const { deviceId, record } of records) {
    for (const [key, entry] of Object.entries(record)) {
      const prior = merged.get(key);
      if (
        !prior ||
        entry.at > prior.entry.at ||
        (entry.at === prior.entry.at && deviceId > prior.deviceId)
      ) {
        merged.set(key, { deviceId, entry });
      }
    }
  }
  return new Map(Array.from(merged, ([key, { entry }]) => [key, entry]));
}

/**
 * Every device's edits, newest per key; on a tie in time the greater device id
 * wins. Each file has one writer, so nothing here ever conflicts; the files
 * only disagree about time.
 */
export function mergeDeviceFiles(sources: DeviceSource[]): DeviceFile {
  const channels = newest(
    sources.map(({ deviceId, file }) => ({ deviceId, record: file.channels })),
  );
  const watched = newest(
    sources.map(({ deviceId, file }) => ({ deviceId, record: file.watched })),
  );
  const settings = newest(
    sources.map(({ deviceId, file }) => ({
      deviceId,
      record: file.settings ?? {},
    })),
  );
  return {
    version: 1,
    channels: Object.fromEntries(channels),
    watched: Object.fromEntries(watched),
    settings: Object.fromEntries(settings),
  };
}

function seenAt(entry: { seen?: unknown }): number {
  return isTime(entry.seen) ? entry.seen : 0;
}

function newerOfOwn<Entry extends { at: number; seen?: unknown }>(
  mine: Record<string, Entry> = {},
  other: Record<string, Entry> = {},
): Record<string, Entry> {
  const merged = { ...mine };
  for (const [key, entry] of Object.entries(other)) {
    const held = merged[key];
    if (
      !held ||
      entry.at > held.at ||
      (entry.at === held.at && seenAt(entry) > seenAt(held))
    ) {
      merged[key] = entry;
    }
  }
  return merged;
}

/**
 * Two copies of one device's own file as one: per key the entry saved last,
 * and of two saved at the same time the one seen in a load last, else
 * `mine`. Used where the same device wrote twice: another tab's copy, or a
 * second Drive file under this device's name.
 */
export function mergeOwnCopies(
  mine: DeviceFile,
  other: DeviceFile,
): DeviceFile {
  const settings =
    mine.settings === undefined && other.settings === undefined
      ? {}
      : { settings: newerOfOwn(mine.settings, other.settings) };
  return {
    ...other,
    ...mine,
    version: 1,
    channels: newerOfOwn(mine.channels, other.channels),
    watched: newerOfOwn(mine.watched, other.watched),
    ...settings,
  };
}

/** Whether two copies of a device's file hold the same entries, by key, time saved and time seen. */
export function sameOwnEntries(left: DeviceFile, right: DeviceFile): boolean {
  const same = (
    first: Record<string, { at: number; seen?: unknown }> = {},
    second: Record<string, { at: number; seen?: unknown }> = {},
  ) => {
    const keys = Object.keys(first);
    return (
      keys.length === Object.keys(second).length &&
      keys.every(
        (key) =>
          second[key]?.at === first[key].at &&
          seenAt(second[key]) === seenAt(first[key]),
      )
    );
  };
  return (
    same(left.channels, right.channels) &&
    same(left.watched, right.watched) &&
    same(left.settings, right.settings)
  );
}

/** When an entry was last saved or last among a load's items, whichever is later. */
function lastUsed(entry: WatchedEntry): number {
  return isTime(entry.seen) ? Math.max(entry.at, entry.seen) : entry.at;
}

/**
 * A device's own file after a full load whose items were `loadedIds`: each of
 * its entries among them gets `seen` set to `now`, unless its `seen` is
 * younger than {@link SEEN_REFRESH_MS}. Returns `file` itself when nothing
 * changes.
 */
export function refreshSeen(
  file: DeviceFile,
  loadedIds: ReadonlySet<string>,
  now: number,
): DeviceFile {
  const refreshed = Object.entries(file.watched).filter(
    ([id, { seen }]) =>
      loadedIds.has(id) && !(isTime(seen) && now - seen < SEEN_REFRESH_MS),
  );
  if (refreshed.length === 0) {
    return file;
  } else {
    const watched = { ...file.watched };
    for (const [id, entry] of refreshed) {
      watched[id] = { ...entry, seen: now };
    }
    return { ...file, watched };
  }
}

/**
 * A device's file without the watched entries neither saved nor seen in a
 * load within {@link WATCHED_RETENTION_MS}. Returns `file` itself when
 * nothing is dropped.
 */
export function pruneDeviceFile(file: DeviceFile, now: number): DeviceFile {
  const kept = Object.entries(file.watched).filter(
    ([, entry]) => now - lastUsed(entry) < WATCHED_RETENTION_MS,
  );
  if (kept.length === Object.keys(file.watched).length) {
    return file;
  } else {
    return { ...file, watched: Object.fromEntries(kept) };
  }
}

/** The filter a newly seen channel starts with. */
export function defaultFilter(): ChannelFilter {
  return { enabled: true, regex: "", mode: "include" };
}

/** Keys the schema forbids in a saved filter: YouTube owns a channel's identity. */
const IDENTITY_KEYS = ["channelId", "title", "thumbnail"] as const;

/** A filter fit to save: identity fields dropped, every other field kept. */
export function savedFilter(filter: ChannelFilter): ChannelFilter {
  const saved = { ...filter };
  for (const key of IDENTITY_KEYS) {
    delete saved[key];
  }
  return saved;
}

/** A filter as an edit saves it: a pattern that is not built from phrases is dropped. */
export function editedFilter(filter: ChannelFilter): ChannelFilter {
  return { ...savedFilter(filter), regex: phrasePatternOnly(filter.regex) };
}

/** A device's own file fit to write: every filter without identity fields. */
export function sanitizeDeviceFile(file: DeviceFile): DeviceFile {
  return {
    ...file,
    channels: Object.fromEntries(
      Object.entries(file.channels).map(([channelId, entry]) => [
        channelId,
        { ...entry, filter: savedFilter(entry.filter) },
      ]),
    ),
  };
}

/**
 * The channels the feed reads: every YouTube subscription with its saved filter
 * (or the default). YouTube owns a channel's title and thumbnail. A filter
 * saved for a channel since unsubscribed is kept, so subscribing again
 * restores it.
 */
export function channelsFor(
  merged: DeviceFile,
  subscriptions: ChannelInfo[],
): Map<string, Channel> {
  const channels = new Map<string, Channel>();
  for (const subscription of subscriptions) {
    const saved = merged.channels[subscription.channelId]?.filter;
    channels.set(subscription.channelId, {
      channelId: subscription.channelId,
      title: subscription.title,
      thumbnail: subscription.thumbnail,
      filter: saved ?? defaultFilter(),
    });
  }
  return channels;
}
