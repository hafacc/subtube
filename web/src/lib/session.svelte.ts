import {
  moveAccountEntries,
  oldAccountIds,
  SETUP_DONE_PREFIX,
} from "./account-entries";
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
import { type DriveUser, fetchDriveUser } from "./drive";
import {
  SignInCancelledError,
  SignInRequiredError,
  shownMessage,
} from "./errors";
import { keysWith, readJson, readText, writeJson, writeText } from "./storage";
import { SyncStore } from "./sync-store";
import { fetchOwnChannelId } from "./youtube";

/** localStorage key: who is signed in on this browser. */
const STORED_ACCOUNT = "subtube.account";
// the one mark earlier versions kept for the whole browser
const OLD_SETUP_DONE = "subtube.setupDone";

/** The signed-in Google account, as Drive reports it. */
export interface Account {
  /** the account's id in Drive, which keys what is kept for it */
  id: string;
  /** the account's name */
  name: string;
  /** the account's photo, when it has one */
  photo?: string;
  /** the account's address, when Drive shares it */
  email?: string;
}

/** The account as earlier versions kept it, under its YouTube channel. */
interface OldAccount {
  channelId: string;
  title: string;
  thumbnail: string;
  googleId?: string;
  email?: string;
}

function accountOf(user: DriveUser): Account {
  if (user.permissionId) {
    return {
      id: user.permissionId,
      name: user.displayName,
      ...(user.photoLink ? { photo: user.photoLink } : {}),
      ...(user.emailAddress ? { email: user.emailAddress } : {}),
    };
  } else {
    throw new Error("Drive gave no id for the account");
  }
}

/**
 * Who is signed in on this browser. An account kept by an earlier version
 * is filed under its Google id here, with everything kept for it; one kept
 * without that id is signed out, and its entries move at its next sign-in.
 */
function readAccount(): Account | null {
  const kept = readJson<Account | OldAccount>(STORED_ACCOUNT);
  if (kept === null || "id" in kept) {
    return kept;
  } else if (kept.googleId) {
    moveAccountEntries(kept.channelId, kept.googleId);
    const account: Account = {
      id: kept.googleId,
      name: kept.title,
      ...(kept.thumbnail ? { photo: kept.thumbnail } : {}),
      ...(kept.email ? { email: kept.email } : {}),
    };
    writeJson(STORED_ACCOUNT, account);
    return account;
  } else {
    writeJson(STORED_ACCOUNT, null);
    return null;
  }
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
function moveOldSetupMark(accountId: string | null): void {
  if (readJson<boolean>(OLD_SETUP_DONE) === true && accountId) {
    writeText(SETUP_DONE_PREFIX + accountId, "1");
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
  account: Account | null = $state.raw(null);
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
    // before the kept account changes shape: that mark is filed under the id it has now
    const kept = readJson<Account | OldAccount>(STORED_ACCOUNT);
    moveOldSetupMark(
      kept === null ? null : "id" in kept ? kept.id : kept.channelId,
    );
    this.account = readAccount();
    this.returning = keysWith(SETUP_DONE_PREFIX).length > 0;
    if (this.account) {
      this.setupDone = setupDoneFor(this.account.id);
      this.store = this.openStore(this.account.id);
      this.expect(this.account);
    }
    if (typeof window !== "undefined") {
      window.addEventListener("storage", (event) => {
        if (event.key === STORED_ACCOUNT) {
          this.follow(readAccount());
        } else {
          this.store?.storageChanged(event.key, event.newValue);
        }
      });
    }
  }

  private openStore(accountId: string): SyncStore {
    const usable = (): boolean =>
      !this.switching && this.account?.id === accountId;
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

  /** Whether a token is `account`'s; its name, photo and address are brought up to date on the way. */
  private async owns(account: Account, token: string): Promise<boolean> {
    const user = await fetchDriveUser(token);
    const same = user.permissionId === account.id;
    if (same && this.account?.id === account.id) {
      const current = accountOf(user);
      if (JSON.stringify(current) !== JSON.stringify(this.account)) {
        this.keep(current);
      }
    }
    return same;
  }

  /**
   * Entries an earlier version filed under a YouTube channel id become the
   * account's when that channel is its own. Asked only while such entries
   * are left, and a sign-in goes on whatever the answer.
   */
  private async adoptOldEntries(token: string, accountId: string) {
    const oldIds = oldAccountIds();
    if (oldIds.length > 0) {
      const channelId = await fetchOwnChannelId(token).catch(() => null);
      if (channelId !== null && oldIds.includes(channelId)) {
        moveAccountEntries(channelId, accountId);
      }
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
    if (this.account?.id === accountId) {
      this.forgetLocal(accountId);
      this.store = this.openStore(accountId);
      this.setupDone = false;
    }
  }

  /** Another tab signed in, out or as someone else: be where it is. */
  private follow(next: Account | null): void {
    if (next?.id !== this.account?.id) {
      this.store?.close();
      forgetToken();
      this.ready = false;
      this.expired = false;
      this.account = next;
      if (next) {
        this.store = this.openStore(next.id);
        this.setupDone = setupDoneFor(next.id);
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
      const account = accountOf(await fetchDriveUser(token));
      await this.adoptOldEntries(token, account.id);
      if (account.id !== this.account?.id) {
        // its unsent edits stay in local storage for that account's next sign-in
        this.store?.close();
        this.store = this.openStore(account.id);
        this.setupDone = setupDoneFor(account.id);
      }
      this.keep(account);
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
      writeText(SETUP_DONE_PREFIX + this.account.id, "1");
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
    const accountId = this.account?.id;
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
