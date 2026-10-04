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

- `web/` — Svelte 5 single-page app (Vite, bun), static on GitHub Pages at
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
- `design/icons/` — `sub-play.svg` is the logo; every client's icons are made
  from it. `sub-ports`, `shark` and `bubbles` are the shortlisted alternatives,
  and `sub-ports-loading`, `sub-play-to-loading` and `bubbles-rising` are
  animated versions.

Brand: Sunflower `#FFC20E` is the only brand colour; yellow fills carry ink
`#2A1F00` text; text and icons on light backgrounds use dark gold `#8A6100`.

## Key decisions

- **No server.** Sign-in is per platform with a public OAuth client id (no
  secret) in the one Cloud project, subtube-dev: web via the extension, Apple via
  the iOS client with PKCE (refresh token in the Keychain), Android via Play
  services' AuthorizationClient.
- **Sync through the user's Drive app folder**: each device writes only
  `device-<id>.json`, reads everyone's, merges newest-`at`-per-key (ties → greater
  device id). Saved filters carry no channel identity; YouTube supplies it, and
  channels followed in subtube are looked up with `channels.list?id=`.
- **Shorts from YouTube's own lists** (`UUSH` beside `UU`), not a probe; a probe
  of `/shorts/{id}` is only the fallback where a platform can make one.
- **Filter patterns** are a small regex subset that JavaScript, ICU and Java read
  identically; the meta regex rejects anything else before it is saved.
- **Watched is self-tracked**, pruned to a year per device.
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
load finishes.

## Gotchas

- The YouTube embed refuses pages that send no referrer (error 153): native web
  views load the player with base URL `https://subtube.hafa.cc`.
- `UUSH`/`UULF`/`UULV` and the `/shorts/` redirect are undocumented.
- A Drive app folder is only readable by OAuth clients of the project that wrote
  it, so every platform's client lives in subtube-dev.
