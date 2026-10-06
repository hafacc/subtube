import {
  createJson,
  type DriveFile,
  deleteFile,
  downloadJson,
  fileExists,
  listAppFiles,
  updateJson,
} from "./drive";
import { ShownError } from "./errors";
import { readJson, readText, writeJson, writeText } from "./storage";
import {
  channelsFor,
  type DeviceFile,
  deviceIdFromName,
  editedEntry,
  editedFilter,
  emptyDeviceFile,
  followedIds,
  hasProfile,
  markedEntry,
  mergeDeviceFiles,
  mergeOwnCopies,
  parseDeviceFile,
  playedEntry,
  pruneDeviceFile,
  refreshSeen,
  type SettingEntry,
  sameOwnEntries,
  sanitizeDeviceFile,
  type WatchedEntry,
} from "./sync-merge";
import type { Channel, ChannelFilter, ChannelInfo } from "./types";
import { GoogleRequestError, TokenExpiredError } from "./youtube";

const DEVICE_KEY = "subtube.device";
/** A burst of edits goes up as one upload. */
const SAVE_DELAY_MS = 2000;
// what the uploaded mark held before it held the file's id
const UPLOADED_WITHOUT_ID = "1";

// the id used when local storage can't keep one, the same for every store of this page
let unkeptDeviceId: string | null = null;

function deviceId(): string {
  const kept = readText(DEVICE_KEY);
  if (kept) {
    return kept;
  } else {
    const made = unkeptDeviceId ?? crypto.randomUUID();
    if (!writeText(DEVICE_KEY, made)) {
      unkeptDeviceId = made;
    }
    return made;
  }
}

/** The profile was deleted on another device; this device's copy is gone too. */
export class ProfileDeletedError extends ShownError {
  constructor() {
    super("Your profile was deleted on another device.");
    this.name = "ProfileDeletedError";
  }
}

/** Run `work` while no other tab of this browser runs work under the same name. */
function exclusively<Result>(
  name: string,
  work: () => Promise<Result>,
): Promise<Result> {
  const locks = globalThis.navigator?.locks;
  if (locks) {
    return locks.request(name, work) as Promise<Result>;
  } else {
    return work();
  }
}

/*
 * The channel filters, watched marks and settings, synced through the Drive app folder.
 * Each device writes only its own file and reads everyone's, so two devices
 * never write the same file. Edits apply in memory at once, are kept in local
 * storage until uploaded (so a reload or a closed tab loses nothing), and go up
 * after a short pause. Tabs of one browser are one device: each takes in what
 * the others kept in local storage before it writes there or uploads.
 */
export class SyncStore {
  private readonly ownId = deviceId();
  private readonly ownName = `device-${this.ownId}.json`;
  private readonly localKey: string;
  // localStorage key: this device's Drive file id, once uploaded for the account
  private readonly uploadedKey: string;
  private readonly lockName: string;
  private own: DeviceFile;
  private ownFileId: string | null = null;
  // whether ownFileId is known; saving before then would create a second file
  private listed = false;
  // how many files this store has created: a listing asked for before a create ended can't be trusted
  private creates = 0;
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
  /** Whether Drive held another device's file at the last load; null before one. */
  profileFound: boolean | null = null;

  /**
   * Keeps `accountId`'s edits; `getToken` supplies Drive access, and `renew`
   * a new token when Google refuses that one. `onDeleted` runs when the
   * profile turns out to be deleted, on another device or in another tab.
   */
  constructor(
    accountId: string,
    private readonly getToken: () => Promise<string>,
    private readonly onDeleted: () => void = () => undefined,
    private readonly renew: (() => Promise<string>) | null = null,
  ) {
    this.localKey = `subtube.sync.${accountId}`;
    this.uploadedKey = `subtube.uploaded.${accountId}`;
    this.lockName = `subtube.save.${accountId}`;
    this.own = this.readStored() ?? emptyDeviceFile();
    this.merged = this.own;
  }

  /** Run a Drive request; when Google refuses the token, renew it and run the request once more. */
  private async withToken<Result>(
    request: (token: string) => Promise<Result>,
  ): Promise<Result> {
    try {
      return await request(await this.getToken());
    } catch (caught) {
      if (caught instanceof TokenExpiredError && this.renew) {
        return request(await this.renew());
      } else {
        throw caught;
      }
    }
  }

