# web — the subtube web app

Svelte 5 single-page app (Vite, no SvelteKit), TypeScript, plain CSS with brand
tokens in `src/app.css`, bun, biome (double quotes, 2-space; `.svelte` files via
biome's HTML support). Static: `bun run build` → `dist/`, published to GitHub
Pages at https://subtube.hafa.cc by `.github/workflows/web-deploy.yml`, started
by hand, which publishes `main` (custom domain set in the repo's Pages
settings; no CNAME file).

- `bun install`, `bun run dev` (port 3000), `bun run build`, `bun test`,
  `bun run lint` (`svelte-check` + `biome check`), `bun run fmt`.
- `bun scripts/icons.ts` regenerates `public/` icons from
  `../design/icons/sub-play.svg` (needs rsvg-convert and ImageMagick); the output is committed.
- Dev sign-in: load `../extension/dist` unpacked, then put its id in
  `web/.env.local` as `VITE_EXTENSION_ID=…` and restart `bun run dev`. The
  extension's redirect URI must be on the web OAuth client.

## Privacy policy (`privacy.html`)

A second Vite entry, built to `dist/privacy.html` and served by Pages at
https://subtube.hafa.cc/privacy; the dev server serves it at `/privacy`
too. Links use the relative `privacyUrl` in `src/lib/config.ts`. It is
plain HTML with `src/app.css` for the brand tokens and theme and loads none
of the app, so it renders in any browser. Setup's sign-in screen, Settings
and the `GetApp` / `ExtensionRequired` footers link to it as "Privacy
policy". Its wording is approved text; don't reword it.

## What decides the page (`src/App.svelte`, `src/lib/environment.ts`)

By user agent at load: phone/tablet (incl. iPadOS's desktop UA + touch) →
`GetApp` (iOS/iPad/Android); desktop Safari → `GetApp platform="mac"`; other
non-Chromium desktop browsers → `ExtensionRequired` (needs Chrome, links to
it); Chromium → `Shell`, told whether the extension answered a ping (it times
out after 500 ms). With the extension: first-run `Nux` until setup is done on
this browser (`subtube.setupDone`), then `Feed`; signed out after setup → Nux
opens at its sign-in step. Without it there is no warning page: `Nux` runs,
from its start for a new browser or at its "Add the Chrome extension" step
when setup was done or an account is known. That step links to the Chrome Web
Store (`chromeWebStoreUrl`), pings every 1.5 s, and keeps Next disabled until
the extension answers. A page can only message an extension that was there
when it loaded, so on coming back to the tab with no answer the step reloads
the page and reopens there (`subtube.setupAtExtension` in sessionStorage).
After sign-in, before "Choose channels", `Nux` loads the Drive folder: any
`device-*.json` there (`hasProfile` in `sync-merge.ts`) marks setup done and
opens the feed.

## Loading

One shimmer for the whole app: the `.shimmer` class in `src/app.css` sweeps a
lighter band (1.4 s) across whatever is inside, and is still under
`prefers-reduced-motion`. Nothing is kept between page opens (there
is no feed cache), so the first load of a page always puts
`FeedCardSkeleton`s (`.skeleton-block` shapes, hidden from accessibility) in
the grid; a reload keeps the previous cards, dimmed and inert, under the same
shimmer (`.over-cards` makes its band darker on a light page, where a
lighter one wouldn't show over pale cards); setup's channel list loads as skeleton rows. The grid's `aria-busy`
is what announces loading.

## Layout

- `src/lib/` — logic, ported from the old root `src/` and tested with `bun test`
  against `../shared/fixtures` (patterns, filters, merge, prune, Shorts, feed
  order, channel order, and every `device-files/` example against the JSON Schema via ajv).
  `bunfig.toml` preloads `scripts/test-svelte-modules.ts`, which compiles
  `.svelte.ts` modules so tests can drive `FeedController` (`feed.test.ts`).
  - `types.ts` — `ChannelFilter` is exactly the Drive file's filter: **no
    channelId/title/thumbnail** (the schema forbids them). `Channel` = YouTube's
    identity + `filter`.
  - `sync-merge.ts` / `sync-store.ts` / `drive.ts` — per-device Drive files.
    `setFilter(channelId, filter)` strips identity keys and keeps unknown ones;
    every write goes through `sanitizeDeviceFile` + prune. Unsent edits live in
    localStorage and go up after the next load. `close()` stops uploads before
    the token can become another account's. An edit keeps unknown fields
    beside `at` (`editedEntry`); unsent edits go up again after the next
    load and when the tab is hidden; a Drive file of this device that this
    version can't read is never overwritten. `deleteProfile()` (Settings →
    "Delete profile") deletes every file in the Drive folder, then the local
    copy; `Session.deleteProfile` also drops the kept channel names and
    the setup-done mark, signs out, and setup starts over. A store marks in
    localStorage (`subtube.uploaded.<account>`) that its file was uploaded; a
    later successful listing without that file (`deletedElsewhere`) means
    another device deleted the profile: the store wipes its copy, throws
    `ProfileDeletedError`, and the session goes back to setup, still signed in.
  - `channel-info.ts` — names/pictures of followed (non-subscribed) channels:
    `channels.list?id=` 50 per call, kept in localStorage, refreshed daily.
  - `feed.svelte.ts` — `FeedController`: load (subscriptions + Drive in
    parallel → every enabled channel's items, applied in one go when the load
    finishes; meanwhile `Feed` greys out the previous feed), filtering, the
    order (every passing item, newest first; a card marked watched here
    stays, dimmed, until the next full load, watched toggle or filter edit —
    not when moving between the feed and a channel page, nor when one
    channel's fetch lands), watched marks, mid-load 401 silent retry, reload
    after `STALE_AFTER_MS` away. Filter edits only re-filter; a channel that
    is on is fetched by itself only when its items for the current mode are
    missing (never fetched, or failed in the last load), at most 6 at a
    time, and after a running load ends. Refresh also refetches the open
    page of a channel that is off. Any fetch whose token Google refuses
    renews it once and retries (`withToken` in `auth.ts`).
  - `channel-order.ts` — the order of every channel list (the left sidebar,
    setup's "Example channel" menu; not setup's "Choose channels"): on with
    something passing by newest passing item, then on with nothing passing,
    then off.
  - `example-channel.ts` — setup's example channel: on, uploads, no "only
    matches" pattern; most Shorts, then newest upload, then lower id.
  - `session.svelte.ts` — account, token state, the account's `SyncStore`.
  - `router.ts` / `router.svelte.ts` — `?channel=x&v=y|list=y`; Back
    closes the player.
  - `platform/` + `auth.ts` — the extension bridge. Protocol types come from
    `../extension/src/protocol.ts` (type-only import; single source).
  - `config.ts` — public ids and store links (TODO constants).
- `src/components/` — `Feed` is the signed-in app, laid out like the Mac app:
  `ChannelSidebar` on the left (the brand, which goes to the feed and
  refreshes; there is no Refresh button — clicking the row of the page
  already showing, Feed or a channel, refreshes it; "Feed" with its unwatched count,
  every channel in `channel-order.ts` order with off channels dimmed); the feed or a channel's page
  (`?channel=`) in the middle under a toolbar (show/hide watched,
  theme, show/hide details, account → `Settings`); `FilterEditor` on the
  right, hidden until its toolbar button is pressed, editing the open
  channel's filter with no preview (the page beside it is the preview), with
  "Mark all as watched" at the bottom (`mark-all.ts` decides, over the cards
  shown on the channel's page: mark the unwatched ones; once all shown are
  watched it reads "Mark all as unwatched" and unmarks exactly those; either
  goes up as one save). A
  "Channels" button in the sidebar's header collapses the left sidebar to a
  rail of icons, and pins it open again from the widened rail; the rail only
  clips the full-width list, so no icon moves as it widens
  (remembered in localStorage as `subtube.sidebarCollapsed`); hover or
  keyboard focus widens the rail over the grid without reflowing it. Both
  sidebars animate over 200ms, not at all under `prefers-reduced-motion`.
  Under 1100px the right sidebar lies over the grid; under 760px the left one
  is a drawer opened from a toolbar button. Also `Player` (a full-page overlay),
  `Settings`, `Nux` (setup uses the app's own controls, never its own
  variants: `ChoiceRow` and `PatternFields` are shared with `FilterEditor`,
  the cards are `.filter-group`, the preview is `FeedCard`s; its "Filter a channel" entry covers three
  screens: pick the example channel, Hide Shorts, Hide titles; it fetches
  every eligible channel's uploads to pick the example and hands them to the
  first feed load via `handOffPrefetched`, which skips those channels),
  `ExtensionRequired`, `GetApp` (iOS/Android + Mac page).

## Gotchas

- Biome reflows Svelte markup and adds whitespace between inline nodes.
- Svelte `.svelte.ts` modules don't support TS parameter properties.
- Settings shows the YouTube channel's name and @handle, not an email: the app
  has no email scope.
- User-facing wording not in the mockups is marked `COPY-DRAFT` in the source.
