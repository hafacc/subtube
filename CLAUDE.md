# subtube — project context

A personal, subscription-driven YouTube reader. Pulls recent uploads (or
playlists) from the channels you subscribe to (official Data API), applies
per-channel filters (title/description **pattern**, min duration, live/VOD,
Shorts), tracks **watched** state itself (YouTube exposes no watch history), and
plays videos through the official **IFrame embed** so ads still serve. No
algorithm, no recommendations, no comments.

## Layout

Independent clients that share behaviour, not code. Each directory has its own
`CLAUDE.md` with its build, layout and gotchas — read it before working there.

- `web/` — Svelte 5 single-page app (SvelteKit, bun), static on GitHub Pages at
  https://subtube.hafa.cc. Desktop Chrome needs the extension; desktop Safari
  links to the Mac app; phones and tablets link to the store apps.
- `extension/` — Chrome MV3 extension: silent Google sign-in and the Shorts probe
  for the web app (`externally_connectable`). Its `src/protocol.ts` is the only
  copy of the message types; `web/` imports it.
- `apple/` — one Xcode project (committed, folder-synced groups): macOS and iOS
  apps in SwiftUI over the `SubtubeCore` Swift package. No Safari extension yet.
- `android/` — Android Studio project: Kotlin + Compose, `:core` (JVM) + `:app`.
- `shared/` — the Drive device-file JSON Schema, the filter-pattern language
  (one meta regex), and JSON fixtures. **Every client's tests load
  `shared/fixtures` and must pass them.** A change to the Drive format or to
  filter, merge, prune, Shorts or feed-order semantics starts here, then goes to
  every client.
- `design/icons/` — the logo, a submarine on YouTube's shape: body, a
  tail that narrows and then flares, tower, two bubbles behind and the play
  triangle. `make.py` draws
  every `sub-` file (needs shapely); change the logo there. `sub-play.svg`
  is the logo as it stands beside the name: fin and body centered across
  and the body centered down, so it sits on the name's line with the tower
  and bubbles above. `sub-play-centred.svg` has all of it centered, for
  wherever the logo stands alone; every client's icons are made from it,
  and from `sub-play-centred-small.svg` (one large bubble) at 16 points and
  under. `sub-ports.svg` has three windows for the triangle;
  `sub-ports-loading.svg` is what a client shows while it loads (windows
  rolling tail to nose, puffs of bubbles rising), and
  `sub-play-to-loading.svg` plays the change there and back. `make.py`'s
  `motion()` and `bubbles()` are that animation, which each client draws
  itself. `shark`, `bubbles` and `bubbles-rising` are
  earlier alternatives.

Brand: Sunflower `#FFC20E` is the only brand color; yellow fills carry ink
`#1B1E24` text, a slightly blue charcoal that is also the logo's play
triangle and the app icon's tile; text and icons on light backgrounds use
dark gold `#8A6100`. Pages, surfaces and text are greys of that same
slightly blue cast (dark page `#121418`, light page white).

## Key decisions

- **No server.** Sign-in is per platform with a public OAuth client id (no
  secret) in the one Cloud project, subtube-dev: web via the extension, Apple via
  the iOS client with PKCE (refresh token in the Keychain), Android via Play
  services' AuthorizationClient.
- **Sync through the user's Drive app folder**: each device writes only
  `device-<id>.json`, reads everyone's, merges newest-`at`-per-key (ties → greater
  device id). Saved filters carry no channel identity; YouTube supplies it.
  The only channels are the user's YouTube subscriptions.
- **Shorts from YouTube's own lists** (`UUSH` beside `UU`), not a probe; a probe
  of `/shorts/{id}` is only the fallback where a platform can make one.
- **Filter patterns** are a small regex subset that JavaScript, ICU and Java read
  identically; the meta regex rejects anything else before it is saved. Users
  type phrases, which are built into a pattern; a saved pattern that is not
  phrases is not applied and is dropped at that filter's next save.
- **Watched is self-tracked**, and a device drops its own entry 30 days after
  it last saved it or last had the video in a full load (`seen`, set at most
  once a day; YouTube's API policies). Drive carries each
  video's playing position, and every client works out from it and the video's
  length whether it is watched (the last 10 seconds of a video longer than
  that); `watched: true` is for marks made without playing and for the
  player's reported end.
- **Topics are YouTube's fifteen video categories**, by category id.
- **Keep the official IFrame player** so ads serve and views count.

## Status

All four clients build and pass the shared fixtures. The web app and
extension work with real sign-in; the Apple and Android apps are not yet
verified with real tokens. Waiting on the user: store listings, the Apple team. The old Firebase project
(subtube-dev) is still deployed for the old site until this ships.

Future work: auto-generate a per-channel pattern from a few picked videos; a
paginated feed (older uploads beyond the first page per channel); build the
feed in place while it loads (a placeholder row for each video known to pass,
filled once its position is certain, rows growing upward with the scroll
adjusted so the view doesn't jump) instead of greying the feed out until the
load finishes; an advanced setting for writing a raw regex pattern; a menu on
the channel list (and setup's "Choose channels") that turns every channel
shown on or off.

## Gotchas

- The YouTube embed refuses pages that send no referrer (error 153): native web
  views load the player with their app id as the base URL
  (`https://cc.hafa.subtube`), which YouTube's rules require of native apps.
- `UUSH`/`UULF`/`UULV` and the `/shorts/` redirect are undocumented.
- A Drive app folder is only readable by OAuth clients of the project that wrote
  it, so every platform's client lives in subtube-dev.
