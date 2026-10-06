import { ExtensionMissingError, SignInRequiredError } from "./errors";
import { type Platform, platform, type Token } from "./platform";
import { TokenExpiredError } from "./youtube";

// Renew a little before expiry so in-flight calls never 401.
const REFRESH_MARGIN_MS = 5 * 60 * 1000;

/** The account a token renewed without UI must be for. */
export interface ExpectedAccount {
  /** the Google account's address, passed to Google as the hint; absent when it isn't known */
  loginHint?: string;
  /** whether a token is this account's */
  owns(token: string): Promise<boolean>;
}

let accessToken: string | null = null;
let expiresAt = 0;
let renewal: Promise<string> | null = null;
let expected: ExpectedAccount | null = null;

function apply(token: Token): string {
  accessToken = token.accessToken;
  expiresAt = Date.now() + token.expiresIn * 1000;
  return token.accessToken;
}

function tokenIsFresh(): boolean {
  return accessToken !== null && Date.now() < expiresAt - REFRESH_MARGIN_MS;
}

/** Whether a token with time left is at hand. */
export function hasToken(): boolean {
  return tokenIsFresh();
}

/** Forget the token without telling the extension, e.g. when another tab changed the account. */
export function forgetToken(): void {
  accessToken = null;
  expiresAt = 0;
}

/**
 * Say whose tokens silent renewals are for: one that turns out to be another
 * account's is not used. Null while nobody is signed in.
 */
export function expectAccount(account: ExpectedAccount | null): void {
  expected = account;
}

async function required(): Promise<Platform> {
  const current = await platform();
  if (current) {
    return current;
  } else {
    throw new ExtensionMissingError();
  }
}

async function renew(current: Platform, fresh: boolean): Promise<string> {
  const account = expected;
  const token = await current.silentToken({
    ...(account?.loginHint ? { loginHint: account.loginHint } : {}),
    ...(fresh ? { fresh } : {}),
  });
  if (token && (!account || (await account.owns(token.accessToken)))) {
    return apply(token);
  } else {
    throw new SignInRequiredError();
  }
}

/**
 * A new token without UI; rejects with {@link SignInRequiredError} when there
 * is none, or when Google answers for another account than the one signed in.
 * `refused` says Google refused the token at hand, so the extension must not
 * hand that one back.
 */
export function silentRefresh(refused = false): Promise<string> {
  renewal ??= required()
    .then((current) => renew(current, refused))
    .finally(() => {
      renewal = null;
    });
  return renewal;
}

/** A token with time left, renewed silently when needed. */
export async function getValidToken(): Promise<string> {
  if (tokenIsFresh() && accessToken) {
    return accessToken;
  } else {
    return silentRefresh();
  }
}

/** Interactive sign-in through the extension; Google's account chooser may give another account. */
export async function signIn(): Promise<string> {
  return apply(await (await required()).signIn());
}

/** Forget the token here and in the extension; Google's grant stays. */
export async function signOut(): Promise<void> {
  forgetToken();
  await (await required()).signOut();
}

/** Forget the token and withdraw the grant at Google, which signs every device out. */
export async function revokeAccess(): Promise<void> {
  const current = await required();
  forgetToken();
  await current.revoke();
}

/**
 * Run a Google request with a token; when Google refuses the token, renew it
 * silently and run the request once more.
 */
export async function withToken<Result>(
  request: (token: string) => Promise<Result>,
): Promise<Result> {
  try {
    return await request(await getValidToken());
  } catch (caught) {
    if (caught instanceof TokenExpiredError) {
      forgetToken();
      return request(await silentRefresh(true));
    } else {
      throw caught;
    }
  }
}
