import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { ProfileDeletedError, SyncStore } from "./sync-store";

/** A Drive app folder and a browser's local storage, faked for one test. */
interface Fake {
  /** the folder's files by id */
  drive: Map<string, { name: string; body: string }>;
  /** local storage */
  kept: Map<string, string>;
  /** every request made, as "METHOD path" */
  requests: string[];
  /** statuses to answer the next requests with instead of asking the folder; 0 lets one through */
  failNext: number[];
  /** runs before each listing is answered */
  beforeListing: () => void;
  /** the open tabs, which each hear of a write to local storage as the `storage` event tells them */
  tabs: SyncStore[];
}

let fake: Fake;
const realFetch = globalThis.fetch;

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status });
}

function answer(input: string | URL | Request, init?: RequestInit): Response {
  const url = new URL(String(input));
  const method = init?.method ?? "GET";
  const fileId = url.pathname.split("/files/")[1];
  fake.requests.push(`${method} ${fileId ?? "files"}`);
  const failure = fake.failNext.shift();
  if (failure) {
    return json({}, failure);
  } else if (method === "GET" && fileId === undefined) {
    fake.beforeListing();
    return json({
      files: Array.from(fake.drive, ([id, file]) => ({
        id,
        name: file.name,
        modifiedTime: file.body,
      })),
    });
  } else if (method === "POST") {
    const parts = String(init?.body).split("\r\n");
    const id = `file${fake.drive.size + 1}-${fake.requests.length}`;
    fake.drive.set(id, { name: JSON.parse(parts[3]).name, body: parts[7] });
    return json({ id, modifiedTime: parts[7] });
  } else {
    const file = fake.drive.get(fileId ?? "");
    if (!file) {
      return json({}, 404);
    } else if (method === "PATCH") {
      file.body = String(init?.body);
      return json({ id: fileId, modifiedTime: file.body });
    } else if (method === "DELETE") {
      fake.drive.delete(fileId ?? "");
      return new Response(null, { status: 204 });
    } else {
      return new Response(
        url.searchParams.has("alt")
          ? file.body
          : JSON.stringify({ id: fileId }),
      );
    }
  }
}

beforeEach(() => {
  fake = {
    drive: new Map(),
    kept: new Map(),
    requests: [],
    failNext: [],
    beforeListing: () => undefined,
    tabs: [],
  };
  (globalThis as { localStorage?: unknown }).localStorage = {
    getItem: (key: string) => fake.kept.get(key) ?? null,
    setItem: (key: string, value: string) => {
      fake.kept.set(key, value);
      fake.tabs.forEach((store) => void store.storageChanged(key, value));
    },
    removeItem: (key: string) => {
      fake.kept.delete(key);
      fake.tabs.forEach((store) => void store.storageChanged(key, null));
    },
  };
  globalThis.fetch = (async (
    input: string | URL | Request,
    init?: RequestInit,
  ) => answer(input, init)) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
  delete (globalThis as { localStorage?: unknown }).localStorage;
});

function tab(onDeleted: () => void = () => undefined): SyncStore {
  const store = new SyncStore(
    "acct",
    async () => "token",
    onDeleted,
    async () => "new",
  );
  fake.tabs.push(store);
  return store;
}

/** The watched ids in each of the folder's files. */
function watchedInDrive(): string[][] {
  return Array.from(fake.drive.values(), (file) =>
    Object.keys(JSON.parse(file.body).watched).sort(),
  );
}

async function uploaded(...ids: string[]): Promise<void> {
  const first = tab();
  await first.load();
  first.setWatchedAll(ids, true);
  await first.save();
  first.close();
}

