# apple/ — subtube for macOS and iOS

One Xcode project, `SubTube.xcodeproj`, committed and opened directly (no
generator). One target and one shared scheme, both `SubTube`, build the Mac
app (macOS 15+, native, not Catalyst) and the iPhone and iPad app (iOS 18+),
bundle id `cc.hafa.subtube`, signing automatic with the team in
`Config/Signing.xcconfig`. The target depends on the local Swift package
`SubtubeCore`, whose tests run from the scheme (⌘U) or `swift test`.

The project uses folder-synced groups: every file under `App/Shared`,
`App/macOS`, `App/iOS` and `App/Resources` is in the target automatically.
Add files on disk; don't add groups or file references in Xcode.
`App/macOS` compiles only for macOS and `App/iOS` only for iOS: the target's
`EXCLUDED_SOURCE_FILE_NAMES[sdk=…]` leaves the other folder out, its files
and those one folder down (the patterns' `*` stops at a `/`, so a deeper
folder needs one more pattern). Settings that differ by platform are
`[sdk=macosx*]` / `[sdk=iphone*]` conditionals on the target.

`Config/` holds what must stay out of the synced folders (the macOS
entitlements, `Info-macOS.plist`, `Info-iOS.plist`, `Versions.xcconfig`,
`Signing.xcconfig`) and `make-icons.sh`. The two Info plists carry only the
keys one platform has (app category; launch screen and orientations) and are
merged into the generated Info.plist; as conditional `INFOPLIST_KEY_`
settings those keys would also land, empty, in the other platform's plist.
`Versions.xcconfig` is the project's base configuration and includes
`Signing.xcconfig`; neither `MARKETING_VERSION` nor `DEVELOPMENT_TEAM` is in
the pbxproj.

## Layout

