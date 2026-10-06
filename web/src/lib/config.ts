/*
 * Public client config; safe to commit. A client id identifies the app to Google,
 * it grants nothing on its own, and none of these clients has a secret.
 *
 * All of subtube's OAuth clients live in one Google Cloud project (subtube-dev),
 * because a Drive app folder is readable only by clients of the project that
 * wrote it, and every platform has to see the same files.
 */

/**
 * The OAuth 2.0 web client, used through the Chrome extension. Authorized
 * redirect URI: the extension's https://<extension-id>.chromiumapp.org/.
 */
export const webClientId =
  "932619996481-qtf3mtbe40o315ptk6rm7ieuvn61akkm.apps.googleusercontent.com";

/**
 * The Chrome extension's id, fixed by the `key` in its manifest. `VITE_EXTENSION_ID`
 * (e.g. in web/.env.local) overrides it.
 */
export const extensionId: string =
  import.meta.env.VITE_EXTENSION_ID || "gobcnmccpjhlgpnohehgkahhknkfbmfo";

/** The privacy policy, a static page beside the app (`privacy.html`, served without the extension). */
export const privacyUrl = `${import.meta.env.BASE_URL}privacy`;

/** The terms of service, a static page beside the app (`terms.html`), like the privacy policy. */
export const termsUrl = `${import.meta.env.BASE_URL}terms`;

/** Where the "Videos from YouTube" attribution links. */
export const youtubeUrl = "https://www.youtube.com/";

/** The extension's Chrome Web Store page; the listing isn't published yet. */
export const chromeWebStoreUrl =
  "https://chromewebstore.google.com/detail/gobcnmccpjhlgpnohehgkahhknkfbmfo";

/**
 * The iPhone and iPad app on the App Store, or null before it is listed.
 * TODO: the App Store listing.
 */
export const appStoreUrl: string | null = null;

/**
 * The Mac app on the Mac App Store, or null before it is listed.
 * TODO: the Mac App Store listing.
 */
export const macAppStoreUrl: string | null = null;

/**
 * The Android app on Google Play, or null before it is listed.
 * TODO: the Google Play listing.
 */
export const playStoreUrl: string | null = null;