describe("two tabs of one browser", () => {
  test("a tab's upload keeps what another tab saved since it loaded", async () => {
    await uploaded("W");
    const left = tab();
    const right = tab();
    await left.load();
    await right.load();
    left.setWatched("X", true);
    await left.save();
    right.setWatched("Y", true);
    await right.save();
    expect(watchedInDrive()).toEqual([["W", "X", "Y"]]);
    left.close();
    right.close();
    const reopened = tab();
    await reopened.load();
    expect(reopened.watchedEntry("X")?.watched).toBe(true);
    expect(reopened.watchedEntry("Y")?.watched).toBe(true);
    reopened.close();
  });

  test("an edit another tab only kept locally is uploaded by this one", async () => {
    await uploaded("W");
    const left = tab();
    const right = tab();
    await left.load();
    await right.load();
    left.setProgress("X", 30, false, false);
    left.close();
    right.setWatched("Y", true);
    await right.save();
    expect(watchedInDrive()).toEqual([["W", "X", "Y"]]);
    right.close();
  });

  test("the storage event brings another tab's edit into this one", async () => {
    const left = tab();
    const right = tab();
    left.setWatched("X", true);
    right.storageChanged(
      "subtube.sync.acct",
      fake.kept.get("subtube.sync.acct") ?? null,
    );
    expect(right.watchedEntry("X")?.watched).toBe(true);
    left.close();
    right.close();
  });

  test("a write that crossed another tab's keeps both tabs' edits in local storage", () => {
    const left = tab();
    const right = tab();
    // each writes before it hears of the other
    fake.tabs = [];
    left.setWatched("X", true);
    const fromLeft = fake.kept.get("subtube.sync.acct") ?? null;
    right.setWatched("Y", true);
    right.storageChanged("subtube.sync.acct", fromLeft);
    expect(
      Object.keys(
        JSON.parse(fake.kept.get("subtube.sync.acct") ?? "{}").watched,
      ).sort(),
    ).toEqual(["X", "Y"]);
    left.close();
    right.close();
  });

  test("a playing video's position reaches local storage late, or when the tab is hidden or closed", async () => {
    const store = tab();
    await store.load();
    const kept = () =>
      JSON.parse(fake.kept.get("subtube.sync.acct") ?? "{}").watched.X
        ?.position;
    store.setProgress("X", 30, false, false);
    expect(store.watchedEntry("X")?.position).toBe(30);
    expect(kept()).toBeUndefined();
    store.flush();
    expect(kept()).toBe(30);
    store.setProgress("X", 35, false, false);
    expect(kept()).toBe(30);
    store.setProgress("X", 40, false, true);
    expect(kept()).toBe(40);
    store.setProgress("X", 45, false, false);
    store.close();
    expect(kept()).toBe(45);
  });

  test("a position saved here doesn't hide a later one from another device", async () => {
    const other = "device-other.json";
    fake.drive.set("other", {
      name: other,
      body: JSON.stringify({
        version: 1,
        channels: {},
        watched: { X: { at: Date.now() + 60_000, watched: true } },
      }),
    });
    const store = tab();
    await store.load();
    store.setProgress("X", 30, false, false);
    expect(store.watchedEntry("X")?.watched).toBe(true);
    store.close();
  });

  test("a load downloads this device's file only when it isn't this store's last upload", async () => {
    const left = tab();
    await left.load();
    left.setWatched("X", true);
    await left.save();
    const [fileId] = fake.drive.keys();
    const downloads = () =>
      fake.requests.filter((request) => request === `GET ${fileId}`).length;
    await left.load();
    expect(downloads()).toBe(0);

    const right = tab();
    await right.load();
    expect(downloads()).toBe(1);
    right.setWatched("Y", true);
    await right.save();
    await left.load();
    expect(downloads()).toBe(2);
    expect(left.watchedEntry("Y")?.watched).toBe(true);
    left.close();
    right.close();
  });

  test("both saving for the first time make one file", async () => {
    const left = tab();
    const right = tab();
    await left.load();
    await right.load();
    left.setWatched("X", true);
    await left.save();
    right.setWatched("Y", true);
    await right.save();
    expect(watchedInDrive()).toEqual([["X", "Y"]]);
    left.close();
    right.close();
  });

  test("a second file under this device's name is merged into the first and deleted", async () => {
    await uploaded("W");
    const [name] = Array.from(fake.drive.values(), (file) => file.name);
    fake.drive.set("zz-second", {
      name,
      body: JSON.stringify({
        version: 1,
        channels: {},
        watched: { Z: { at: Date.now(), watched: true } },
      }),
    });
    const store = tab();
    await store.load();
    expect(store.watchedEntry("Z")?.watched).toBe(true);
    await store.save();
    expect(watchedInDrive()).toEqual([["W", "Z"]]);
    store.close();
  });

  test("after another tab deleted the profile this one forgets it and uploads nothing", async () => {
    await uploaded("W");
    let deletions = 0;
    const left = tab();
    const right = tab(() => {
      deletions += 1;
    });
    await left.load();
    await right.load();
    await left.deleteProfile();
    right.storageChanged("subtube.sync.acct", null);
    expect(deletions).toBe(1);
    expect(right.watchedEntry("W")).toBeUndefined();
    right.setWatched("Z", true);
    await right.save();
    expect(fake.drive.size).toBe(0);
  });
});

