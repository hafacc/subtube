# web — the subtube web app

Svelte 5 single-page app built by SvelteKit 3 with `adapter-static`
(configured in `vite.config.ts`; there is no `svelte.config.js`), TypeScript,
plain CSS with brand tokens in `src/app.css`, bun, biome (double quotes,
2-space; `.svelte` files via biome's HTML support). Every page is prerendered:
`bun run build` → `dist/`, published to GitHub
Pages at https://subtube.hafa.cc by `.github/workflows/web-deploy.yml`, started
by hand, which publishes `main` (custom domain set in the repo's Pages
settings; no CNAME file).

- `bun install`, `bun run dev` (port 3000), `bun run build`, `bun test`,
  `bun run lint` (`svelte-kit sync`, `svelte-check`, `biome check`),
  `bun run fmt`.
- `src/app.html` is the page shell; `src/routes/+layout.svelte` loads
  `app.css`; `src/routes/+page.svelte` is the app's page: the built page
  holds the title and description only, and `src/App.svelte` mounts in the
  browser. SvelteKit's router has nothing to do: the app is one route and
  moves through its own `Router` (see `router.svelte.ts` below), so the dev
  console warns once that the page changes the URL itself.
- `bun scripts/icons.ts` regenerates `static/` from `../design/icons/`
  (needs rsvg-convert and ImageMagick); the output is committed. `logo.svg`
  is `sub-play.svg`, for beside the name (hull centred, tower above the
  line); `icon.svg` and the PNG icons are `sub-play-centred.svg`, all of the
  logo centred, for where it stands alone. In the collapsed sidebar, where
  the name is hidden, `logo.svg` is moved down to the same place.
- Dev sign-in: load `../extension/dist` unpacked, then put its id in
  `web/.env.local` as `VITE_EXTENSION_ID=…` and restart `bun run dev`. The
  extension's redirect URI must be on the web OAuth client.

## Privacy policy and terms (`src/routes/(policy)/`)

Two more routes, `privacy/+page.svelte` and `terms/+page.svelte`, built to
`dist/privacy.html` and `dist/terms.html` and served by Pages at
https://subtube.hafa.cc/privacy and `/terms`; the dev server serves them at
`/privacy` and `/terms` too. Links use `privacyUrl` and `termsUrl` in
`src/lib/config.ts`. Their shared `+layout.svelte` is the header and
`src/policy.css` (its header logo is sized in CSS by `Logo.svelte`'s rule),
over `src/app.css` for the brand tokens and theme; `+layout.ts` sets
`csr = false`, so they are built as plain HTML with no script but the theme
script and render in any browser. Setup's
footer, the channel sidebar's foot, Settings and the `GetApp` /
`ExtensionRequired` footers link to them as "Privacy policy" and "Terms",
side by side; setup's sign-in screen has the line "By signing in, you agree
to SubTube's Terms and Privacy Policy." under its button. Their wording is
approved text; don't reword it.

## YouTube attribution (`YouTubeAttribution.svelte`)

The text "Videos from YouTube", small and muted, a link to youtube.com; no
logo (YouTube's logo may not be drawn under 100px tall). `Feed` puts it after
the last card or the empty text of the feed and of a channel's page, not
during the first load's skeletons; `ChannelSidebar` puts it at its foot,
hidden in the rail.

## What decides the page (`src/App.svelte`, `src/lib/environment.ts`)

By user agent at load: phone/tablet (incl. iPadOS's desktop UA + touch) →
`GetApp` (iOS/iPad/Android); desktop Safari → `GetApp platform="mac"`; other
non-Chromium desktop browsers → `ExtensionRequired` (needs Chrome, links to
it); Chromium → `Shell`, told whether the extension answered a ping (it times
out after 500 ms). With the extension: first-run `Nux` until setup is done
for the account on this browser (`subtube.setupDone.<account>`, one mark per
account; signing out clears none), then `Feed`; signed out on a browser where
any account finished setup → Nux opens at its sign-in step, and an account
with no mark here goes on through setup. Without it there is no warning page: `Nux` runs,
from its start for a new browser or at its "Add the Chrome extension" step
when setup was done or an account is known. That step links to the Chrome Web
Store (`chromeWebStoreUrl`), pings every 1.5 s, and keeps Next disabled until
the extension answers. A page can only message an extension that was there
when it loaded, so on coming back to the tab with no answer the step reloads
the page and reopens there (`subtube.setupAtExtension` in sessionStorage).
After sign-in, before "Choose channels", `Nux` loads the Drive folder: any
`device-*.json` of ANOTHER device there (`SyncStore.profileFound`, `hasProfile`
in `sync-merge.ts`) marks setup done and opens the feed. This device's own
file never counts, so a reload part-way through setup, after "Choose
channels" saved the switches, goes on with setup.

## Content-Security-Policy (`csp` in `vite.config.ts`)

Each built page carries a `<meta http-equiv="content-security-policy">` first
in its head (Pages can't send headers): SvelteKit writes it where
`%sveltekit.head%` stands in `src/app.html`, adding the hash of its own
inline start script. One policy for every page, the policy pages too. It
lets in the site's own files, the inline
theme script by its hash, `https://www.youtube.com` for the IFrame API script
and the player's frame, pictures from `*.ytimg.com`, `*.ggpht.com` and
`*.googleusercontent.com`, and requests to `https://www.googleapis.com`
(YouTube and Drive); `'self'` covers the dev server's module scripts and its
reload socket, and `style-src` has `'unsafe-inline'` for the `style:`
attributes and the dev server's style tags. `src/lib/csp.test.ts` fails when
the theme script in `src/app.html` and its hash in `vite.config.ts` drift. A new host the app loads from (a picture
host, another API) must be added there.

## Loading

Stand-ins shimmer through the `.shimmer` class in `src/app.css`, which sweeps
a lighter band (1.4 s) across whatever is inside. Nothing is kept between
page opens (there is no feed cache), so the first load of a page always puts
`FeedCardSkeleton`s (`.skeleton-block` shapes, hidden from accessibility) in
the grid; setup's channel list loads as skeleton rows. A reload keeps the
previous cards, dimmed and inert, under a `.shimmer-band` overlay: a band
40% of the pane wide, black at 16% on a light page and white at 22% on a dark
one, as in the Apple apps, crossing in 1.4 s. The overlay lies over the
visible pane (`.pane` in `Feed`, around the scrolling `.content`), not inside
the grid: a band stretched over the grid's whole height never reaches the
window on a long feed. Both are still under `prefers-reduced-motion`. The
grid's `aria-busy` is what announces loading.

A full load (not a channel fetched by itself, nor a channel page's own fetch)
also draws `LoadBar`: a 3px Sunflower bar laid over the top edge of `.pane`,
taking no room, as wide as `FeedController.loadProgress` (null when no load
runs). That is `loadFraction` in `load-progress.ts`: 0.05 from the start of
the load until the subscription list and Drive are read, then channels
finished (fetched, failed or skipped, counted by `fetchChannels`'
`onFinished`) over enabled channels, never under 0.05 and never going back
(a load that starts over after renewing its token keeps its place). The
width eases over 0.2 s (steps under `prefers-reduced-motion`); when the load
ends, however it ends, the bar goes to the end, fades over 0.3 s and leaves
the page 0.5 s after the end. It is a `role="progressbar"` with 0–100
values, named by the page's `h1`.

## Layout

- `src/lib/` — logic, ported from the old root `src/` and tested with `bun test`
  against `../shared/fixtures` (patterns, filters, merge, prune, Shorts, feed
  order, channel order, channel chips, settings, feed chips, groups, phrases, watch progress, the card swipe's rules, and every `device-files/` example against the JSON Schema via ajv).
  `bunfig.toml` preloads `scripts/test-svelte-modules.ts`, which compiles
  `.svelte.ts` modules so tests can drive `FeedController` (`feed.test.ts`).
  - `types.ts` — `ChannelFilter` is exactly the Drive file's filter: **no
    channelId/title/thumbnail** (the schema forbids them). `Channel` = YouTube's
    identity + `filter`.
  - `sync-merge.ts` / `sync-store.ts` / `drive.ts` — per-device Drive files.
    `setFilter(channelId, filter)` strips identity keys and keeps unknown ones;
    every write goes through `sanitizeDeviceFile` + prune. Unsent edits live in
    localStorage and go up after the next load. **Tabs of one browser are
    one device**: before it writes to localStorage or uploads, a store takes
    in what another tab kept there (`absorbStored`, `mergeOwnCopies`: the
    entry saved last, of two saved at once the one seen in a load last), and
    `Session` passes the window's `storage` event to `storageChanged`. Saves
    run one tab at a time (`navigator.locks`), a save with no file id loads
    again first, and a load that finds several files under this device's
    name merges them into the first by id and deletes the rest, so two tabs
    never leave two files. A Drive request Google refuses (401) renews the
    token once and runs again (`renew`, the constructor's fourth argument).
    `close()` stops uploads before the token can become another account's. An edit keeps unknown fields
    beside `at` (`editedEntry`); unsent edits go up again after the next
    load and when the tab is hidden; a Drive file of this device that this
    version can't read is never overwritten. `deleteProfile()` (Settings →
    "Delete profile") deletes every file in the Drive folder, this device's
    last, then the local copy; `Session.deleteProfile` also drops the kept
    channel names and the account's setup-done mark, withdraws Google's
    grant (`revokeAccess`: the only place that does), signs out, and setup
    starts over. Another tab hears of it through the `storage` event and
    forgets the profile too. A store keeps in localStorage
    (`subtube.uploaded.<account>`) its uploaded file's id; a later listing
    without that file is looked at twice (`ownFiles`: the file asked for by
    its id, then the folder listed again, and never a listing asked for
    before one of this store's creates ended) before it means another device
    deleted the profile: the store wipes its copy, throws
    `ProfileDeletedError`, and the session goes back to setup, still signed in.
    A watched entry is written by `markedEntry` (a mark keeps the entry's
    `position`, an unmark drops it) or `playedEntry` (`position`, with
    `watched` true only when the player reported the end);
    `SyncStore.setProgress` keeps a position in localStorage at once and
    starts an upload only when told to. `setFilter` saves through
    `editedFilter`, which drops a pattern that is not phrases.
    `FeedController.applyLoad` hands each full load's item ids to
    `SyncStore.noteLoaded`, which sets `seen` on this device's entries for
    them (`refreshSeen`, at most once a day per entry, `at` untouched), then
    drops its entries neither saved nor loaded for 30 days
    (`pruneDeviceFile`), and uploads only when either changed something. A
    load that some channels failed in still counts; a channel fetched by
    itself does not.
  - `progress.ts` — what a watched entry means: `isWatchedEntry` (marked, or
    a position in the last 10 seconds of a video longer than that),
    `resumePosition`, `progressFraction` (the card's bar).
  - `phrases.ts` — `phrasesToPattern` / `patternToPhrases` (null = not
    phrases) / `phrasePatternOnly`. `compileFilter` applies a pattern only
    when it reads back as phrases.
  - `settings.ts` — the synced settings (`feedSort`, `channelSort`,
    `autoplay`, `timeChip`, `topicChips`, `groupChips`, and the channel list's own
    `channelTimeChip`, `channelTopicChips` and `channelGroupChips`) read out of the Drive files'
    `settings` map, which merges like the other maps; a missing or unknown
    value reads as the default and the entry is kept. `SyncStore.settings()` /
    `setSetting(name, value)` hold the raw entries; `FeedController.settings`
    is what the app reads, re-read after every load, and
    `FeedController.setSetting` changes one here and in Drive.
  - `text-order.ts` — the one case-insensitive compare (each code point
    lowercased alone, then code point order) behind the Title sort, channel
    names and chip labels.
  - `feed-order.ts` — `sortFeed`: the feed's four orders (Latest, Shortest,
    Title, Random, as the sort chip cycles); every one ends
    newest first, then by id. Random sorts by an FNV-1a hash of seed and id;
    the controller picks a new seed at each full load.
  - `chips.ts` — the chips row: the fifteen topics (`CATEGORY_NAMES`, by
    YouTube category id, kept on `Video.categoryId`; `topicLabel` is null for
    any other id, which gets no chip and matches nothing), the topic chips'
    order (`chipRow`), the filter editor's (`editorTopics`), what the time and
    topic chips keep (`chipFiltered`), and what a starting point marks
    (`startMarks`).
  - `setup-start.ts` — setup's starting point, applied channel by channel
    (`shared/fixtures/setup-start.json`): "Open my feed" keeps
    `{start, cutoff, channels}` in localStorage as
    `subtube.startFrom.<account>` (`pendingStart`: the choice, that moment
    and the channels then on; nothing for "All time"). Each time a
    channel's items are fetched in full, by a load or by itself,
    `applyStart` marks its items from before the cut-off less the span and
    takes it out of the record (`FeedController.markBeforeStart`); a channel
    that failed or was skipped stays until a later fetch, and the record is
    dropped once empty.
  - `storage.ts` — the one place that touches localStorage (`readText`,
    `writeText`, `readJson`, `writeJson`, `keysWith`); a read that fails
    finds nothing and a write that fails is dropped.
  - `errors.ts` — `ShownError`: an error whose message is the text shown
    (daily limit, missing permission, sign in again, the extension, no
    YouTube channel). `shownMessage(caught)` gives that message, and for
    anything else — a request that got no answer, a status Google answered
    with, an OAuth code — the one text "Couldn't reach Google. Check your
    connection and try again."; the detail goes to the console only. A
    sign-in the user calls off (`SignInCancelledError`) shows nothing.
  - `groups.ts` — groups of channels (`shared/fixtures/groups.json`): a
    group is a name in the `groups` of its channels' saved filters.
    `groupName` (typed text → name or null), `filterGroups`, `groupNames`
    (the groups that exist: named by a listed channel, in chip order),
    `groupKeptChannels` (what selected groups keep; null = everything) and
    `keptByBoth`, `chipTitle` (what a row's title shows), and the edits
    `setMembers` / `renameGroup` / `deleteGroup` / `saveGroup` (the editor's
    "Save"), which return a `GroupEdit`
    (changed filters by channel id + changed settings) and touch nothing.
    `FeedController.groups` is the chip list; `saveGroup` and
    `deleteGroup` apply an edit to `channels`, save its
    filters in one `SyncStore.setFilters` (over `savedFilters()`, which has
    the channels no longer listed too) and set the settings; a save counts
    only listed channels as members;
    `toggleGroupChip` / `toggleChannelGroupChip` select, and
    `clearChips("feed" | "channels")` empties a row's groups and topics.
    The feed's groups filter `beforeChips` before `chipFiltered` (not on a
    channel's page) and count for `emptiedBySelection`; the channel list's
    narrow `chipChannels`, so with only a group selected off channels stay.
  - `autoplay.ts` — `AUTOPLAY_OPTIONS` (the auto-play chip's two labels) and
    `nextUnwatched`: what plays after an item ends.
  - `watched-mode.ts` — the watched chip: `modeFiltered` (Unwatched /
    Watched / All, plus the items that changed sides on screen),
    `autoplayAdvances` (not in Watched), `emptiedBySelection` (which empty
    text a page shows).
  - `playback.ts` — `Playback`: one item in one YouTube player, with no DOM:
    starts a video at `resumeAt`, saves its position (every 5 s on the
    device; with an upload on pause, on leaving and, at once, when the tab is
    hidden), marks it at the player's reported end and calls `onended`.
    Nothing is saved for a live broadcast or a playlist; a playlist is marked
    when its last video ends. `cover(true)` pauses it and `cover(false)`
    plays again what that paused; `ontoggle` reports a pause or play that
    was not `cover`'s. Tested with a fake player (`playback.test.ts`).
  - `player.ts` / `player.svelte.ts` — the one player, with no DOM
    (`player.test.ts`): `PlayerController` (`play`, `minimize`, `expand`,
    `enlarge`, `close`, `ended`, `routeChanged`, `pageChanged`, `cardLost`,
    and `isPlaying` / `inCard` for the cards) over the
    rules `nextInQueue`, `endOutcome`, `afterRoute`, and the boxes
    `largeBox`, `minimizedBox`, `cardHolds`, `clipped`. See "Playing"
    below.
  - `channel-info.ts` — names/pictures of followed (non-subscribed) channels:
    `channels.list?id=` 50 per call, kept in localStorage, refreshed daily.
  - `feed.svelte.ts` — `FeedController`: load (subscriptions + Drive in
    parallel → every enabled channel's items, applied in one go when the load
    finishes; meanwhile `Feed` greys out the previous feed), filtering, the
    chips (counted over the current page's items after the filters and the
    watched chip — `watchedMode`, kept for the visit only, not synced — then
    applied; the unwatched counts ignore them; `emptiedBySelection` is why
    an empty page reads "No videos for the selected filter." rather than "Nothing
    new. You're caught up."), the
    order (every passing item, in the `feedSort` order; a video that becomes
    watched or unwatched here stays until the next full load, filter edit,
    change of the watched, time, topic or group chips, or move between the
    feed and a channel page — not when the sort changes, nor when one
    channel's fetch lands),
    `autoplayNext` (the next unwatched item of the page, null with
    "Auto-play" off or in Watched), watched marks and progress (`watched` and `bars`
    are read from the store's entries with each video's length;
    `recordProgress` saves the player's position, `resumeAt` is where a video
    opens), mid-load 401 silent retry, reload
    after `STALE_AFTER_MS` away. Filter edits only re-filter; a channel that
    is on is fetched by itself only when something its filter needs is
    missing (`isMissing`: its mode's items never fetched or failed in the
    last load, or the Shorts list — see below), at most 6 at a
    time, and after a running load ends. Refresh also refetches the open
    page of a channel that is off. Any request whose token Google refuses
    renews it once and retries (`withToken` in `auth.ts`; the store's own
    for Drive), asking the extension for a token it has not handed out
    before; a full load starts over instead. A channel's own fetch that
    fails leaves the page as it is and shows the partial-results notice,
    not the error banner; a failure signing in fixes goes to the session
    (`needsSignIn`), which shows the banner with "Sign in". The empty text
    is not shown beside an error. `Prefetch` fetches
    the items of the channels `fetchOnly` names, 6 at a time, before the feed
    opens; a later `fetchOnly` keeps what is fetched or being fetched for
    channels still named (adding only the Shorts list when a filter has come
    to need it), queues the new ones, and takes the others out of
    the queue (they have no items there). The load that gets it through
    `handOffPrefetched` builds on what it has for each enabled channel
    (`completeItems`) instead of fetching it again.
    **Shorts list only when needed**: `needsShorts(filter)` is uploads mode
    with Shorts on Hide or Only. Otherwise `fetchUploads` skips the `UUSH`
    request (`withoutShortsList`: a video that can't be a Short gets
    `isShort: false`, a candidate stays unjudged, so no "Short" tag).
    `ChannelItems.shorts` and the "shorts" mark in `fetchedModes` record
    whether the list was read; `completeItems` returns what is there when it
    `covers` the filter, asks for the Shorts list alone (`addShortsMarks`,
    one request, none without a candidate) when only that lacks, and fetches
    everything otherwise. Until the list arrives the Shorts gate hides the
    unjudged candidates. Only the Shorts gate in `filters.ts` and
    `FeedCard`'s tag read `isShort`. A channel whose Shorts list YouTube
    answers "not found" for has no Shorts; the extension's `/shorts/{id}`
    probe runs only when the list couldn't be read (`fetchShortIds` gives
    "failed": a 5xx again after one retry, or no answer). An uploads list
    answered "not found" is a channel with no uploads, not a failed channel.
    **Daily limit**: a 403 whose body has `error.errors[].reason`
    `quotaExceeded` or `dailyLimitExceeded` (`isDailyLimit`; not the
    per-minute `rateLimitExceeded`) is a `DailyLimitError`, whose message is
    the text shown ("SubTube has reached YouTube's daily limit. Try again
    after midnight Pacific time."). It is never retried and renews no token.
    In a load (`fetchChannels`) the channels not yet asked for are skipped
    and count as failed, what was fetched is shown, older items of the
    others stay, and the message replaces the partial-results notice; a
    `Prefetch` stops asking; the single-channel queue is emptied. Before the
    channels (subscriptions) it is the load's error, and setup's "Choose
    channels" shows it as its error.
  - `channel-order.ts` — the order of every channel list (the left sidebar;
    not setup's "Choose channels"), by the `channelSort` setting. "Latest"
    (`newest`): on with something fetched by newest fetched item, then on with
    nothing fetched; filters and watched marks don't count, so an edit or a
    mark never reorders the list. "Name"; "Unwatched" (`unwatched`), by
    `FeedController.unwatchedByChannel`, which does move as marks change. Off
    channels are last in every sort.
  - `channel-chips.ts` — the channel list's time and topic chips
    (`channelTimeChip`, `channelTopicChips`; apart from the feed's).
    `passingItems`: every fetched item, watched or not, of the kind its
    channel shows, that passes the filter of a channel that is on
    (`FeedController.listed`, which the unwatched counts are counted from
    too). `FeedController.channelTopicChips` is `chipRow` over those, so the
    open page, the watched chip and the list's time chip don't change which
    topics are offered. `chipKeptChannels` (`FeedController.chipChannels`):
    null with "All time" and no topic, else the ids of the channels with one
    item inside the span and in a selected topic (one item meets both), so
    off channels and channels with nothing passing drop out. The chips
    change neither the order nor the unwatched counts.
  - **The shown order is held** (`HeldChannelOrder`, `inHeldOrder`): the
    sidebar sorts only when its "moment" changes, and between changes every
    row keeps its place while its count and dimming update (a channel the
    held order doesn't know goes after the known ones, in sorted order).
    Which rows are shown is held the same way: `arrange` takes the ids the
    chips keep, and a channel shown at the last moment stays until the next
    even when the chips no longer keep it (switched off, say). The
    moment changes after each full load that is shown
    (`FeedController.loadCount`), when the channel sort or one of the list's
    chips changes, and when the
    user goes somewhere (`whereabouts` in `Feed`: the page's channel, the
    player over the app opening or closing, Settings opening or closing, the
    narrow drawer opening or closing). So switching a channel off, a mark, a
    filter edit or a channel's own fetch landing moves nothing until then.
    Auto-play moving on inside the open player and a card playing in place
    are not going somewhere.
  - `session.svelte.ts` — account, token state, the account's `SyncStore`.
  - `router.ts` / `router.svelte.ts` — `?channel=x&v=y|list=y`; the item
    is in the URL only while the player is large. Minimizing drops it by
    going back (`Router.close`), so Back from large minimizes, Back while
    minimized goes back a page with the player still there, and Forward
    onto the playing item makes it large again (`afterRoute`). Every entry
    the app makes carries in `history.state` how many of its entries lie
    before it (`depth`), which is how `close` knows it can go back, also
    after Back, Forward and a reload. A reload or
    a link with an item opens it large, also in a narrow window. Auto-play
    moves on with `replace`. A minimized player or one in a card is not in
    the URL, so a reload drops it. It works on the browser's History API
    directly, because the player needs each change at once, and writes its
    `depth` beside what SvelteKit keeps in the entry.
  - `platform/` + `auth.ts` — the extension bridge. Protocol types come from
    `../extension/src/protocol.ts` (type-only import; single source). A
    silent renewal names the account (`loginHint`, the address Drive gave at
    sign-in) and the token is checked to be that account's before it is
    used (`expectAccount`; `Session.owns` asks Drive's `about` for its
    `permissionId`), so with two Google accounts in the browser the app
    never works with the other one's token. `signOut` only forgets the
    token; `revokeAccess` also withdraws the grant.
  - `session.svelte.ts` also follows other tabs: the `storage` event for
    `subtube.account` signs this tab in, out or over to the other account.
  - `config.ts` — the extension's id and store links (TODO constants).
- `src/components/` — `Feed` is the signed-in app, laid out like the Mac app:
  `ChannelSidebar` on the left (the brand, which goes to the feed and
  refreshes; there is no Refresh button — clicking the row of the page
  already showing, Feed or a channel, refreshes it; "Feed" with its unwatched count,
  under the "Channels" heading a `ChipRow` of the list's own (hidden in the rail, where it keeps its height):
  the sort chip, the time chip, a divider, the "New group" chip, the group chips, a second divider, then the topic chips, no auto-play or watched chip; every
  channel the chips keep (`channel-chips.ts`) in `channel-order.ts` order with its unwatched count and off channels dimmed,
  or "No channels for the selected filter." in the feed's empty-text style when a loaded list's chips keep none; in the rail a row is
  a 40px box around its icon, so the selected one's highlight stays inside); the feed or a channel's page
  (`?channel=`) in the middle under a toolbar (theme, show/hide details,
  account → `Settings`) and the feed's `ChipRow` (`ChipRow` is the scrolling row, the divider, the round + chip "New group" (only when given `onnewgroup`: once the first load is shown, and not on a channel's page), the group chips in name order and the
  topic chips, with a second divider before the topic chips whenever the row has topics after a + chip or a group chip; its `leading` snippet is the chips before the first divider, and a parent fits it in with
  `--chip-row-padding` and `--chip-row-rule`, as the sidebar does; here: the auto-play chip, which cycles "Play one" (off) and
  "Auto-play" (on), the sort
  chip, the time chip, the watched chip, a divider, the "New group" chip, the group chips, a second divider, then the topic chips; it
  scrolls sideways with no scrollbar, fading out at an edge that hides
  chips). Every chip is `Chip` (a toggle, or a removable
  phrase, named "Remove {phrase}" to a screen reader) or `CycleChip` (shows
  the current choice, a press moves to the next; it is as wide as its widest
  label, and a screen reader hears what it sets first: "Playback: Play one",
  "Sort: Latest", "Time: All time", "Show: Unwatched"), both styled by `.chip` in
  `app.css`, the same box selected or not. `FeedCard` draws a 4px Sunflower
  bar along the bottom of the thumbnail, `bars`' fraction wide; watched cards
  are not dimmed. **The bar marks**: `.mark`, a plain button beside the
  thumbnail button in `.picture` (not Bits' `Toggle`: its name changes with
  the state, "Mark watched" / "Mark unwatched", also its `title`), calls
  `onmark`, which `Feed` gives as `FeedController.setWatched` with the
  opposite of what the item is, so the card stays where it is and the
  counts change at once. The bar (`.track` with `.progress` in it) fills or
  empties over 0.2 s. In a wide window `.mark` is the bottom 18px of the
  thumbnail; under the pointer or keyboard focus the track turns grey and
  grows to 7px over 0.15 s (the hover only for a pointer that can hover; a
  touch gets no grey track). At 760px and narrower `.mark` is 44px high,
  22px over the thumbnail (which no longer plays there) and 22px over the
  text. Nothing moves under `prefers-reduced-motion`. **A swipe marks too**,
  at 760px and narrower only: `.card` has `touch-action: pan-y pinch-zoom`
  and pointer handlers (touch, pen and mouse) that follow `swipe.ts` —
  `swipeIntent` (after 10px, a swipe when twice as far sideways as upright,
  else the press is dropped), `swipeOffset`, `swipePasses` (a quarter of the
  card's width, either way). `.face` (everything in the card) follows the
  pointer over `.behind`, a strip with the eye icon and "Mark watched", or
  the crossed eye and "Mark unwatched", at the edge being uncovered, its
  text darker once the swipe would count. On release `.face` slides back
  over 0.2 s and a swipe that passed calls `onmark`; the click that ends a
  mouse swipe is swallowed. Under `prefers-reduced-motion` the card stays
  still and the release still marks. The bar button stays the screen
  reader's and keyboard's way (the web has no accessibility actions).
  The card of what the player is playing, in any
  place, has no `.mark` (the player's next position save would undo the
  mark): large or minimized it keeps the bar, which is then not a button,
  and in the card it has none; it doesn't swipe either. `.mark` is described by its card's title
  (`aria-describedby`). Under the title one
  line holds the channel name (cut with an ellipsis) and the date at the
  right (never cut); `FeedCardSkeleton` is the same height as a card with a
  two-line title. `FilterEditor` on the
  right, hidden until its toolbar button is pressed, editing the open
  channel's filter with no preview (the page beside it is the preview):
  `PatternFields` is the phrase input (Enter or a comma makes the typed
  phrase a chip, pressing a chip removes it, Backspace in the empty field
  removes the last), and "Topics" lists all fifteen as toggles for the
  filter's `topics`, hidden for playlists.
  **Titles while chips are selected** (`chipTitle`): with an existing group
  or a topic selected in its row, the feed's `h1` and the sidebar's
  "Channels" `h2` (a 15px-high `.heading` row, so nothing moves) show the
  selected names joined with ", ", followed by a pencil "Edit group" (only
  with exactly one group selected) and an × "Clear" (`clearChips`). A
  channel's page keeps its name and gets only the ×, which empties
  `topicChips`. There is no clear chip in the rows.
  **`GroupEditor`** takes the filter editor's place in the right panel
  (`groupEdit` in `Feed`): the "New group" chip or a pencil opens the panel
  on it, each opening a fresh editor; it leaves when it closes itself or
  the page's channel changes (the panel then shows the filter editor), and
  the details button opens the filter editor again. It
  fills the panel's height as a column: the `.filter-group` card "Name"
  (no `maxlength`, which counts UTF-16 units, not code points: a name
  `groupName` refuses just disables "Save"); the card "Channels" with every listed channel by name with a `Switch`, in
  setup's `.channel-row` rows (now in `app.css`; only channels that are off
  are dimmed) — the rows are the only part that scrolls (there is no
  search field: the web app's channel list has none); then one row of
  `.button-compact` buttons (36px high, in `app.css`, for side panels):
  "Delete group" at the left for a group that exists (`.destructive`, with
  the trash icon; deletes at once and closes), "Cancel" (quiet) and "Save"
  (`.primary`) at the right (only the button saves, Enter in the
  name field does nothing). Everything is a local draft: nothing is
  written until "Save", which is disabled without a name and a switch on,
  calls `FeedController.saveGroup` (`saveGroup` in `groups.ts`: channels in
  and out and the rename as one `GroupEdit`, one save) and closes.
  "Cancel", opening another editor and leaving the page discard the draft.
  A name another group has merges into it. Selected chips change only by
  a rename or delete following through.
  `Switch` slides its knob with a transform and fades its track over
  0.15 s (not under `prefers-reduced-motion`); every switch in the app is
  that component (see "Controls"). A
  "Channels" button in the sidebar's header collapses the left sidebar to a
  rail of icons, and pins it open again from the widened rail; the rail only
  clips the full-width list, so no icon moves as it widens
  (remembered in localStorage as `subtube.sidebarCollapsed`); hover or
  keyboard focus widens the rail over the grid without reflowing it. In
  the rail, the room the hidden heading and chip row leave shows the
  channel list's selected groups and topics as round marks (`chipMarks` in
  `lib/groups.ts`: a group's first letter, a topic's icon from
  `TOPIC_ICONS`, two at most, the last one "+n" when there are more),
  starting right under "Feed"; they are not controls. Both
  sidebars animate over 200ms, not at all under `prefers-reduced-motion`.
  Under 1100px the right sidebar lies over the grid; under 760px the left one
  is a drawer opened from a toolbar button, sliding in over 200ms while its
  scrim fades; the toolbar stays one row.
  Playing: one player for the whole app. `PlayerController`
  (`player.svelte.ts`) holds what plays and where; `PlayerHost`, mounted once
  beside `.app`, draws it: one `position: fixed` box that is exactly the
  video's box, holding `PlayerFrame` (the YouTube embed, driving one
  `Playback`) keyed by item, so changing size or place never moves the
  iframe in the DOM and never reloads it. Three places:
  - **large** — over the dimmed app (`.dim`, a button that minimizes; `.app`
    is `inert` meanwhile), the widest 16:9 box that fits inside the margins
    with 37px kept above it for the bar (`largeBox`). It is a
    `role="dialog"` with `aria-modal` meanwhile. Escape (the box takes
    focus itself, since a cross-origin frame keeps its keys), a click on the
    dimmed area and Back minimize; none closes.
  - **minimized** — 356×200 at the window's bottom right, 16px from the
    edges (`minimizedBox`), with the app usable behind; `beside` moves it
    left by the details panel's 320px while that is open in a wide window.
    A window narrower than 388px gets the width it has, never under 200
    high. Meanwhile the page's scrolling `.content` gets `MINIMIZED_ROOM`
    (232px: the player and its margins) of padding after its last row, so
    the last cards scroll clear of it. Nothing else needs it: the channel
    list and the details panel are never under the player, and in a narrow
    window the drawer, the panel and Settings lie over it.
  - **card** — at 760px and narrower a card plays in place: `FeedCard`
    leaves its thumbnail box empty (`data-player-slot`) and the host lays
    the player over it, measuring it every frame and clipping to the
    scrolling pane (`data-player-view`). It never gets the frame below: it
    looks like its card with the video in it. When less than half of the box
    shows it minimizes (`cardLost`) and does not come back by itself. While
    something fills the screen (the embed's full-screen button), and for
    0.5 s after, the window's width and the card's box say nothing: the
    player stays in its card. A card whose
    thumbnail is under 200px high (two columns, 528–760px) can't hold a
    player, so it plays large.
  A card starts it large in a wide window and in the card in a narrow one,
  replacing whatever played. Leaving the page, the card leaving the list or
  the window widening minimizes a card's player (`pageChanged`); nothing but
  Close, and the end of a video with nothing next in a card, removes it. "Expand" makes
  a minimized player large in a wide window; in a narrow one it goes back to
  the page the video was started on (a new history entry), scrolls its card
  into view and plays there, or large when that page no longer lists it
  (in the one new entry, so Back returns to where Expand was pressed).
  **Frame** (large and minimized only, never in a card): at rest nothing of
  ours is drawn. While the user's last hover,
  click or tap was on the video, `.frame` is drawn around the box (inset
  -37px/-1px, so the video neither moves nor resizes): a 36px bar with the
  title and "Expand" (minimized) or "Minimize" (large), then "Close"; it
  fades in and out over 0.15 s (not under `prefers-reduced-motion`).
  It shows on `pointerover` of the video, on the window's `blur` with the
  embed focused (the first click inside a cross-origin frame), when the
  player reports a pause or play that is not ours (`Playback`'s
  `ontoggle`), and while the keyboard's focus (`:focus-visible`) is on the
  player or one of the bar's buttons: large or minimized the player is a
  tab stop, and the bar's buttons come next. It
  goes on a scroll, on `pointerover`/`pointerdown` anywhere else (not
  while the keyboard is inside), and when
  the player changes place. Hiding it leaves the embed its focus, so
  YouTube's keyboard shortcuts keep working; a later click inside no longer
  blurs the window, and is seen by the hover before it or the toggle it
  makes. Nothing is ever put over the embed.
  **Covered**: every 250 ms the host asks `elementFromPoint` at nine points
  of the shown part of the box; anything of the page there pauses the video
  (`Playback.cover`), and a video paused that way plays again once clear.
  In a wide window the player is above everything (z-index 30), in a narrow
  one under the channel drawer, the details panel and Settings (11).
  **Next**: `play` keeps the page's list and watched chip as they were
  (`PlayQueue`); at the end `nextInQueue` is the next unwatched item after
  the ended one in that list, whatever page shows now (null with
  "Auto-play" off, or a list started in Watched), played in the place the
  player is in (`endOutcome`; a card not on the page → minimized, else its
  card is scrolled into view). With nothing next the large and the
  minimized player stay, stopped on the ended video, until Close or Expand;
  a card's player closes. A player opened from a link has no
  list and uses the page's `autoplayNext`.
  Focus returns to the card of what was playing when the large player
  minimizes or closes. Its accessible name is the video's title, else
  "Player". The embed's own button is the way to full screen
  (`allowfullscreen` is set on the frame).
  `Settings`, `Nux` (setup uses the app's own controls, never its own
  variants: `ChoiceRow` is shared with `FilterEditor`, the cards are
  `.filter-group`; its screens are intro, extension, sign-in, "Choose
  channels", "Shorts", "Where to start", done. "Choose channels"' Next saves
  the switches and tells its `Prefetch` to fetch only the channels left on
  (nothing is fetched for a channel before that, so one turned off costs no
  quota; going Back and pressing Next again fetches only the newly-on
  ones), which runs under the later screens (the "Shorts" screen's Next calls it
  again, so a Hide or Only choice adds the Shorts lists) and is handed to
  the first feed load on "Open my feed"; the Shorts choice (the `shortsChoice` snippet) is saved on its
  own screen's Next; the starting point is kept per channel (`setup-start.ts`) and marks
  each channel's older items watched when that channel is first fetched; the list is in name order (`compareIgnoringCase`) and its search is `nameMatches`, case only;
  the sign-in screen's button is `GoogleButton`: Google's standard button, its four-colour mark on the neutral `--google-*` fill, stroke and text for a light and a dark page, never a Sunflower button),
  `ExtensionRequired`, `GetApp` (iOS/Android + Mac page). `Logo` takes the
  height of its hull, which is four fifths of the line height of the name
  beside it (17.6px by the 18px name on its 22px line, 28.8px by the 30px
  one on its 36px line), so the tower rises little above the line: the
  drawing is hull / 0.518 square with negative margins, so only the hull
  takes up room.

## Controls (Bits UI)

Behaviour (keyboard, focus, ARIA, state) comes from
[Bits UI](https://bits-ui.com) (`bits-ui`, pinned to an exact version); the
look is the app's own CSS. Each primitive is used through its `child`
snippet, so the element is written in our template, keeps the component's
scoped styles and is styled by the primitive's `data-state`. State is passed
with a function binding (`bind:checked={() => checked, (next) => …}`), so
the parent still owns it.

| Component | Primitive |
| --- | --- |
| `Switch` | `Switch.Root` + `Switch.Thumb` |
| `Segmented` (and `ChoiceRow` through it) | `RadioGroup`, horizontal: one tab stop, arrows move and choose |
| `Chip` with `pressed` | `Toggle` |
| the sidebar's "Channels" button | `Toggle` |
| `Settings` | `Popover` (`Popover.Root` and `.Trigger` in `Feed`, `Popover.ContentStatic` in `Settings`, not portalled, focus not trapped) |
| "Delete your profile?" | `AlertDialog`, not portalled: it stays inside the Settings popover so it stacks under the player as before; its `Content` is inside its `Overlay`, which is the centring backdrop |
| `LoadBar` | `Progress` |

Plain elements, because no primitive fits: `CycleChip`, a removable `Chip`
and the "New group" chip (buttons that act, with no state of their own);
`ChipRow`'s scroller and dividers; `PatternFields`' phrase input; text and
number inputs; `Avatar` (Bits' hides the picture until a second copy has
loaded); the details panel and the channel drawer (not modal, always in the
page, moved by CSS); `PlayerHost`; tooltips, which are `title` attributes.

- A new control uses a Bits primitive when one fits, with the app's CSS.
- Every state change animates (0.15 s for controls, 0.2 s for panels) and is
  still under `prefers-reduced-motion`. Popovers and dialogs fade through
  the `.fades` class in `app.css`, which Bits waits for before unmounting.
- Bits sets `contain: layout style` on popover and dialog content, which
  would trap a `position: fixed` child and shifts text by a pixel; both
  elements here set `contain: none`.
- Nothing of Bits may be portalled over the player, lock scrolling or trap
  focus outside a modal dialog: the minimized player stays usable beside an
  open Settings popover.

## Gotchas

- Biome reflows Svelte markup and adds whitespace between inline nodes.
- Svelte `.svelte.ts` modules don't support TS parameter properties.
- Settings shows the Google account's name and email, which Drive's `about`
  answers under the app-folder scope (no email scope is requested); the
  privacy policy says so.
- Sign out only forgets the account on this browser; Google's grant stays
  (other devices stay signed in, no consent screen next time), so an
  interactive sign-in always asks Google for the account chooser. Only
  "Delete profile" revokes.
