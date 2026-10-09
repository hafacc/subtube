import {
  type ErrorResponse,
  type ExtensionRequest,
  isAllowedOrigin,
  type ProbeShortResponse,
  type SignOutResponse,
  silentFailureNeedsUser,
  type TokenRequest,
  type TokenResponse,
} from "./protocol";

/** The web OAuth client (public; no secret); its redirect URI is this extension's `https://<id>.chromiumapp.org/`. */
const OAUTH_CLIENT_ID =
  "932619996481-qtf3mtbe40o315ptk6rm7ieuvn61akkm.apps.googleusercontent.com";
const OAUTH_SCOPES = [
  "https://www.googleapis.com/auth/youtube.readonly",
  "https://www.googleapis.com/auth/drive.appdata",
];
/** A cached token is handed out only while it has at least this long left. */
const TOKEN_MIN_REMAINING_MS = 5 * 60 * 1000;
const TOKEN_STORAGE_KEY = "token";

const SHORTS_PROBE_BASE = "https://www.youtube.com/shorts/";
const SHORTS_PROBE_TIMEOUT_MS = 5000;
const VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;

/** A token as kept in `chrome.storage.session`. */
interface CachedToken {
  accessToken: string;
  /** Epoch milliseconds. */
  expiresAt: number;
}

async function readCachedToken(): Promise<CachedToken | undefined> {
  const stored = await chrome.storage.session.get(TOKEN_STORAGE_KEY);
  return stored[TOKEN_STORAGE_KEY] as CachedToken | undefined;
}

/** Why a sign-in ended without a token; `cancelled` when the user closed Google's page or refused. */
class SignInError extends Error {
  /** Carries what went wrong and whether the user called it off. */
  constructor(
    message: string,
    readonly cancelled = false,
  ) {
    super(message);
    this.name = "SignInError";
  }
}

// what Chrome says when the user closes the sign-in window
const CLOSED_BY_USER = /did not approve|cancel/i;

/**
 * Runs Google's implicit flow in a Chrome-owned window. Non-interactive runs
 * reject when Google would need to show anything, which is the caller's cue to
 * retry interactively; `loginHint` names the account such a run is for.
 */
async function mintToken(
  interactive: boolean,
  loginHint: string | undefined,
): Promise<CachedToken> {
  const state = crypto.randomUUID();
  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.search = new URLSearchParams({
    client_id: OAUTH_CLIENT_ID,
    response_type: "token",
    redirect_uri: chrome.identity.getRedirectURL(),
    scope: OAUTH_SCOPES.join(" "),
    state,
    // a sign-out leaves the grant, so only the chooser lets the user pick another account
    prompt: interactive ? "select_account" : "none",
    ...(!interactive && loginHint ? { login_hint: loginHint } : {}),
  }).toString();

  let responseUrl: string | undefined;
  try {
    responseUrl = await chrome.identity.launchWebAuthFlow({
      url: authUrl.toString(),
      interactive,
    });
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : String(caught);
    throw new SignInError(message, CLOSED_BY_USER.test(message));
  }
  if (responseUrl === undefined) {
    throw new SignInError("sign-in returned no response");
  }
  const params = new URLSearchParams(new URL(responseUrl).hash.slice(1));
  if (params.get("state") !== state) {
    throw new SignInError("sign-in state mismatch");
  }
  const oauthError = params.get("error");
  if (oauthError !== null) {
    throw new SignInError(oauthError, oauthError === "access_denied");
  }
  const accessToken = params.get("access_token");
  const expiresIn = Number(params.get("expires_in"));
  if (accessToken === null || !Number.isFinite(expiresIn)) {
    throw new SignInError("sign-in returned no token");
  }
  return { accessToken, expiresAt: Date.now() + expiresIn * 1000 };
}

// sign-ins under way, so two requests for the same one share its window and its token
const minting = new Map<string, Promise<CachedToken>>();

