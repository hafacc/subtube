# subtube Chrome extension

Lets the subtube web app sign in to Google and detect Shorts without a backend.
No UI of its own; the page talks to it with `chrome.runtime.sendMessage`
(see `src/protocol.ts`).

## Build

```sh
cd extension
bun install
bun export      # bundles to dist/
bun lint       # type-check and biome
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

The store version's ID is `gobcnmccpjhlgpnohehgkahhknkfbmfo`, the Chrome Web
Store listing's. An unpacked build, named "SubTube (dev)", has its own ID,
`dhiidepocengihahncjbhmcnlhmphbhh`, fixed by the public key
`manifest.dev.json` carries as `key` (no private key is kept; an unpacked
build needs none), so both can be installed at once. The web app's dev server
talks to the dev ID, its published build to the store's. `bun export` merges
`manifest.dev.json` over `manifest.json`, adding that key, the name and
`http://localhost/*` to the pages that may message it; `bun pack` uploads
`manifest.json` as it is.
