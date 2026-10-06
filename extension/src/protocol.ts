/*
 * Messages between the subtube web app and its Chrome extension, sent with
 * `chrome.runtime.sendMessage(extensionId, request)`. Dependency-free so the
 * web app can import it without pulling in the extension's Chrome types.
 */

/**
 * The pages that may message the extension while it is developed: the
 * manifest's `externally_connectable.matches`, kept equal by a test. The
 * store build drops every `http:` one (`scripts/store-manifest.ts`).
 */
export const EXTENSION_ORIGIN_MATCHES = [
  "https://subtube.hafa.cc/*",
  "http://localhost/*",
] as const;

/**
 * Whether a page origin may message the extension: it fits one of `matches`,
 * the running manifest's `externally_connectable.matches`. A match pattern
 * ignores the port.
 */
export function isAllowedOrigin(
  origin: string | undefined,
  matches: readonly string[],
): boolean {
  if (origin === undefined || !URL.canParse(origin)) {
    return false;
  } else {
    const { protocol, hostname } = new URL(origin);
    return matches.includes(`${protocol}//${hostname}/*`);
  }
}

/** Asks whether the extension is installed. */
export interface PingRequest {
  type: "ping";
}

/** The installed extension's manifest version. */
export interface PingResponse {
  version: string;
}

/** Asks for a Google access token for YouTube and the Drive app folder. */
export interface TokenRequest {
  type: "token";
  /** Whether Google may show its account chooser or consent screen; such a request never gets a kept token. */
  interactive: boolean;
  /** The Google account's address a silent request is for, so Google doesn't answer for another one. */
  loginHint?: string;
  /** Set when Google refused the last token: the kept one is dropped first. */
  fresh?: boolean;
}

/** A Google access token. */
export interface TokenSuccess {
  accessToken: string;
  /** Seconds the token has left. */
  expiresIn: number;
}

/** Why no token came back, e.g. Google wanted to show UI to a non-interactive request. */
export interface ErrorResponse {
  /** what went wrong, for a log; not written for the user */
  error: string;
  /** Set when the user closed Google's page or refused: nothing went wrong. */
  cancelled?: boolean;
}

/** The result of a {@link TokenRequest}. */
export type TokenResponse = TokenSuccess | ErrorResponse;

/** Forgets the kept token; Google's grant stays, so other devices stay signed in. */
export interface SignOutRequest {
  type: "signOut";
}

/** Forgets the kept token and withdraws the grant at Google, as deleting the profile does. */
export interface RevokeRequest {
  type: "revoke";
}

/** The token is forgotten; a revocation that failed is swallowed, as the token still expires within the hour. */
export interface SignOutResponse {
  ok: true;
}

/** Asks whether a video is a Short. */
export interface ProbeShortRequest {
  type: "probeShort";
  videoId: string;
}

/** The probe's verdict. */
export interface ProbeShortResponse {
  /** `null` when YouTube's answer was inconclusive and shouldn't be cached. */
  isShort: boolean | null;
}

/** Any message the web app can send. */
export type ExtensionRequest =
  | PingRequest
  | TokenRequest
  | SignOutRequest
  | RevokeRequest
  | ProbeShortRequest;

/** The response type for each request type. */
export interface ExtensionResponses {
  ping: PingResponse;
  token: TokenResponse;
  signOut: SignOutResponse;
  revoke: SignOutResponse;
  probeShort: ProbeShortResponse | ErrorResponse;
}
