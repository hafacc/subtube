import {
  createJson,
  type DriveFile,
  deleteFile,
  downloadJson,
  listAppFiles,
  updateJson,
} from "./drive";
import {
  channelsFor,
  type DeviceFile,
  deletedElsewhere,
  deviceIdFromName,
  editedEntry,
  editedFilter,
  emptyDeviceFile,
  followedIds,
  hasProfile,
  markedEntry,
  mergeDeviceFiles,
  parseDeviceFile,
  playedEntry,
  pruneDeviceFile,
  refreshSeen,
  type SettingEntry,
  sanitizeDeviceFile,
  type WatchedEntry,
} from "./sync-merge";
import type { Channel, ChannelFilter, ChannelInfo } from "./types";

const DEVICE_KEY = "subtube.device";
/** A burst of edits goes up as one upload. */
const SAVE_DELAY_MS = 2000;

function deviceId(): string {
  try {
    let id = localStorage.getItem(DEVICE_KEY);
    if (!id) {
      id = crypto.randomUUID();
      localStorage.setItem(DEVICE_KEY, id);
    }
    return id;
  } catch {
    return crypto.randomUUID();
  }
}

/** The profile was deleted on another device; this device's copy is gone too. */
export class ProfileDeletedError extends Error {
  constructor() {
    super("Your profile was deleted on another device.");
    this.name = "ProfileDeletedError";
  }
}

function sameEntries(
  left: Record<string, { at: number }> = {},
  right: Record<string, { at: number }> = {},
): boolean {
  const keys = Object.keys(left);
  return (
    keys.length === Object.keys(right).length &&
    keys.every((key) => right[key]?.at === left[key].at)
  );
}

/*
 * The channel filters, watched marks and settings, synced through the Drive app folder.
 * Each device writes only its own file and reads everyone's, so two devices
 * never write the same file. Edits apply in memory at once, are kept in local
 * storage until uploaded (so a reload or a closed tab loses nothing), and go up
 * after a short pause.
 */
export class SyncStore {
  private readonly ownId = deviceId();
  private readonly ownName = `device-${this.ownId}.json`;
  private readonly localKey: string;
  // localStorage key: set once this device's file has been uploaded for the account
  private readonly uploadedKey: string;
  private own: DeviceFile;
  private ownFileId: string | null = null;
  // whether ownFileId is known; saving before then would create a second file
  private listed = false;
  // null: a file this version can't read
  private others = new Map<
    string,
    { modifiedTime: string; deviceId: string; file: DeviceFile | null }
  >();
  private merged: DeviceFile;
  private saveTimer: ReturnType<typeof setTimeout> | null = null;
  private saving: Promise<void> | null = null;
  private closed = false;
  // edits made here, counted, and how many of them Drive has: behind means unsent
  private edits = 0;
  private sentEdits = 0;
  // this device's Drive file exists but this version can't read it, so it is never overwritten
  private ownUnreadable = false;
  /** When Drive last answered a load or a save, in epoch milliseconds. */
  lastSynced: number | null = null;
  /** Whether Drive held any device's file at the last load; null before one. */
  profileFound: boolean | null = null;

  /**
   * Keeps `accountId`'s edits; `getToken` supplies Drive access. `onDeleted`
   * runs when a load finds the profile was deleted on another device.
   */
  constructor(
    accountId: string,
    private readonly getToken: () => Promise<string>,
    private readonly onDeleted: () => void = () => undefined,
  ) {
    this.localKey = `subtube.sync.${accountId}`;
    this.uploadedKey = `subtube.uploaded.${accountId}`;
    this.own = this.readLocal();
    this.merged = this.own;
  }

  private readLocal(): DeviceFile {
    try {
      const raw = localStorage.getItem(this.localKey);
      return (raw && parseDeviceFile(JSON.parse(raw))) || emptyDeviceFile();
    } catch {
      return emptyDeviceFile();
    }
  }

  private writeLocal(): void {
    try {
      localStorage.setItem(this.localKey, JSON.stringify(this.own));
    } catch {
      // the upload still carries it
    }
  }

  private uploadedBefore(): boolean {
    try {
      return localStorage.getItem(this.uploadedKey) !== null;
    } catch {
      return false;
    }
  }

