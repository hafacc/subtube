/*
 * Messages between the subtube web app and its Chrome extension, sent with
 * `chrome.runtime.sendMessage(extensionId, request)`. Dependency-free so the
 * web app can import it without pulling in the extension's Chrome types.
 */

/** The `externally_connectable.matches` patterns in the manifest; keep them in sync. */
export const EXTENSION_ORIGIN_MATCHES = [
  "https://subtube.hafa.cc/*",
  "http://localhost/*",
] as const;

/** Whether a page origin may message the extension, mirroring {@link EXTENSION_ORIGIN_MATCHES}. */
export function isAllowedOrigin(origin: string | undefined): boolean {
  if (origin === undefined) {
    return false;
  } else if (origin === "https://subtube.hafa.cc") {
    return true;
  } else {
    // match patterns ignore the port, so any localhost port is let in
    return /^http:\/\/localhost(:\d+)?$/.test(origin);
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
  /** Whether Google may show its account chooser or consent screen. */
  interactive: boolean;
}

/** A Google access token. */
export interface TokenSuccess {
  accessToken: string;
  /** Seconds the token has left. */
  expiresIn: number;
}

/** Why no token came back, e.g. Google wanted to show UI to a non-interactive request. */
export interface ErrorResponse {
  error: string;
}

/** The result of a {@link TokenRequest}. */
export type TokenResponse = TokenSuccess | ErrorResponse;

/** Revokes the cached token and forgets it. */
export interface SignOutRequest {
  type: "signOut";
}

/** Sign-out finished; revocation failures are swallowed since the cache is cleared regardless. */
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
  | ProbeShortRequest;

/** The response type for each request type. */
export interface ExtensionResponses {
  ping: PingResponse;
  token: TokenResponse;
  signOut: SignOutResponse;
  probeShort: ProbeShortResponse | ErrorResponse;
}