  private readStored(): DeviceFile | null {
    return parseDeviceFile(readJson<unknown>(this.localKey));
  }

  /** Take in what another tab kept since this one last looked; says whether that changed anything here. */
  private absorbStored(): boolean {
    const stored = this.readStored();
    const merged = stored ? mergeOwnCopies(this.own, stored) : this.own;
    if (sameOwnEntries(merged, this.own)) {
      return false;
    } else {
      this.own = merged;
      this.edits += 1;
      return true;
    }
  }

  private writeLocal(): void {
    this.absorbStored();
    // when storage refuses, the upload still carries it
    writeJson(this.localKey, this.own);
  }

  /** What the uploaded mark holds: the file's id, "1" from before ids were kept, or null. */
  private uploadedMark(): string | null {
    return readText(this.uploadedKey);
  }

  private markUploaded(fileId: string): void {
    // when storage refuses, a delete made elsewhere goes unnoticed on this device
    writeText(this.uploadedKey, fileId);
  }

  /** Stop uploading and forget what this store holds in memory. */
  private forget(): void {
    this.close();
    this.own = emptyDeviceFile();
    this.others.clear();
    this.merged = this.own;
    this.ownFileId = null;
    this.listed = false;
  }

  /** Stop uploading and forget everything kept for the account on this device. */
  private wipe(): void {
    this.forget();
    writeText(this.localKey, null);
    writeText(this.uploadedKey, null);
  }