  private markUploaded(): void {
    try {
      localStorage.setItem(this.uploadedKey, "1");
    } catch {
      // a delete made elsewhere then goes unnoticed on this device
    }
  }

  /** Stop uploading and forget everything kept for the account on this device. */
  private wipe(): void {
    this.close();
    this.own = emptyDeviceFile();
    this.others.clear();
    this.merged = this.own;
    this.ownFileId = null;
    try {
      localStorage.removeItem(this.localKey);
      localStorage.removeItem(this.uploadedKey);
    } catch {
      // nothing was kept
    }
  }

  private remerge(): void {
    const sources = [{ deviceId: this.ownId, file: this.own }];
    for (const { deviceId, file } of this.others.values()) {
      if (file) {
        sources.push({ deviceId, file });
      }
    }
    this.merged = mergeDeviceFiles(sources);
  }

  /** Read every device's file, downloading only the ones that changed. */
  async load(): Promise<void> {
    const token = await this.getToken();
    const listed = await listAppFiles(token);
    const names = listed.map(({ name }) => name);
    if (deletedElsewhere(this.uploadedBefore(), names, this.ownName)) {
      this.wipe();
      this.onDeleted();
      throw new ProfileDeletedError();
    } else if (names.includes(this.ownName)) {
      // a file uploaded before this device kept the mark
      this.markUploaded();
    }
    const live = new Set<string>();
    // edits kept locally that Drive doesn't have yet, e.g. from before a reload
    let unsent =
      Object.keys(this.own.channels).length > 0 ||
      Object.keys(this.own.watched).length > 0 ||
      Object.keys(this.own.settings ?? {}).length > 0;
    await Promise.all(
      listed.map(async (entry: DriveFile) => {
        const fileDeviceId = deviceIdFromName(entry.name);
        if (fileDeviceId === null) {
          return;
        }
        if (fileDeviceId === this.ownId) {
          this.ownFileId = entry.id;
          const remote = parseDeviceFile(await downloadJson(entry.id, token));
          this.ownUnreadable = remote === null;
          if (remote) {
            // another tab of this device may have saved since this one loaded
            this.own = {
              ...remote,
              ...this.own,
              ...mergeDeviceFiles([
                { deviceId: this.ownId, file: remote },
                { deviceId: this.ownId, file: this.own },
              ]),
            };
            unsent =
              !sameEntries(this.own.channels, remote.channels) ||
              !sameEntries(this.own.watched, remote.watched) ||
              !sameEntries(this.own.settings, remote.settings);
          }
          return;
        }
        live.add(entry.id);
        if (this.others.get(entry.id)?.modifiedTime !== entry.modifiedTime) {
          const file = parseDeviceFile(await downloadJson(entry.id, token));
          this.others.set(entry.id, {
            modifiedTime: entry.modifiedTime,
            deviceId: fileDeviceId,
            file,
          });
        }
      }),
    );
    for (const id of this.others.keys()) {
      if (!live.has(id)) {
        this.others.delete(id);
      }
    }
    this.listed = true;
    this.profileFound = hasProfile(names);
    this.lastSynced = Date.now();
    this.remerge();
    if (unsent && this.sentEdits === this.edits) {
      // found behind by this load, e.g. edits kept from before a reload
      this.edits += 1;
    }
    if (unsent && !this.saveTimer && !this.saving) {
      this.scheduleSave();
    }
  }

  /** The feed's channels: subscriptions with their filters, plus followed channels. */
  channels(
    subscriptions: ChannelInfo[],
    followedInfo?: ReadonlyMap<string, ChannelInfo>,
  ): Map<string, Channel> {
    return channelsFor(this.merged, subscriptions, followedInfo);
  }

  /** The channels followed in subtube, by id. */
  followedIds(): string[] {
    return followedIds(this.merged);
  }

  /** A video's or playlist's watched entry as last saved on any device. */
  watchedEntry(id: string): WatchedEntry | undefined {
    return this.merged.watched[id];
  }

  /**
   * Save a channel's filter; identity fields and a pattern that is not built
   * from phrases are dropped, unknown fields kept.
   */
  setFilter(channelId: string, filter: ChannelFilter): void {
    this.own.channels[channelId] = editedEntry(this.own.channels[channelId], {
      at: Date.now(),
      filter: editedFilter(filter),
    });
    this.changed();
  }

