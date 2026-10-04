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
  emptyDeviceFile,
  followedIds,
  hasProfile,
  mergeDeviceFiles,
  parseDeviceFile,
  pruneDeviceFile,
  sanitizeDeviceFile,
  savedFilter,
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
  left: Record<string, { at: number }>,
  right: Record<string, { at: number }>,
): boolean {
  const keys = Object.keys(left);
  return (
    keys.length === Object.keys(right).length &&
    keys.every((key) => right[key]?.at === left[key].at)
  );
}

/*
 * The channel filters and watched marks, synced through the Drive app folder.
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
      Object.keys(this.own.watched).length > 0;
    await Promise.all(
      listed.map(async (entry: DriveFile) => {
        const fileDeviceId = deviceIdFromName(entry.name);
        if (fileDeviceId === null) {
          return;
        }
        if (fileDeviceId === this.ownId) {
          this.ownFileId = entry.id;
          const remote = parseDeviceFile(await downloadJson(entry.id, token));
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
              !sameEntries(this.own.watched, remote.watched);
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

  /** Whether a video or playlist is marked watched. */
  isWatched(id: string): boolean {
    return this.merged.watched[id]?.watched ?? false;
  }

  /** The ids among these that are marked watched. */
  watchedAmong(ids: string[]): Set<string> {
    return new Set(ids.filter((id) => this.isWatched(id)));
  }

  /** Save a channel's filter; identity fields are dropped, unknown ones kept. */
  setFilter(channelId: string, filter: ChannelFilter): void {
    this.own.channels[channelId] = {
      at: Date.now(),
      filter: savedFilter(filter),
    };
    this.changed();
  }

  /** Mark or unmark a video or playlist as watched. */
  setWatched(id: string, watched: boolean): void {
    this.own.watched[id] = { at: Date.now(), watched };
    this.changed();
  }

  /** Mark or unmark several videos or playlists in one save. */
  setWatchedAll(ids: readonly string[], watched: boolean): void {
    const at = Date.now();
    for (const id of ids) {
      this.own.watched[id] = { at, watched };
    }
    this.changed();
  }

  private changed(): void {
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

  /** Upload now when an upload is waiting, e.g. as the page is hidden. */
  flush(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
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
      const token = await this.getToken();
      this.own = sanitizeDeviceFile(pruneDeviceFile(this.own, Date.now()));
      if (this.ownFileId) {
        await updateJson(this.ownFileId, this.own, token);
      } else {
        this.ownFileId = (await createJson(this.ownName, this.own, token)).id;
      }
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