describe("a profile deleted on another device", () => {
  test("is noticed when this device's file is gone by its id and from a second listing", async () => {
    await uploaded("W");
    let deletions = 0;
    const store = tab(() => {
      deletions += 1;
    });
    await store.load();
    fake.drive.clear();
    fake.requests.length = 0;
    await expect(store.load()).rejects.toBeInstanceOf(ProfileDeletedError);
    expect(deletions).toBe(1);
    expect(
      fake.requests.filter((request) => request === "GET files"),
    ).toHaveLength(2);
    expect(fake.kept.has("subtube.sync.acct")).toBe(false);
  });

  test("a listing that misses the file is not believed while the file answers by its id", async () => {
    await uploaded("W");
    const [[fileId, file]] = Array.from(fake.drive);
    const store = tab();
    fake.beforeListing = () => {
      fake.drive.delete(fileId);
      fake.beforeListing = () => undefined;
    };
    const loading = store.load();
    await Promise.resolve();
    fake.drive.set(fileId, file);
    await loading;
    expect(store.watchedEntry("W")?.watched).toBe(true);
    store.close();
  });

  test("a save whose file is gone finds the profile deleted", async () => {
    await uploaded("W");
    const store = tab();
    await store.load();
    fake.drive.clear();
    store.setWatched("X", true);
    await expect(store.save()).rejects.toBeInstanceOf(ProfileDeletedError);
    expect(fake.drive.size).toBe(0);
  });
});

describe("a device's first file", () => {
  test("is not a profile found for the account", async () => {
    const store = tab();
    await store.load();
    store.setWatched("X", true);
    await store.save();
    await store.load();
    expect(store.profileFound).toBe(false);
    fake.drive.set("other", { name: "device-other.json", body: "{}" });
    await store.load();
    expect(store.profileFound).toBe(true);
    store.close();
  });
});

describe("a refused token", () => {
  test("is renewed once for a save", async () => {
    await uploaded("W");
    const store = tab();
    await store.load();
    store.setWatched("X", true);
    fake.failNext = [401];
    await store.save();
    expect(watchedInDrive()).toEqual([["W", "X"]]);
    store.close();
  });

  test("is renewed once for a load", async () => {
    await uploaded("W");
    const store = tab();
    fake.failNext = [401];
    await store.load();
    expect(store.watchedEntry("W")?.watched).toBe(true);
    store.close();
  });
});

describe("deleting the profile", () => {
  test("deletes this device's file last and keeps everything when Drive fails", async () => {
    await uploaded("W");
    fake.drive.set("other", { name: "device-other.json", body: "{}" });
    const store = tab();
    await store.load();
    fake.requests.length = 0;
    fake.failNext = [0, 500];
    await expect(store.deleteProfile()).rejects.toThrow();
    expect(fake.kept.has("subtube.sync.acct")).toBe(true);
    await store.load();
    expect(store.watchedEntry("W")?.watched).toBe(true);
    await store.deleteProfile();
    const deleted = fake.requests.filter((request) =>
      request.startsWith("DELETE"),
    );
    expect(deleted.at(-1)).not.toBe("DELETE other");
    expect(fake.drive.size).toBe(0);
    expect(fake.kept.has("subtube.sync.acct")).toBe(false);
  });
});