  /** Mark a video or playlist watched, or unmark it, which also forgets its position. */
  setWatched(id: string, watched: boolean): void {
    this.own.watched[id] = markedEntry(
      this.own.watched[id],
      Date.now(),
      watched,
    );
    this.changed();
  }

  /** Mark or unmark several videos or playlists in one save. */
  setWatchedAll(ids: readonly string[], watched: boolean): void {
    const at = Date.now();
    for (const id of ids) {
      this.own.watched[id] = markedEntry(this.own.watched[id], at, watched);
    }
    this.changed();
  }

  /**
   * Save how far a video has been played; `ended` when its player reported
   * the end. It is kept on this device at once and goes to Drive with the next
   * upload, which this starts only when `upload` is set.
   */
  setProgress(
    id: string,
    position: number,
    ended: boolean,
    upload: boolean,
  ): void {
    this.own.watched[id] = playedEntry(
      this.own.watched[id],
      Date.now(),
      position,
      ended,
    );
    this.edits += 1;
    this.remerge();
    this.writeLocal();
    if (upload) {
      this.scheduleSave();
    }
  }

  /**
   * Note the videos and playlists a full load just returned: this device's
   * entries for them are kept another 30 days, and its entries past that are
   * dropped, here and in Drive.
   */
  noteLoaded(ids: Iterable<string>): void {
    const now = Date.now();
    const kept = pruneDeviceFile(refreshSeen(this.own, new Set(ids), now), now);
    if (kept !== this.own) {
      this.own = kept;
      this.changed();
    }
  }

  /** Every synced setting as last saved on any device; `readSettings` gives them meaning. */
  settings(): Readonly<Record<string, SettingEntry>> {
    return this.merged.settings ?? {};
  }

  /** Save a synced setting. */
  setSetting(name: string, value: unknown): void {
    const settings = this.own.settings ?? {};
    settings[name] = editedEntry(settings[name], { at: Date.now(), value });
    this.own.settings = settings;
    this.changed();
  }

  private changed(): void {
    this.edits += 1;
    this.remerge();
    this.writeLocal();
    this.scheduleSave();
  }

  private scheduleSave(): void {
    if (this.closed) {
      return;
    }
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      void this.save().catch(() => undefined);
    }, SAVE_DELAY_MS);
  }

  /**
   * Stop uploading, before the token turns into another account's. Edits not
   * yet uploaded stay in local storage and go up at this account's next load.
   */
  close(): void {
    this.closed = true;
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
  }

  /**
   * Upload now when anything is unsent, e.g. as the page is hidden; this is
   * also what retries an upload that failed.
   */
  flush(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    if (this.sentEdits !== this.edits && !this.closed) {
      void this.save().catch(() => undefined);
    }
  }

  /** Upload this device's file now; a save already running is waited for first. */
  async save(): Promise<void> {
    while (this.saving) {
      await this.saving;
    }
    if (this.closed) {
      return;
    }
    this.saving = (async () => {
      if (!this.listed) {
        await this.load();
      }
      if (this.ownUnreadable) {
        return;
      }
      const token = await this.getToken();
      const sending = this.edits;
      this.own = sanitizeDeviceFile(pruneDeviceFile(this.own, Date.now()));
      if (this.ownFileId) {
        await updateJson(this.ownFileId, this.own, token);
      } else {
        this.ownFileId = (await createJson(this.ownName, this.own, token)).id;
      }
      this.sentEdits = sending;
      this.markUploaded();
      this.lastSynced = Date.now();
      this.writeLocal();
    })().finally(() => {
      this.saving = null;
    });
    return this.saving;
  }

  /**
   * Delete the profile: every device's file in the Drive folder, then what this
   * device kept. If Drive fails, nothing kept here changes and uploads resume.
   */
  async deleteProfile(): Promise<void> {
    const pending = this.saveTimer !== null;
    this.close();
    while (this.saving) {
      await this.saving.catch(() => undefined);
    }
    try {
      const token = await this.getToken();
      for (const file of await listAppFiles(token)) {
        await deleteFile(file.id, token);
      }
    } catch (caught) {
      this.closed = false;
      // this device's file may be gone already; the next save finds out
      this.listed = false;
      this.ownFileId = null;
      if (pending) {
        this.scheduleSave();
      }
      throw caught;
    }
    this.wipe();
  }
}