- `SubtubeCore/` — everything below the UI, platform-neutral: models
  (`ChannelFilter` keeps the stored filter object so unknown fields survive;
  its `regex` reads as empty when the stored pattern isn't phrases, and a
  save then writes it as empty; `topics` are category ids; `Video.categoryId`
  is YouTube's, as written),
  `Pattern` (the shared pattern language: meta regex + engine rewrite),
  `Phrases` (`phrasesToPattern` / `patternToPhrases`, nil = not phrases /
  `phrasePatternOnly`),
  `Filters` (a pattern is applied only when it reads back as phrases; the
  `topics` gate), `JSONValue` + `SyncMerge` (device files, merge; `WatchedEntry.seen`
  lives in the entry's `extra`, and anything but a whole number in range
  reads as nil; `refreshSeen` sets it on this device's entries for a full
  load's items, at most once a day each, `at` untouched; `pruneDeviceFile`
  drops own entries whose later of `at` and `seen` is 30 days old or more),
  `Progress` (what a watched entry means: `WatchedEntry.position` lives in
  the entry's `extra`; `isWatched` — marked, or a position in the last 10
  seconds of a video longer than that — `resumePosition`,
  `progressFraction` for the card's bar; `markedEntry` keeps the position on
  a mark and drops it on an unmark, `playedEntry` writes a position with
  `watched` true only at the player's reported end),
  `SyncStore` (Drive app-folder sync, debounced uploads, local pending copy
  uploaded again after a load finds Drive behind it or when the app leaves
  the foreground; never writes over its own Drive file if that couldn't be
  read; `watchedEntries`, `setWatched`, and `setProgress`, which keeps a
  position on the device at once and starts an upload only when told to;
  `noteLoaded`, which `FeedModel` calls with every full load's item ids —
  refresh, then prune, and an upload only when either changed something; a
  load some channels failed in still counts, a channel fetched by itself
  does not;
  followed channels' names cached per account), `Drive`, `YouTube`
  (`GoogleAPIError.dailyLimit`: a 403 whose body has `error.errors[].reason`
  `quotaExceeded` or `dailyLimitExceeded`, `isDailyLimit`, read only on
  YouTube answers; never retried, renews no token, and its description is
  the text shown), `Shorts` (`withoutShortsList`: a video that can't be a
  Short is not one, a candidate stays unjudged), `ShortsProbe`,
  `Settings` (`SyncedSettings`: `feedSort`, `channelSort`,
  `autoplay`, `timeChip`, `topicChips`, and the channel list's own
  `channelTimeChip` and `channelTopicChips`, read out of the device files'
  `settings` map, which merges like the other maps; a missing or unknown
  value reads as the default and the entry is kept. `SyncStore.settings()` /
  `settingEntries()` / `setSetting(_:value:)`; a file without the section is
  written back without it), `TextOrder` (the one case-insensitive compare:
  each scalar lowercased alone, then scalar order; behind the Title sort,
  channel names and chip labels),
  `FeedOrder` (`sortFeed`: the feed's four orders — newest, shortest, title,
  random — each ending newest first, then by id; Random sorts by
  `shuffleKey`, an FNV-1a hash of a seed and the id),
  `ChannelOrder` (off channels last in every sort. Newest: on with something
  fetched by newest fetched item, then on with nothing fetched; filters and
  watched marks don't count, so an edit or a mark never reorders a list.
  Name. Unwatched: by the count given in `ChannelOrderEntry.unwatched`;
  `HeldChannelOrder`: the rows a list shows — `recompute` takes the order
  as it is now, less the channels its chips drop (`kept`), `hold` keeps
  every row in place whether or not it is still kept, drops channels that
  are gone and puts newly kept ones last),
  `LoadProgress` (`loadFraction`: a full load's bar, `loadProgressStart`
  while the subscription list is read, then one equal step per channel
  fetched, failed or skipped; `FeedLoadSink.progress` reports the counts),
  `Chips` (the fifteen topics, `categoryNames` by YouTube category id;
  `topicLabel` is nil for any other id, which gets no chip and matches
  nothing; the topic chips' order, `chipRow`; the filter editor's,
  `editorTopics`; what the time and topic chips keep, `chipFiltered`;
  the channel list's row (shared/fixtures/channel-chips.json): `listedItems`,
  every fetched item of an on channel, of the kind it shows, that passes its
  filter, watched or not — what that row's topic chips are counted over —
  and `chipKeptChannels`, the channels with one of those inside the span and
  in a selected topic, nil when neither is chosen;
  setup's starting point, `startMarks`, kept in UserDefaults by
  `keepPendingStart` / `takePendingStart` until the first load after setup),
  `WatchedMode` (the watched chip: `modeFiltered`, `autoplayAdvances`,
  `emptiedBySelection`), `Autoplay`
  (`nextUnwatched`: what plays after an item ends), `Playback` (one item in
  one player, no web view: from the player's reports it says what to save —
  a video's position every 5 s on the device, for Drive on pause and on
  `save(upload:)`, `watched` at the reported end; nothing for a playlist or
  a live broadcast, which are marked when they end), `FeedLoader`
  (`needsShorts`: uploads with Shorts on Hide or Only; `fetchChannelItems`
  asks for the `UUSH` list only then, and `ChannelItems.shorts` records
  whether it was read; `completeItems` returns what is there when it
  `covers` the filter, asks for the Shorts list alone — `addShortsMarks`,
  one request, none without a candidate — when only that lacks, and fetches
  everything otherwise; `fetchChannels` stops asking once the daily limit
  refuses a request and counts the rest as failed; `Prefetch`: the items of
  the channels `fetchOnly` names, 6 at a time, before the feed opens — a
  later `fetchOnly` keeps what is fetched or being fetched for channels
  still named, adds the Shorts list when a filter has come to need it,
  queues the new ones and takes the others out of the queue; the load given
  it builds on `items(_:)`),
  `Auth` (ASWebAuthenticationSession, PKCE, refresh token in the Keychain).
- `App/Shared/` — SwiftUI shared by both apps: `AppModel` (sign-in, first
  run, theme; after sign-in on a device that hasn't finished the first run
  it lists the Drive app folder and skips the rest of setup when any
  `device-*.json` is there; Delete Profile empties the app folder and local
  state, then signs out; a load that finds this device's uploaded file gone
  — `SyncError.profileDeleted` — wipes local state and restarts setup,
  unless a fresh listing shows another device set the account up again),
  `FeedModel` (the feed: `shown` is everything fetched that passes the
  filters, the watched chip — `watchedMode`, kept for the visit — and the
  time and topic chips, in the `feedSort` order; `topicChips` are counted
  after the filters and the watched chip, `unwatchedByChannel` ignores the
  chips; an item that becomes watched or unwatched on screen stays until a
  full load, a filter edit or a change of the watched, time or topic chip,
  not when moving between pages; `watched` and `bars` are worked out from a
  mirror of the store's entries, `entries`, and each video's length;
  everything asked of the store about entries and settings goes through one
  queue, `storeCalls`, so saves land in the order made; `recordProgress`
  saves the player's position, `resumeAt` is where a video opens;
  `autoplayNext`; `player` is the one `PlayerSession`, and replacing it
  saves the old one's position; during a load the previous feed stays,
  greyed out, and filters edited meanwhile win over the load's copy; an
  edit to a shown channel that lacks something its filter needs —
  `isMissing`: its mode's items, or the Shorts list — fetches just that,
  after the load if one runs, six fetches at a time; the daily limit shows
  its text in place of the partial-load notice, or as the error, and drops
  the fetches still waiting; refreshing on an off channel's page refetches
  it; the first load after setup marks what was fetched from before the
  starting point watched in one edit; `loadProgress` is the running full
  load's fraction, nil otherwise and for a channel fetched by itself;
  `orderedChannels` is the held rows, those the channel list's chips keep:
  `reorderChannels()` works them out again — a full load and a change of
  the channel sort, time or topic chips call it, a list calls it when it
  appears and when its search changes — and between those an edit, a count
  or a single channel's fetch moves no row and takes none away, and a
  channel that comes to be kept goes last; `channelTopicChips` is that
  row's topics; `explainsNoChannels` is true once a full load is shown
  and a span or topic is chosen: a list then empty, by the chips alone or
  with its search, shows "No channels for selected filter"), `Player` (`PlayerSession`: one video
  or one real playlist; it owns its WKWebView — IFrame API, element full screen
  and inline playback on; the page's base URL and the player's `origin` and
  `widget_referrer` are `PlayerPage.identity`, `https://<bundle id>` read
  from the bundle, as YouTube asks of a native app —
  so a view showing it can go and come back without restarting it; the page
  posts the player's state and, each second while playing, its position;
  `YouTubePlayerView` is the bare 16:9 player), `ChipViews` (`Chip`, a
  toggle or a removable phrase; `CycleChip`, as wide as its widest label
  and never drawn selected; `AutoplayChip`, a `CycleChip` reading "Play one"
  with auto-play off and "Auto-play" with it on; `ChipRow`, which fades out
  over 40 pt at an edge with chips beyond it and shows no scroll indicator:
  its leading chips, then, when it has topics, a divider, `ClearTopicsChip`
  — round, a × alone, dimmed and disabled while no topic is selected — and
  the topic toggles; `FeedChipRow` and `ChannelChipRow` (sort, time, topics)
  are the two rows; `NoChannelsForFilter`; `FlowLayout`), `FeedViews` (also `LoadProgressBar`: 3 pt
  of Sunflower over the top edge of the feed while `loadProgress` is set,
  running to the end and fading out when the load finishes; no animation
  under reduced motion; to accessibility a progress value), `FilterForm` (`PhraseFields`: the pattern as phrase chips
  over `PhraseInput`, an AppKit/UIKit field because SwiftUI's reports
  neither Return nor Delete-when-empty on a phone; "Case" is a segmented
  group, "Ignore" or "Match", for `caseSensitive`;
  Topics lists all fifteen as toggles for the filter's `topics`, hidden for
  playlists; its segmented groups are `SegmentedRow`: on macOS
  a label with the segments at natural width on the right, under the label
  when they don't fit),
  `NuxView` (the first run uses the app's own controls; its screens are
  intro, sign-in, "Choose channels", "Shorts", "Where to start", done.
  `SignInAgreement`, the line "By signing in, you agree to SubTube's Terms
  and Privacy Policy." with its two links, sits directly under every
  `GoogleSignInButton`: setup's and the Mac Settings window's when signed
  out.
  "Choose channels" loads channels only; its Next saves the switches and
  calls `FeedModel.prefetchEnabled()`, which fetches only the channels left
  on, so one turned off costs no quota; "Shorts"' Next saves the choice and
  calls it again, so a Hide or Only choice adds the Shorts lists; the first
  full load takes the prefetch when the feed opens; the starting point is
  kept on the device for that load; the decisions are in `Setup.swift`),
  `SettingsViews` (also `Links`, the three addresses the apps open;
  `LegalLinks`, "Privacy Policy" and "Terms" side by side in Settings;
  `YouTubeAttribution`, "Videos from YouTube" as a small muted link to
  youtube.com, text only: after the last card or the empty text of the feed
  and of a channel's page, not while `FeedModel.showsSkeletons`, and at the
  end of the channel list), `Brand` (also `LogoMark`, sized by its hull so only the
  hull takes layout room, and `Wordmark`, the logo beside the name with the
  hull as tall as the name's line; the one shimmer, `shimmering()`, and
  `skeleton()` for stand-ins: a first load shows skeleton cards, a reload
  sweeps the greyed feed with a dark band on light and a light band on dark;
  still under reduced motion), `Strings`.
- `App/macOS/` — `NavigationSplitView` (sidebar: Feed + channels, each with
  its unwatched count, the channel chip row under the "Channels" header,
  scrolling inside the sidebar's width, and
  the YouTube attribution pinned at the bottom, gone with the sidebar when
  it is collapsed;
  every channel list but setup's uses `FeedModel.orderedChannels`; the
  sidebar is always on screen, so it asks for a new order when Feed or a
  channel is selected, when the player opens or closes and when the
  Settings window appears or goes; detail:
  the chip row, Auto-play first, over the grid, the load bar over both; inspector: filters, opened
  only from the toolbar; no Refresh button: clicking the sidebar row already
  showing refreshes, as does Feed → Refresh, Cmd-R), the player is the
  video alone over the dimmed app, closed by a click beside it or Escape
  (the window's toolbar stays above it), `FeedCommands` (Feed menu),
  Settings scene (General, Account).
- `App/iOS/` — tab bar (Feed, Channels, Settings; tapping Feed while the feed shows
  scrolls to the top and refreshes, and pull to refresh stays); the Feed and
  Channels tabs have the standard large title, alone. The Channels list's
  first row is its chip row, then `ChannelSearchField`, which narrows what
  the chips keep. The chip row, Auto-play
  first, is the first row of the feed and of a channel's page; a channel's
  page has an inline title, the channel's name, with only the Filters button
  beside it; the load bar lies over the top edge of both lists, so under the
  Feed tab's large title until that collapses, then under the bar. A channel's page is
  pushed from a feed card or the Channels list (unwatched count left of each
  switch), and its Filters
  button, the filter symbol `line.3.horizontal.decrease.circle`, opens the
  filter sheet over it; a card plays in place of its
  thumbnail, one at a time, and stops when its card leaves the list or the
  page changes.

## Shared behaviour

`../shared/` is the spec. `SubtubeCoreTests/SharedFixtureTests.swift` loads
every fixture from it by path (`#filePath` → repo root) and must pass. Never
change shared behaviour here alone; change `shared/` first.

## Brand

`AccentColor` is Sunflower. Yellow fills always carry ink text
(`ProminentButtonStyle`); text, links and icons on light use `Color.gold`
(dark gold, Sunflower in dark mode). iOS sets `.tint(.gold)` at the root;
switches set `.tint(.sunflower)` themselves. The macOS sidebar selection is
Sunflower, so selected rows force ink text. Icons: `Config/make-icons.sh`
from `../design/icons/sub-play.svg`.

## Copy

All user-facing text is in `App/Shared/Strings.swift`. New wording waiting for
approval is marked `COPY-DRAFT`. The same thing is worded the same on every
platform (web, Android); only capitalization follows the platform.

## Run and look

- `xcodebuild -project SubTube.xcodeproj -scheme SubTube -destination 'platform=macOS' build CODE_SIGN_IDENTITY=-`
- `xcodebuild -project SubTube.xcodeproj -scheme SubTube -destination 'generic/platform=iOS Simulator' build CODE_SIGN_IDENTITY=-`
- `CODE_SIGN_IDENTITY=-` signs ad hoc, so a machine without the team's
  certificate can build; the macOS build fails without it, the simulator
  build doesn't need it.
- Debug builds take launch arguments to show screens without a Google
  sign-in: `-demo` (mockup data, no network), plus `-select:<channelId>`,
  `-play` (with `-video:<videoId>` the card plays that real video, which
  needs the network but no sign-in; use it to check the player after any
  change to `PlayerPage`), `-signedOut`, `-nux`, `-nuxStep:<0-5>`; iOS also
  `-tab:channels|settings`, `-channel:<channelId>` (with `-tab:channels`,
  opens that channel's page), `-filter:<channelId>` (the page, then its filter
  sheet), `-channelTime:<none|day|week|month>` and `-channelTopics:<id,id>` (the
  Channels list's time and topic chips; both platforms), `-bottom` (the filter sheet, the feed, the Channels list and Settings
  start scrolled to the end); macOS also `-sidebarCollapsed`; both platforms
  take `-loading` (the feed as
  during a reload, its bar stopped at three channels of eight; with `-empty`,
  as during the first load), `-unwatched` (the
  watched chip on Unwatched; the demo otherwise opens on All) and `-confirmDelete` (the Delete
  Profile confirmation, once Settings shows). Values ride in the same
  argument: macOS opens any bare argument as a file and then skips the main
  window.
- macOS screenshots without screen-recording permission:
  `open -W -n …/SubTube.app --args -demo -snapshot:<name>` writes PNGs to
  `~/Library/Containers/cc.hafa.subtube/Data/tmp/snapshots/<name>`, each
  window twice half a second apart (`later-…`) to show what moves. Sidebar
  and inspector (AppKit-backed lists and forms) and the web view don't render
  in them.
- iOS: `xcrun simctl io <device> screenshot`. Use an existing simulator; never
  create one.

## Release

macOS and iOS are cut separately; each has its own version line in
`Config/Versions.xcconfig`.

1. Run the `ios-cut` or `macos-cut` GitHub workflow with a patch, minor or
   major bump. It rewrites that platform's line, commits `ios v<version>` /
   `macos v<version>` to main and pushes the tag `ios-v<version>` /
   `macos-v<version>`.
2. Xcode Cloud has one workflow per platform, started by tags beginning
   `ios-v` / `macos-v`. Each has an Archive action with platform iOS or
   macOS and scheme `SubTube` (Release), and supplies the build number.
3. The archive goes to TestFlight; App Store submission is done from App
   Store Connect.

## Gotchas

- `GoogleClient.iOSClientID`: one Google iOS OAuth client (bundle id
  `cc.hafa.subtube`) serves both apps, in the same Cloud project as the
  other platforms' clients or the Drive app folder isn't shared.
- Drive filters carry no channel id/title/thumbnail; followed channels' names
  come from `channels.list?id=` (50 per call), cached in
  `channels-<account>.json` in Application Support.
- A pattern read from Drive that isn't phrases (or fails the meta regex) is
  treated as no pattern, and written as empty the next time its filter is
  saved; the editor only ever builds patterns from phrases.
- The YouTube embed refuses a page that sends no referrer (error 153), so
  the player page must keep a base URL. `https://cc.hafa.subtube` played a
  public video on the iPhone 17 simulator (iOS 27) on 2026-10-04.
- `ToolbarItemPlacement.largeTitle` (iOS 26) made the Channels tab's bar
  drop its large title and show nothing in its place, so no control sits
  beside a large title.
- A list row scrolled off screen is torn down, so the playing web view
  belongs to its `PlayerSession`, not to the row.
