# extension — the subtube Chrome extension

MV3 service worker with no UI. The web app talks to it with
`chrome.runtime.sendMessage(extensionId, request)`; `externally_connectable`
lets in `https://subtube.hafa.cc/*` and `http://localhost/*` (any port).

- `src/protocol.ts` — the message types (`ping`, `token`, `signOut`,
  `probeShort`) and `isAllowedOrigin`. Dependency-free: the web app imports its
  types from here, so it is the single source. Keep `EXTENSION_ORIGIN_MATCHES`
  equal to the manifest (a test checks).
- `src/background.ts` — `token`: Google's implicit flow through
  `chrome.identity.launchWebAuthFlow` (`prompt=none` when not interactive),
  cached in `chrome.storage.session`; `signOut`: forget + revoke; `probeShort`:
  `youtube.com/shorts/{id}` with `redirect: "manual"` (200 = Short, redirect =
  not, anything else = unknown). The OAuth client id must match
  `web/src/lib/config.ts`.
- `bun install`, `bun run build` (→ `dist/`, load unpacked), `bun run lint`
  (tsc + biome), `bun test`, `bun run package` (→ `subtube-extension.zip` for the Web Store,
  without the manifest `key`), `bun run icons` (regenerates `icons/` from
  `../design/icons/sub-play.svg`; needs rsvg-convert; output committed).
- Releases: run the `ext-cut` workflow by hand with a patch/minor/major bump.
  It bumps `manifest.json`'s version (the source of truth), tags
  `extension-v<version>` and starts `ext-release`, which attaches
  `subtube-extension.zip` to a GitHub release for uploading to the Web Store.

Gotchas: the manifest's `key` is the Web Store listing's public key, so an
unpacked build has the store id (see README); the id's `https://<id>.chromiumapp.org/` redirect must
be on the web OAuth client. `manifest.json` name/description are user-facing.
