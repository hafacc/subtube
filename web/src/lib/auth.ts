import { type Platform, platform, type Token } from "./platform";

// Renew a little before expiry so in-flight calls never 401.
const REFRESH_MARGIN_MS = 5 * 60 * 1000;

let accessToken: string | null = null;
let expiresAt = 0;
let renewal: Promise<string> | null = null;

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

/** Thrown when only an interactive sign-in can produce a token. */
export class SignInRequiredError extends Error {
  constructor() {
    super("Sign in again to continue.");
    this.name = "SignInRequiredError";
  }
}

/** Thrown when the extension the web app needs isn't installed. */
export class ExtensionMissingError extends Error {
  constructor() {
    super("The SubTube extension isn't installed.");
    this.name = "ExtensionMissingError";
  }
}

async function required(): Promise<Platform> {
  const current = await platform();
  if (current) {
    return current;
  } else {
    throw new ExtensionMissingError();
  }
}

async function renew(current: Platform): Promise<string> {
  const token = await current.silentToken();
  if (token) {
    return apply(token);
  } else {
    throw new SignInRequiredError();
  }
}

/** A fresh token without UI; rejects with {@link SignInRequiredError} when there is none. */
export function silentRefresh(): Promise<string> {
  renewal ??= required()
    .then(renew)
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

/** Interactive sign-in through the extension. */
export async function signIn(): Promise<string> {
  return apply(await (await required()).signIn());
}

/** Forget the token and have the extension revoke it. */
export async function signOut(): Promise<void> {
  accessToken = null;
  expiresAt = 0;
  await (await required()).signOut();
}
