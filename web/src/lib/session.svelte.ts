import {
  expectAccount,
  forgetToken,
  getValidToken,
  hasToken,
  revokeAccess,
  signIn,
  signOut,
  silentRefresh,
} from "./auth";
import { fetchDriveUser } from "./drive";
import {
  SignInCancelledError,
  SignInRequiredError,
  shownMessage,
} from "./errors";
import { keysWith, readJson, readText, writeJson, writeText } from "./storage";
import { SyncStore } from "./sync-store";
import type { ChannelInfo } from "./types";
import { fetchMyChannel } from "./youtube";

/** localStorage key: who is signed in on this browser. */
const STORED_ACCOUNT = "subtube.account";
/** localStorage key prefix: set, per account, once first-run setup is finished on this browser. */
const SETUP_DONE_PREFIX = "subtube.setupDone.";
// the one mark earlier versions kept for the whole browser
const OLD_SETUP_DONE = "subtube.setupDone";

/** The signed-in account: its YouTube channel, which keys what is kept for it, and its Google identity. */
export interface Account extends ChannelInfo {
  /** the Google account's id as Drive reports it; absent when it was signed in before this was kept */
  googleId?: string;
  /** the Google account's address, when Drive shares it */
  email?: string;
}

/** Earlier versions kept the last feed in IndexedDB; nothing reads it now. */
function dropOldFeedCache(): void {
  try {
    indexedDB.deleteDatabase("subtube");
  } catch {
    // nothing was kept
  }
}

/** Whether setup is finished for an account on this browser. */
export function setupDoneFor(accountId: string): boolean {
  return readText(SETUP_DONE_PREFIX + accountId) !== null;
}

/** Earlier versions marked setup done for the browser: the mark goes to the account signed in then. */
function moveOldSetupMark(account: Account | null): void {
  if (readJson<boolean>(OLD_SETUP_DONE) === true && account) {
    writeText(SETUP_DONE_PREFIX + account.channelId, "1");
  }
  writeText(OLD_SETUP_DONE, null);
}

/**
 * Who is signed in and whether a token is at hand. A returning account
 * renews its token silently through the extension; only when that fails does
 * it need a click. Tabs of one browser share the account: a sign-in, sign-out
 * or profile delete in one is followed by the others.
 */
export class Session {
  /** the signed-in account, or null when signed out */
  account: Account | null = $state.raw(readJson<Account>(STORED_ACCOUNT));
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
  /** whether first-run setup is finished for the account on this browser */
  setupDone = $state(false);
  /** whether setup was ever finished on this browser, for any account */
  returning = $state(false);
  /** the account's synced filters and watched marks */
  store: SyncStore | null = $state.raw(null);
  // an interactive sign-in holds a token whose account isn't known yet: no store may use it
  private switching = false;

  constructor() {
    dropOldFeedCache();
    moveOldSetupMark(this.account);
    this.returning = keysWith(SETUP_DONE_PREFIX).length > 0;
    if (this.account) {
      this.setupDone = setupDoneFor(this.account.channelId);
      this.store = this.openStore(this.account.channelId);
      this.expect(this.account);
    }
    if (typeof window !== "undefined") {
      window.addEventListener("storage", (event) => {
        if (event.key === STORED_ACCOUNT) {
          this.follow(readJson<Account>(STORED_ACCOUNT));
        } else {
          this.store?.storageChanged(event.key, event.newValue);
        }
      });
    }
  }

  private openStore(accountId: string): SyncStore {
    const usable = (): boolean =>
      !this.switching && this.account?.channelId === accountId;
    return new SyncStore(
      accountId,
      () =>
        usable() ? getValidToken() : Promise.reject(new SignInRequiredError()),
      () => this.profileDeleted(accountId),
      () =>
        usable()
          ? silentRefresh(true)
          : Promise.reject(new SignInRequiredError()),
    );
  }

  /** Have silent renewals refuse a token that is another Google account's. */
  private expect(account: Account): void {
    expectAccount({
      ...(account.email ? { loginHint: account.email } : {}),
      owns: (token) => this.owns(account, token),
    });
  }

