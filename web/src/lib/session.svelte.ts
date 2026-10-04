import {
  getValidToken,
  hasToken,
  signIn,
  signOut,
  silentRefresh,
} from "./auth";
import { clearChannelInfo } from "./channel-info";
import { SyncStore } from "./sync-store";
import {
  type ChannelSummary,
  fetchMyChannel,
  TokenExpiredError,
} from "./youtube";

/** localStorage key: who was signed in, so a reload paints their cached feed at once. */
const STORED_ACCOUNT = "subtube.account";
/** localStorage key: set once first-run setup is finished on this browser. */
const SETUP_DONE = "subtube.setupDone";

/** Earlier versions kept the last feed in IndexedDB; nothing reads it now. */
function dropOldFeedCache(): void {
  try {
    indexedDB.deleteDatabase("subtube");
  } catch {
    // nothing was kept
  }
}

function readStored<Value>(key: string): Value | null {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as Value) : null;
  } catch {
    return null;
  }
}

function writeStored(key: string, value: unknown): void {
  try {
    if (value === null) {
      localStorage.removeItem(key);
    } else {
      localStorage.setItem(key, JSON.stringify(value));
    }
  } catch {
    // a reload just asks again
  }
}

/**
 * Who is signed in and whether a token is at hand. A returning account paints
 * from its cache at once and renews its token silently through the extension;
 * only when that fails does it need a click.
 */
export class Session {
  /** the signed-in account's channel, or null when signed out */
  account: ChannelSummary | null = $state.raw(
    readStored<ChannelSummary>(STORED_ACCOUNT),
  );
  /** whether a token is at hand */
  ready = $state(false);
  /** whether a token was at hand and Google stopped accepting it */
  expired = $state(false);
  /** whether a silent renewal is running */
  checking = $state(false);
  /** whether an interactive sign-in is running */
  connecting = $state(false);
  /** why the last sign-in failed */
  error: string | null = $state(null);
  /** whether first-run setup is finished on this browser */
  setupDone = $state(readStored<boolean>(SETUP_DONE) === true);
  /** the account's synced filters and watched marks */
  store: SyncStore | null = $state.raw(null);

  constructor() {
    dropOldFeedCache();
    if (this.account) {
      this.store = this.openStore(this.account.channelId);
    }
  }

  private openStore(accountId: string): SyncStore {
    return new SyncStore(accountId, getValidToken, () =>
      this.profileDeletedElsewhere(accountId),
    );
  }

  /** Forget the channel names and the setup-done mark; the store forgets its own part. */
  private forgetLocal(): void {
    clearChannelInfo();
    writeStored(SETUP_DONE, null);
  }

  /** Another device deleted the profile: start setup again, still signed in. */
  private profileDeletedElsewhere(accountId: string): void {
    if (this.account?.channelId !== accountId) {
      return;
    }
    this.forgetLocal();
    this.store = this.openStore(accountId);
    this.setupDone = false;
  }

  /** Get a token without UI for a returning account. */
  async restore(): Promise<void> {
    if (!this.account) {
      return;
    } else if (hasToken()) {
      this.ready = true;
      return;
    }
    this.checking = true;
    try {
      await silentRefresh();
      this.ready = true;
    } catch {
      this.ready = false;
    } finally {
      this.checking = false;
    }
  }

  /** Interactive sign-in; it can pick a different Google account, which swaps everything. */
  async signIn(): Promise<boolean> {
    this.connecting = true;
    this.error = null;
    try {
      const token = await signIn();
      const mine = await fetchMyChannel(token);
      if (mine.channelId !== this.account?.channelId) {
        // its unsent edits stay in local storage for that account's next sign-in
        this.store?.close();
        this.store = this.openStore(mine.channelId);
      }
      writeStored(STORED_ACCOUNT, mine);
      this.account = mine;
      this.ready = true;
      this.expired = false;
      return true;
    } catch (caught) {
      this.error = (caught as Error).message;
      return false;
    } finally {
      this.connecting = false;
    }
  }

  /** The token stopped working; the next load asks for a click. */
  tokenLost(): void {
    this.ready = false;
    this.expired = true;
  }

  /** Mark first-run setup finished. */
  finishSetup(): void {
    writeStored(SETUP_DONE, true);
    this.setupDone = true;
  }

  /**
   * Delete the account's profile from Drive and from this browser, then sign
   * out and return to the first setup screen. Throws, changing nothing here,
   * when Drive can't be reached.
   */
  async deleteProfile(): Promise<void> {
    const accountId = this.account?.channelId;
    if (!accountId || !this.store) {
      return;
    }
    try {
      await this.store.deleteProfile();
    } catch (caught) {
      if (!(caught instanceof TokenExpiredError)) {
        throw caught;
      }
      // Google refused the token: renew it and try once more
      await silentRefresh();
      await this.store.deleteProfile();
    }
    this.forgetLocal();
    await signOut().catch(() => undefined);
    writeStored(STORED_ACCOUNT, null);
    this.store = null;
    this.ready = false;
    this.account = null;
    this.setupDone = false;
  }

  /** Upload what's unsaved, then forget the account on this browser. */
  async signOut(): Promise<void> {
    await this.store?.save().catch(() => undefined);
    this.store?.close();
    await signOut();
    writeStored(STORED_ACCOUNT, null);
    this.store = null;
    this.ready = false;
    this.account = null;
  }
}
