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

## Privacy policy and terms (`privacy.html`, `terms.html`)

Two more Vite entries, built to `dist/privacy.html` and `dist/terms.html`
and served by Pages at https://subtube.hafa.cc/privacy and `/terms`; the dev
server serves them at `/privacy` and `/terms` too. Links use the relative
`privacyUrl` and `termsUrl` in `src/lib/config.ts`. They are plain HTML with
`src/app.css` for the brand tokens and theme and `src/policy.css` for their
layout (its header logo is sized in CSS by `Logo.svelte`'s rule), and load none of the app, so they render in any browser. Setup's
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
  order, channel order, channel chips, settings, feed chips, phrases, watch progress, and every `device-files/` example against the JSON Schema via ajv).
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
    `autoplay`, `timeChip`, `topicChips`, and the channel list's own
    `channelTimeChip` and `channelTopicChips`) read out of the Drive files'
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
    topic chips keep (`chipFiltered`), and setup's starting point
    (`startMarks`; the choice waits in localStorage as
    `subtube.startFrom.<account>` for the first load after setup).
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
    when its last video ends. Tested with a fake player (`playback.test.ts`).
  - `channel-info.ts` — names/pictures of followed (non-subscribed) channels:
    `channels.list?id=` 50 per call, kept in localStorage, refreshed daily.
  - `feed.svelte.ts` — `FeedController`: load (subscriptions + Drive in
    parallel → every enabled channel's items, applied in one go when the load
    finishes; meanwhile `Feed` greys out the previous feed), filtering, the
    chips (counted over the current page's items after the filters and the
    watched chip — `watchedMode`, kept for the visit only, not synced — then
    applied; the unwatched counts ignore them; `emptiedBySelection` is why
    an empty page reads "No videos for selected filter" rather than "Nothing
    new. You're caught up."), the
    order (every passing item, in the `feedSort` order; a video that becomes
    watched or unwatched here stays until the next full load, filter edit or
    change of the watched, time or topic chips — not when moving between the
    feed and a channel page, nor when one channel's fetch lands),
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
    page of a channel that is off. Any fetch whose token Google refuses
    renews it once and retries (`withToken` in `auth.ts`). `Prefetch` fetches
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
    `FeedCard`'s tag read `isShort`.
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
    is the player open over the app, so Back closes it and a reload or deep
    link reopens it over the feed. Auto-play moves on with `replace`, so
    Back still closes. A card playing in place is not in the URL.
  - `platform/` + `auth.ts` — the extension bridge. Protocol types come from
    `../extension/src/protocol.ts` (type-only import; single source).
  - `config.ts` — public ids and store links (TODO constants).
- `src/components/` — `Feed` is the signed-in app, laid out like the Mac app:
  `ChannelSidebar` on the left (the brand, which goes to the feed and
  refreshes; there is no Refresh button — clicking the row of the page
  already showing, Feed or a channel, refreshes it; "Feed" with its unwatched count,
  under the "Channels" heading a `ChipRow` of the list's own (hidden in the rail, where it keeps its height):
  the sort chip, the time chip, a divider, then the topic chips, no auto-play or watched chip; every
  channel the chips keep (`channel-chips.ts`) in `channel-order.ts` order with its unwatched count and off channels dimmed,
  or "No channels for selected filter" in the feed's empty-text style when a loaded list's chips keep none; in the rail a row is
  a 40px box around its icon, so the selected one's highlight stays inside); the feed or a channel's page
  (`?channel=`) in the middle under a toolbar (theme, show/hide details,
  account → `Settings`) and the feed's `ChipRow` (`ChipRow` is the scrolling row, the divider, the round × chip "Clear topics" that empties the row's topic setting (there whenever a topic chip is, disabled and dimmed while none is selected) and the
  topic chips; its `leading` snippet is the chips before the divider, and a parent fits it in with
  `--chip-row-padding` and `--chip-row-rule`, as the sidebar does; here: the auto-play chip, which cycles "Play one" (off) and
  "Auto-play" (on), the sort
  chip, the time chip, the watched chip, a divider, then the topic chips; it
  scrolls sideways with no scrollbar, fading out at an edge that hides
  chips). Every chip is `Chip` (a toggle, or a removable
  phrase) or `CycleChip` (shows the current choice, a press moves to the
  next; it is as wide as its widest label), both styled by `.chip` in
  `app.css`, the same box selected or not. `FeedCard` draws a 4px Sunflower
  bar along the bottom of the thumbnail, `bars`' fraction wide; watched cards
  are not dimmed and there is no per-card watched button. Under the title one
  line holds the channel name (cut with an ellipsis) and the date at the
  right (never cut); `FeedCardSkeleton` is the same height as a card with a
  two-line title. `FilterEditor` on the
  right, hidden until its toolbar button is pressed, editing the open
  channel's filter with no preview (the page beside it is the preview):
  `PatternFields` is the phrase input (Enter or a comma makes the typed
  phrase a chip, pressing a chip removes it, Backspace in the empty field
  removes the last), and "Topics" lists all fifteen as toggles for the
  filter's `topics`, hidden for playlists. A
  "Channels" button in the sidebar's header collapses the left sidebar to a
  rail of icons, and pins it open again from the widened rail; the rail only
  clips the full-width list, so no icon moves as it widens
  (remembered in localStorage as `subtube.sidebarCollapsed`); hover or
  keyboard focus widens the rail over the grid without reflowing it. Both
  sidebars animate over 200ms, not at all under `prefers-reduced-motion`.
  Under 1100px the right sidebar lies over the grid; under 760px the left one
  is a drawer opened from a toolbar button; the toolbar stays one row.
  Playing: `PlayerFrame` is the YouTube embed in a 16:9 box, driving one
  `Playback`; both places a video plays use it. At 761px and wider a card
  opens `Player`, a modal `<dialog>` over the app holding nothing but the
  video (the browser dims and disables everything behind and keeps focus
  inside), as wide as a 16:9 video fits inside the margins, with the cards'
  8px corners. It closes on Escape, a click on the dimmed area, or Back;
  there is no close button. Its accessible name is the video's title, else
  "Player". The feed stays mounted under it, and focus returns to the card
  of whatever it last played. With "Auto-play" on, the end plays
  `autoplayNext` in the same dialog. Escape does nothing while focus is
  inside the embed (a cross-origin frame keeps its keys), so the dialog
  opens with focus on itself, not in the embed. At 760px and
  narrower a card plays in place: `Feed` hands `FeedCard` the frame as its
  `player` snippet, which takes the thumbnail's box, and focus goes into the
  embed. One card plays at a time (`inlineItem`); starting another, the end,
  or the card leaving the list (page, filter or chip change, a load that
  drops it) unmounts the frame, which saves the position. With "Auto-play"
  on, the end starts `autoplayNext` in its card and scrolls it into view.
  The embed's own button is the way to full screen (`allowfullscreen` is set
  on the frame). A `?v=` link opened in a narrow window still opens the
  dialog.
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
  own screen's Next; the starting point is kept for the first feed load, which marks
  everything fetched from before it watched in one save),
  `ExtensionRequired`, `GetApp` (iOS/Android + Mac page). `Logo` takes the
  height of its hull, which is the line height of the name beside it (22px
  by the 18px name, 36px by the 30px one): the drawing is hull / 0.518
  square with negative margins, so only the hull takes up room and the tower
  rises above the line.

## Gotchas

- Biome reflows Svelte markup and adds whitespace between inline nodes.
- Svelte `.svelte.ts` modules don't support TS parameter properties.
- Settings shows the Google account's name and email, which Drive's `about`
  answers under the app-folder scope (no email scope is requested); the
  privacy policy says so.
- User-facing wording not in the mockups is marked `COPY-DRAFT` in the source.