  /** Whether a token is `account`'s; an account kept without its Google id gets it here. */
  private async owns(account: Account, token: string): Promise<boolean> {
    if (account.googleId) {
      return (await fetchDriveUser(token)).permissionId === account.googleId;
    } else {
      const [mine, user] = await Promise.all([
        fetchMyChannel(token),
        fetchDriveUser(token),
      ]);
      const same = mine.channelId === account.channelId;
      if (same && this.account?.channelId === account.channelId) {
        this.keep({
          ...account,
          googleId: user.permissionId,
          email: user.emailAddress,
        });
      }
      return same;
    }
  }

  private keep(account: Account): void {
    writeJson(STORED_ACCOUNT, account);
    this.account = account;
    this.expect(account);
  }

  /** Forget the account's setup-done mark; the store forgets its own part. */
  private forgetLocal(accountId: string): void {
    writeText(SETUP_DONE_PREFIX + accountId, null);
  }

  /** The profile was deleted on another device or in another tab: start setup again, still signed in. */
  private profileDeleted(accountId: string): void {
    if (this.account?.channelId === accountId) {
      this.forgetLocal(accountId);
      this.store = this.openStore(accountId);
      this.setupDone = false;
    }
  }

  /** Another tab signed in, out or as someone else: be where it is. */
  private follow(next: Account | null): void {
    if (next?.channelId !== this.account?.channelId) {
      this.store?.close();
      forgetToken();
      this.ready = false;
      this.expired = false;
      this.account = next;
      if (next) {
        this.store = this.openStore(next.channelId);
        this.setupDone = setupDoneFor(next.channelId);
        this.expect(next);
        void this.restore();
      } else {
        this.store = null;
        this.setupDone = false;
        expectAccount(null);
      }
    }
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
    this.switching = true;
    try {
      const token = await signIn();
      const [mine, user] = await Promise.all([
        fetchMyChannel(token),
        fetchDriveUser(token),
      ]);
      if (mine.channelId !== this.account?.channelId) {
        // its unsent edits stay in local storage for that account's next sign-in
        this.store?.close();
        this.store = this.openStore(mine.channelId);
        this.setupDone = setupDoneFor(mine.channelId);
      }
      this.keep({
        ...mine,
        googleId: user.permissionId,
        email: user.emailAddress,
      });
      this.ready = true;
      this.expired = false;
      return true;
    } catch (caught) {
      if (!(caught instanceof SignInCancelledError)) {
        console.error(caught);
        this.error = shownMessage(caught);
      }
      return false;
    } finally {
      this.switching = false;
      this.connecting = false;
    }
  }

  /** The token stopped working; the next load asks for a click. */
  tokenLost(): void {
    this.ready = false;
    this.expired = true;
  }

  /** Mark first-run setup finished for the account. */
  finishSetup(): void {
    if (this.account) {
      writeText(SETUP_DONE_PREFIX + this.account.channelId, "1");
      this.setupDone = true;
      this.returning = true;
    }
  }

  private signedOut(): void {
    writeJson(STORED_ACCOUNT, null);
    expectAccount(null);
    this.store = null;
    this.ready = false;
    this.account = null;
    this.setupDone = false;
  }

  /**
   * Delete the account's profile from Drive and from this browser, then
   * withdraw Google's grant, sign out and return to the first setup screen.
   * Throws, changing nothing here, when Drive can't be reached.
   */
  async deleteProfile(): Promise<void> {
    const accountId = this.account?.channelId;
    if (accountId && this.store) {
      await this.store.deleteProfile();
      this.forgetLocal(accountId);
      this.returning = keysWith(SETUP_DONE_PREFIX).length > 0;
      await revokeAccess().catch(() => undefined);
      this.signedOut();
    }
  }

  /** Upload what's unsaved, then forget the account on this browser; Google's grant stays. */
  async signOut(): Promise<void> {
    await this.store?.save().catch(() => undefined);
    this.store?.close();
    // signed out here even when the extension can't be told
    await signOut().catch(() => undefined);
    this.signedOut();
  }
}
