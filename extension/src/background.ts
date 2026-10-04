import {
  type ErrorResponse,
  type ExtensionRequest,
  isAllowedOrigin,
  type ProbeShortResponse,
  type SignOutResponse,
  type TokenResponse,
} from "./protocol";

/** The web OAuth client (public; same as `webClientId` in web/src/lib/config.ts). */
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

/**
 * Runs Google's implicit flow in a Chrome-owned window. Non-interactive runs
 * reject when Google would need to show anything, which is the caller's cue to
 * retry interactively.
 */
async function mintToken(interactive: boolean): Promise<CachedToken> {
  const state = crypto.randomUUID();
  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.search = new URLSearchParams({
    client_id: OAUTH_CLIENT_ID,
    response_type: "token",
    redirect_uri: chrome.identity.getRedirectURL(),
    scope: OAUTH_SCOPES.join(" "),
    state,
    ...(interactive ? {} : { prompt: "none" }),
  }).toString();

  const responseUrl = await chrome.identity.launchWebAuthFlow({
    url: authUrl.toString(),
    interactive,
  });
  if (responseUrl === undefined) {
    throw new Error("sign-in returned no response");
  }
  const params = new URLSearchParams(new URL(responseUrl).hash.slice(1));
  if (params.get("state") !== state) {
    throw new Error("sign-in state mismatch");
  }
  const oauthError = params.get("error");
  if (oauthError !== null) {
    throw new Error(oauthError);
  }
  const accessToken = params.get("access_token");
  const expiresIn = Number(params.get("expires_in"));
  if (accessToken === null || !Number.isFinite(expiresIn)) {
    throw new Error("sign-in returned no token");
  }
  return { accessToken, expiresAt: Date.now() + expiresIn * 1000 };
}

async function handleToken(interactive: boolean): Promise<TokenResponse> {
  try {
    const cached = await readCachedToken();
    const token =
      cached !== undefined &&
      cached.expiresAt - Date.now() > TOKEN_MIN_REMAINING_MS
        ? cached
        : await mintToken(interactive);
    if (token !== cached) {
      await chrome.storage.session.set({ [TOKEN_STORAGE_KEY]: token });
    }
    return {
      accessToken: token.accessToken,
      expiresIn: Math.floor((token.expiresAt - Date.now()) / 1000),
    };
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

async function handleSignOut(): Promise<SignOutResponse> {
  const cached = await readCachedToken();
  await chrome.storage.session.remove(TOKEN_STORAGE_KEY);
  if (cached !== undefined) {
    try {
      // no-cors: there is no host permission for this endpoint and the reply is unneeded
      await fetch("https://oauth2.googleapis.com/revoke", {
        method: "POST",
        mode: "no-cors",
        body: new URLSearchParams({ token: cached.accessToken }),
      });
    } catch {
      // an unrevoked token still expires within the hour
    }
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
      return handleToken(request.interactive === true);
    case "signOut":
      return handleSignOut();
    case "probeShort":
      return handleProbeShort(String(request.videoId));
    default:
      return { error: "unknown request" };
  }
}

chrome.runtime.onMessageExternal.addListener(
  (request: ExtensionRequest, sender, sendResponse) => {
    if (!isAllowedOrigin(sender.origin)) {
      sendResponse({ error: "origin not allowed" });
      return false;
    } else {
      void handleRequest(request).then(sendResponse);
      // keeps the channel open for the async sendResponse
      return true;
    }
  },
);