  /**
   * Another tab changed local storage (the window's `storage` event): take
   * in the edits it kept, or, when it removed this account's copy, forget
   * the profile here too, as that tab deleted it.
   */
  storageChanged(key: string | null, newValue: string | null): void {
    if (key !== this.localKey || this.closed) {
      return;
    }
    if (newValue === null) {
      this.forget();
      this.onDeleted();
    } else if (this.absorbStored()) {
      this.remerge();
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
    await this.withToken((token) => this.loadWith(token));
  }

  /** The folder's files, listed after every create of this store ended. */
  private async listing(token: string): Promise<DriveFile[]> {
    let created = this.creates;
    let files = await listAppFiles(token);
    while (created !== this.creates) {
      created = this.creates;
      files = await listAppFiles(token);
    }
    return files;
  }

  /**
   * This device's files among a listing, by id; the folder's files as last
   * listed come back too. A listing without one, though one was uploaded,
   * is looked at twice before it counts as the profile deleted elsewhere:
   * the file is asked for by its id, and the folder listed again.
   */
  private async ownFiles(
    listed: DriveFile[],
    token: string,
  ): Promise<{ files: DriveFile[]; ownIds: string[] }> {
    const idsIn = (files: DriveFile[]) =>
      files
        .filter(({ name }) => name === this.ownName)
        .map(({ id }) => id)
        .sort();
    const ownIds = idsIn(listed);
    const mark = this.uploadedMark();
    if (ownIds.length > 0 || mark === null) {
      return { files: listed, ownIds };
    } else {
      const knownId =
        this.ownFileId ?? (mark === UPLOADED_WITHOUT_ID ? null : mark);
      if (knownId !== null && (await fileExists(knownId, token))) {
        return { files: listed, ownIds: [knownId] };
      } else {
        const again = await this.listing(token);
        return { files: again, ownIds: idsIn(again) };
      }
    }
  }

  private async loadWith(token: string): Promise<void> {
    this.absorbStored();
    const { files, ownIds } = await this.ownFiles(
      await this.listing(token),
      token,
    );
    if (ownIds.length === 0 && this.uploadedMark() !== null) {
      this.wipe();
      this.onDeleted();
      throw new ProfileDeletedError();
    }
    const live = new Set<string>();
    const [keptId] = ownIds;
    let remote: DeviceFile | null = null;
    const merged: string[] = [];
    await Promise.all([
      ...ownIds.map(async (fileId) => {
        const copy = parseDeviceFile(await downloadJson(fileId, token));
        if (fileId === keptId) {
          remote = copy;
        } else if (copy) {
          merged.push(fileId);
        }
        if (copy) {
          this.own = mergeOwnCopies(this.own, copy);
        }
      }),
      ...files.map(async (entry) => {
        const fileDeviceId = deviceIdFromName(entry.name);
        if (fileDeviceId === null || fileDeviceId === this.ownId) {
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
    ]);
    // a second file under this device's name, made by two tabs saving at once
    await Promise.all(merged.map((fileId) => deleteFile(fileId, token)));
    for (const id of this.others.keys()) {
      if (!live.has(id)) {
        this.others.delete(id);
      }
    }
    this.ownFileId = keptId ?? null;
    this.ownUnreadable = keptId !== undefined && remote === null;
    if (keptId !== undefined) {
      this.markUploaded(keptId);
    }
    this.listed = true;
    this.profileFound = hasProfile(
      files.map(({ name }) => name).filter((name) => name !== this.ownName),
    );
    this.lastSynced = Date.now();
    this.writeLocal();
    this.remerge();
    // edits Drive's copy lacks, e.g. kept from before a reload or made in another tab
    const unsent = !sameOwnEntries(this.own, remote ?? emptyDeviceFile());
    if (unsent && this.sentEdits === this.edits) {
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

  /** Every channel's filter as last saved on any device, by channel id; channels no longer listed too. */
  savedFilters(): Record<string, ChannelFilter> {
    return Object.fromEntries(
      Object.entries(this.merged.channels).map(([channelId, { filter }]) => [
        channelId,
        filter,
      ]),
    );
  }

  /** Save several channels' filters in one save, each as {@link setFilter} does. */
  setFilters(filters: Readonly<Record<string, ChannelFilter>>): void {
    const at = Date.now();
    for (const [channelId, filter] of Object.entries(filters)) {
      this.own.channels[channelId] = editedEntry(this.own.channels[channelId], {
        at,
        filter: editedFilter(filter),
      });
    }
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
    this.writeLocal();
    this.remerge();
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
    this.writeLocal();
    this.remerge();
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
      await this.saving.catch(() => undefined);
    }
    if (this.closed) {
      return;
    }
    // one tab at a time, so two tabs never both create this device's file
    this.saving = exclusively(this.lockName, () => this.upload()).finally(
      () => {
        this.saving = null;
      },
    );
    return this.saving;
  }

  private async upload(triedAgain = false): Promise<void> {
    if (!this.listed || !this.ownFileId) {
      // also right before a create: another tab may have made the file since
      await this.load();
    }
    if (this.ownUnreadable || this.closed) {
      return;
    }
    this.absorbStored();
    const sending = this.edits;
    this.own = sanitizeDeviceFile(pruneDeviceFile(this.own, Date.now()));
    const content = this.own;
    try {
      await this.withToken(async (token) => {
        if (this.ownFileId) {
          await updateJson(this.ownFileId, content, token);
        } else {
          const created = await createJson(this.ownName, content, token);
          this.ownFileId = created.id;
          this.creates += 1;
        }
      });
    } catch (caught) {
      const gone =
        caught instanceof GoogleRequestError && caught.status === 404;
      if (gone && !triedAgain) {
        // the file went since it was listed: the load says whether the profile did
        this.listed = false;
        this.ownFileId = null;
        return this.upload(true);
      } else {
        throw caught;
      }
    }
    this.sentEdits = sending;
    if (this.ownFileId) {
      this.markUploaded(this.ownFileId);
    }
    this.lastSynced = Date.now();
    this.remerge();
    writeJson(this.localKey, this.own);
  }

  /**
   * Delete the profile: every device's file in the Drive folder, this
   * device's last, then what this device kept. If Drive fails, nothing kept
   * here changes and uploads resume.
   */
  async deleteProfile(): Promise<void> {
    const pending = this.saveTimer !== null;
    this.close();
    while (this.saving) {
      await this.saving.catch(() => undefined);
    }
    try {
      await this.withToken(async (token) => {
        const files = await listAppFiles(token);
        const mine = (file: DriveFile) => file.name === this.ownName;
        const ordered = [
          ...files.filter((file) => !mine(file)),
          ...files.filter(mine),
        ];
        for (const file of ordered) {
          await deleteFile(file.id, token);
        }
      });
    } catch (caught) {
      this.closed = false;
      this.listed = false;
      if (pending) {
        this.scheduleSave();
      }
      throw caught;
    }
    this.wipe();
  }
}
