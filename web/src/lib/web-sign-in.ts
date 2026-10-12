import { oauthClientId } from "./config";
import { deleteFile, listAppFiles } from "./drive";

/*
 * Sign-in for the delete page, which has to work in any browser and so can't
 * go through the extension: the page sends the browser to Google, and Google
 * sends it back with a short-lived token after the `#`. The page's own address
 * must be a redirect URI of the web OAuth client.
 */

const AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const REVOKE_ENDPOINT = "https://oauth2.googleapis.com/revoke";
const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.appdata";

/** Google's sign-in page for the Drive app folder, returning to `redirectUri` with `state`. */
export function signInUrl(redirectUri: string, state: string): string {
  const url = new URL(AUTH_ENDPOINT);
  url.search = new URLSearchParams({
    client_id: oauthClientId,
    redirect_uri: redirectUri,
    response_type: "token",
    scope: DRIVE_SCOPE,
    state,
    prompt: "select_account",
  }).toString();
  return url.toString();
}

/** The token Google returned in `hash`, or null unless it answers the sign-in that sent `state`. */
export function returnedToken(
  hash: string,
  state: string | null,
): string | null {
  const answer = new URLSearchParams(hash.replace(/^#/, ""));
  const token = answer.get("access_token");
  if (token && state !== null && answer.get("state") === state) {
    return token;
  } else {
    return null;
  }
}

/** Delete every file in the account's Drive app folder, then withdraw Google's grant. */
export async function deleteEverything(token: string): Promise<void> {
  for (const file of await listAppFiles(token)) {
    await deleteFile(file.id, token);
  }
  // no-cors: the reply is unneeded, and an unrevoked token still expires within the hour
  await fetch(REVOKE_ENDPOINT, {
    method: "POST",
    mode: "no-cors",
    body: new URLSearchParams({ token }),
  }).catch(() => undefined);
}
