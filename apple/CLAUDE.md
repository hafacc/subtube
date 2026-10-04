# apple/ — subtube for macOS and iOS

One Xcode project, `SubTube.xcodeproj`, committed and opened directly (no
generator). Targets `SubTube-macOS` (macOS 15+) and `SubTube-iOS` (iOS 18+),
bundle id `cc.hafa.subtube`, signing automatic with the team in
`Config/Signing.xcconfig`. Both depend on the local Swift package `SubtubeCore`, whose
tests run from either app scheme (⌘U) or `swift test`.

The project uses folder-synced groups: every file under `App/Shared`,
`App/macOS`, `App/iOS` and `App/Resources` is in the target(s) of its folder
automatically. Add files on disk; don't add groups or file references in
Xcode. `Config/` holds what must stay out of the synced folders (the macOS
entitlements, `Versions.xcconfig`, `Signing.xcconfig`) and `make-icons.sh`.
`Versions.xcconfig` is the project's base configuration and includes
`Signing.xcconfig`; neither `MARKETING_VERSION` nor `DEVELOPMENT_TEAM` is in
the pbxproj.

## Layout

- `SubtubeCore/` — everything below the UI, platform-neutral: models
  (`ChannelFilter` keeps the stored filter object so unknown fields survive),
  `Pattern` (the shared pattern language: meta regex + engine rewrite),
  `Filters`, `JSONValue` + `SyncMerge` (device files, merge, prune),
  `SyncStore` (Drive app-folder sync, debounced uploads, local pending copy
  uploaded again after a load finds Drive behind it or when the app leaves
  the foreground; never writes over its own Drive file if that couldn't be
  read;
  followed channels' names cached per account), `Drive`, `YouTube`, `Shorts`,
  `ShortsProbe`, `FeedOrder`, `ChannelOrder`, `PlayerTracker`, `FeedLoader`,
  `Auth` (ASWebAuthenticationSession, PKCE, refresh token in the Keychain).
- `App/Shared/` — SwiftUI shared by both apps: `AppModel` (sign-in, first
  run, theme; after sign-in on a device that hasn't finished the first run
  it lists the Drive app folder and skips the rest of setup when any
  `device-*.json` is there; Delete Profile empties the app folder and local
  state, then signs out; a load that finds this device's uploaded file gone
  — `SyncError.profileDeleted` — wipes local state and restarts setup,
  unless a fresh listing shows another device set the account up again),
  `FeedModel` (the feed: everything fetched that passes the filters, newest
  first; with watched hidden a card marked watched stays, dimmed, until a
  full load, a filter edit or the Hide Watched toggle, not when moving
  between pages; during a load the previous feed stays, greyed out, and
  filters edited meanwhile win over the load's copy; an edit to a shown
  channel whose items of that kind are missing fetches that channel, after
  the load if one runs, six fetches at a time; refreshing on an off
  channel's page refetches it), `Player` (one video or one real playlist; IFrame API in a WKWebView, base URL
  `https://subtube.hafa.cc`, element full screen on), `FilterForm` (ends with Mark All as Watched, one batch
  through `SyncStore.setWatched`, or Mark All as Unwatched when all are watched; its segmented groups are `SegmentedRow`: on macOS
  a label with the segments at natural width on the right, under the label
  when they don't fit),
  `NuxView` (the first run uses the app's own controls; "Choose channels"
  loads channels only and saves its switches and Shorts choice on Next,
  which then fetches the channels left on; the filter screens edit a draft
  saved once when the last is left; the decisions are in `Setup.swift`),
  `SettingsViews`, `Brand` (also the one shimmer, `shimmering()`, and
  `skeleton()` for stand-ins: a first load shows skeleton cards, a reload
  sweeps the greyed feed; still under reduced motion), `Strings`.
- `App/macOS/` — `NavigationSplitView` (sidebar: Feed + channels; every channel list but setup's uses
  `FeedModel.orderedChannels`; detail: grid; inspector: filters, opened
  only from the toolbar; no Refresh button: clicking the sidebar row already
  showing refreshes, as does Feed → Refresh, Cmd-R), the player takes over the
  window, `FeedCommands` (Feed menu), Settings scene (General, Account).
- `App/iOS/` — tab bar (Feed, Channels, Settings; tapping Feed while the feed shows
  scrolls to the top and refreshes, and pull to refresh stays); a channel's page is pushed
  from a feed card or the Channels list, and its Filters button opens the
  filter sheet over it; full-screen player.

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

- `xcodebuild -project SubTube.xcodeproj -scheme SubTube-macOS build CODE_SIGN_IDENTITY=-`
- `xcodebuild -project SubTube.xcodeproj -scheme SubTube-iOS -destination 'generic/platform=iOS Simulator' build CODE_SIGN_IDENTITY=-`
- `CODE_SIGN_IDENTITY=-` signs ad hoc, so a machine without the team's
  certificate can build; the macOS build fails without it, the simulator
  build doesn't need it.
- Debug builds take launch arguments to show screens without a Google
  sign-in: `-demo` (mockup data, no network), plus `-select:<channelId>`,
  `-play`, `-signedOut`, `-nux`, `-nuxStep:<0-6>` (3-5 are the
  three filter screens: example channel, Shorts, titles); iOS also
  `-tab:channels|settings`, `-channel:<channelId>` (with `-tab:channels`,
  opens that channel's page), `-filter:<channelId>` (the page, then its filter
  sheet), `-bottom` (the filter sheet and Settings start scrolled to the
  end); both platforms take `-loading` (the feed as
  during a reload; with `-empty`, as during the first load), `-hideWatched` and `-confirmDelete` (the Delete
  Profile confirmation, once Settings shows). Values ride in the same
  argument: macOS opens any bare argument as a file and then skips the main
  window.
- macOS screenshots without screen-recording permission:
  `open -W -n …/SubTube.app --args -demo -snapshot:<name>` writes PNGs to
  `~/Library/Containers/cc.hafa.subtube/Data/tmp/snapshots/<name>`. Sidebar
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
   `ios-v` / `macos-v`. It archives that platform's scheme (Release) and
   supplies the build number.
3. The archive goes to TestFlight; App Store submission is done from App
   Store Connect.

## Gotchas

- `GoogleClient.iOSClientID`: one Google iOS OAuth client (bundle id
  `cc.hafa.subtube`) serves both apps, in the same Cloud project as the
  other platforms' clients or the Drive app folder isn't shared.
- Drive filters carry no channel id/title/thumbnail; followed channels' names
  come from `channels.list?id=` (50 per call), cached in
  `channels-<account>.json` in Application Support.
- A pattern the meta regex rejects is never saved (`PatternField`); one read
  from Drive that fails it is treated as no pattern.
