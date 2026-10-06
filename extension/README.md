# subtube Chrome extension

Lets the subtube web app sign in to Google and detect Shorts without a backend.
No UI of its own; the page talks to it with `chrome.runtime.sendMessage`
(see `src/protocol.ts`).

## Build

```sh
cd extension
bun install
bun run build   # bundles to dist/
bun run lint    # type-check and biome
bun test
```

## Load unpacked

1. Open `chrome://extensions` and turn on **Developer mode**.
2. **Load unpacked** → pick `extension/dist`.
3. The card shows the extension **ID** (32 letters a–p).

## OAuth redirect

Sign-in redirects to `https://<id>.chromiumapp.org/`. Add that exact URL as an
**Authorized redirect URI** on the web OAuth client in the Google Cloud console.

## The ID

The extension's ID is `gobcnmccpjhlgpnohehgkahhknkfbmfo`, the Chrome Web Store
listing's. An unpacked build gets the same ID because `manifest.json` carries
the listing's public key as `key` (store dashboard → Package → View public
key, as one base64 line). `bun run package` leaves `key` out of the upload,
which the store requires, and `http://localhost/*` out of the pages that may
message it.
