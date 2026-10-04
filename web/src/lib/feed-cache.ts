import type { Channel, FeedItem } from "./types";

/*
 * A tiny IndexedDB key/value store (one record per account) holding the last feed, so
 * a reload paints instantly while fresh data loads behind it. IndexedDB rather
 * than localStorage because the videos can exceed the ~5MB string cap, and
 * structured clone stores Maps/Sets directly. The channel filters ride along so a
 * reload filters the cached feed on the first frame, without waiting on a read.
 */
const DB_NAME = "subtube";
const STORE = "feed";
/** Each bump discards older records rather than migrating, costing one blank load. */
const DB_VERSION = 4;

/** The last feed one account loaded. */
export interface CachedFeed {
  /** the channels with their filters, so a reload paints already filtered */
  channels: Map<string, Channel>;
  /** the loaded items that are marked watched */
  watched: Set<string>;
  /** every loaded item */
  items: FeedItem[];
  /** when it was saved, in epoch milliseconds */
  cachedAt: number;
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (database.objectStoreNames.contains(STORE)) {
        database.deleteObjectStore(STORE);
      }
      database.createObjectStore(STORE);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/** The account's cached feed, or null when there is none or it can't be read. */
export async function loadCachedFeed(
  accountId: string,
): Promise<CachedFeed | null> {
  try {
    const db = await openDb();
    return await new Promise<CachedFeed | null>((resolve, reject) => {
      const request = db
        .transaction(STORE, "readonly")
        .objectStore(STORE)
        .get(accountId);
      request.onsuccess = () => resolve((request.result as CachedFeed) ?? null);
      request.onerror = () => reject(request.error);
    });
  } catch {
    return null;
  }
}

/** Replace the account's cached feed; failures are ignored. */
export async function saveCachedFeed(
  accountId: string,
  feed: CachedFeed,
): Promise<void> {
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(STORE, "readwrite");
      transaction.objectStore(STORE).put(feed, accountId);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } catch {
    // Best-effort cache; a failure here just means no instant paint next time.
  }
}

/** Forget the account's cached feed; failures are ignored. */
export async function deleteCachedFeed(accountId: string): Promise<void> {
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(STORE, "readwrite");
      transaction.objectStore(STORE).delete(accountId);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } catch {
    // a leftover cache is replaced by the next load
  }
}

/**
 * Fold a watched change into the cached feed as it is made. The whole-feed save
 * only happens at the end of a load, so without this a reload would repaint every
 * mark since that load as unwatched until the next one finished reading them back.
 */
export async function cacheWatched(
  accountId: string,
  id: string,
  isWatched: boolean,
): Promise<void> {
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      // One transaction for the read and the write, so a whole-feed save can't
      // land between them and be overwritten by what it replaced.
      const transaction = db.transaction(STORE, "readwrite");
      const store = transaction.objectStore(STORE);
      const request = store.get(accountId);
      request.onsuccess = () => {
        const cached = request.result as CachedFeed | undefined;
        if (!cached || cached.watched.has(id) === isWatched) {
          return;
        }
        const watched = new Set(cached.watched);
        if (isWatched) {
          watched.add(id);
        } else {
          watched.delete(id);
        }
        store.put({ ...cached, watched }, accountId);
      };
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  } catch {
    // Best-effort; the next full save carries the mark anyway.
  }
}