function mintOnce(
  interactive: boolean,
  loginHint: string | undefined,
): Promise<CachedToken> {
  const key = JSON.stringify([interactive, loginHint ?? null]);
  let running = minting.get(key);
  if (!running) {
    running = (async () => {
      const token = await mintToken(interactive, loginHint);
      await chrome.storage.session.set({ [TOKEN_STORAGE_KEY]: token });
      return token;
    })().finally(() => {
      minting.delete(key);
    });
    minting.set(key, running);
  }
  return running;
}

/**
 * A token for the page: the kept one while it has time left, unless the
 * request is interactive (the user may be choosing another account) or says
 * Google refused it; otherwise a new one.
 */
async function handleToken(request: TokenRequest): Promise<TokenResponse> {
  const interactive = request.interactive === true;
  const loginHint =
    typeof request.loginHint === "string" ? request.loginHint : undefined;
  try {
    const cached =
      interactive || request.fresh === true
        ? undefined
        : await readCachedToken();
    const token =
      cached !== undefined &&
      cached.expiresAt - Date.now() > TOKEN_MIN_REMAINING_MS
        ? cached
        : await mintOnce(interactive, loginHint);
    return {
      accessToken: token.accessToken,
      expiresIn: Math.floor((token.expiresAt - Date.now()) / 1000),
    };
  } catch (caught) {
    const error = caught instanceof Error ? caught.message : String(caught);
    return {
      error,
      ...(caught instanceof SignInError && caught.cancelled
        ? { cancelled: true }
        : {}),
      signInRequired: interactive || silentFailureNeedsUser(error),
    };
  }
}

/** Forget the kept token; with `revoke`, also withdraw the grant at Google. */
async function handleSignOut(revoke: boolean): Promise<SignOutResponse> {
  try {
    const cached = await readCachedToken();
    await chrome.storage.session.remove(TOKEN_STORAGE_KEY);
    if (revoke && cached !== undefined) {
      // no-cors: there is no host permission for this endpoint and the reply is unneeded
      await fetch("https://oauth2.googleapis.com/revoke", {
        method: "POST",
        mode: "no-cors",
        body: new URLSearchParams({ token: cached.accessToken }),
      });
    }
  } catch {
    // an unrevoked token still expires within the hour
  }
  return { ok: true };
}

/**
 * youtube.com/shorts/{id} serves 200 for a Short and redirects anything else to
 * /watch. With `redirect: "manual"` the redirect arrives as an `opaqueredirect`
 * response (status 0), which also means a consent-page redirect reads as "not a
 * Short"; the user's own cookies are sent so they normally skip that page.
 */
async function handleProbeShort(
  videoId: string,
): Promise<ProbeShortResponse | ErrorResponse> {
  if (!VIDEO_ID_PATTERN.test(videoId)) {
    return { error: "invalid video id" };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SHORTS_PROBE_TIMEOUT_MS);
  try {
    const response = await fetch(`${SHORTS_PROBE_BASE}${videoId}`, {
      redirect: "manual",
      credentials: "include",
      signal: controller.signal,
    });
    void response.body?.cancel();
    if (response.status === 200) {
      return { isShort: true };
    } else if (response.type === "opaqueredirect") {
      return { isShort: false };
    } else {
      return { isShort: null };
    }
  } catch {
    return { isShort: null };
  } finally {
    clearTimeout(timer);
  }
}

async function handleRequest(request: ExtensionRequest): Promise<unknown> {
  switch (request?.type) {
    case "ping":
      return { version: chrome.runtime.getManifest().version };
    case "token":
      return handleToken(request);
    case "signOut":
      return handleSignOut(false);
    case "revoke":
      return handleSignOut(true);
    case "probeShort":
      return handleProbeShort(String(request.videoId));
    default:
      return { error: "unknown request" };
  }
}

chrome.runtime.onMessageExternal.addListener(
  (request: ExtensionRequest, sender, sendResponse) => {
    const allowed =
      chrome.runtime.getManifest().externally_connectable?.matches ?? [];
    if (!isAllowedOrigin(sender.origin, allowed)) {
      sendResponse({ error: "origin not allowed" });
      return false;
    } else {
      void handleRequest(request).then(sendResponse, (caught) =>
        sendResponse({ error: String(caught) }),
      );
      // keeps the channel open for the async sendResponse
      return true;
    }
  },
);
