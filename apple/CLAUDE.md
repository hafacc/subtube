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

`App/Resources/PrivacyInfo.xcprivacy` is the privacy manifest for both apps:
no tracking, no collected data, and the two required-reason APIs the code
uses — `UserDefaults` (CA92.1) and the system uptime the player's save timer
reads (35F9.1). A new use of such an API needs its line there.

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
  read; uploads run one after another, each chained to the one before and
  clearing `saving` itself — never wait for one in a `while let running =
  saving` loop that someone else must clear, which spins the actor for good
  (`SyncStoreTests`); every Drive call goes through `withDrive`, which
  renews a refused token once; a listing without this device's file wipes
  the profile only after `ownFileIsGone` confirms it — asked for by id, or
  listed again — and never when an upload ran while the listing was asked
  for; `watchedEntries`, `setWatched`, and `setProgress`, which keeps a
  position on the device at once and starts an upload only when told to;
  `noteLoaded`, which `FeedModel` calls with every full load's item ids —
  refresh, then prune, and an upload only when either changed something; a
  load some channels failed in still counts, a channel fetched by itself
  does not;
  followed channels' names cached per account), `Drive`, `YouTube`
  (`GoogleAPIError.dailyLimit`: a 403 whose body has `error.errors[].reason`
  `quotaExceeded` or `dailyLimitExceeded`, `isDailyLimit`, read only on
  YouTube answers; never retried, renews no token; the errors carry no text
  of their own, `Strings.message(for:signedOut:)` words them; an uploads list
  that is "not found" is an empty one; `shortIds` is empty for a Shorts list
  that is "not found" and nil when the list couldn't be read — a 5xx twice,
  or a failed request), `Shorts` (`withoutShortsList`: a video that can't be
  a Short is not one, a candidate stays unjudged; `classifyShorts` probes
  only when the list couldn't be read), `ShortsProbe`,
  `Settings` (`SyncedSettings`: `feedSort`, `channelSort`,
  `autoplay`, `timeChip`, `topicChips`, `groupChips`, and the channel list's own
  `channelTimeChip`, `channelTopicChips` and `channelGroupChips`, read out of the device files'
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
  setup's starting point, `startMarks`, kept per account in UserDefaults as
  a `PendingStart` (shared/fixtures/setup-start.json) — the choice, when setup finished and the channels that
  were on — by `keepPendingStart` / `pendingStart`; `applyPendingStart`
  marks a waiting channel's older items the first time a load fetches it and
  takes it off the list, so a channel that failed keeps waiting),
  `Groups` (shared/fixtures/groups.json: `groupName`, a typed name trimmed
  of the listed white space, 1 to 24 code points, nil for a longer one, which
  the name field keeps as typed with "Save" off; `filterGroups`, a saved
  filter's `groups`, which `ChannelFilter.groups` mirrors and writes only
  when changed; `groupNames`, the groups that exist, in chip order;
  `chipTitle`, what a row's title shows while chips are selected;
  `groupKeptChannels` / `groupFiltered` / `keptByBoth`, the group chips'
  filter; the edits `setMembers`, `renameGroup`, `deleteGroup` and the
  editor's `saveGroup`, each a `GroupEdit` of whole filters and the two
  selections, which `SyncStore.applyGroupEdit` saves as one edit with one
  time; `groupEdited`, the listed channels an edit changes, which
  `keepingEdits` puts over a running load's older copy;
  `SyncStore.savedFilters` is every saved filter, listed or not; names are
  compared by code point everywhere, in the app too, never with `==`),
  `WatchedMode` (the watched chip: `modeFiltered`, `autoplayAdvances`,
  `emptiedBySelection`), `Autoplay`
  (`nextUnwatched`: what plays after an item ends; and the player's rules,
  shared/fixtures/player.json: `PlayerPlace` — large, card, minimized —
  `PlayQueue`, the page's list and watched chip as they were when an item
  was started, `nextInQueue`, `endOutcome` — with nothing next a card's
  player closes, the large and the minimized one stay on the ended item —
  `minimizedPlayerSize`, `largePlayerSize`),
  `Playback` (one item in
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
  `Auth` (PKCE against the iOS client, refresh token in the Keychain; the
  sign-in page always asks which account, `prompt=select_account`;
  `signOut(revoke:)` forgets the sign-in here and withdraws Google's grant
  only when asked; declining the permissions is `AuthError.declined`, shown
  as nothing; a Keychain that won't keep the token fails the sign-in).
- `App/Shared/` — SwiftUI shared by both apps: `AppModel` (sign-in, first
  run, theme; the web authentication session is started by `SignInButton`;
  "setup done" is kept per account, `subtube.onboarded.<channel id>`, and
  `introSeen` says whether any account finished it here, which opens setup
  on its sign-in screen; an account without the mark gets setup unless the
  Drive app folder holds another device's file — this device's own, written
  by a setup not finished, doesn't count (`setUpElsewhere`); Sign Out
  uploads, forgets the account here and leaves Google's grant alone, so
  other devices stay signed in; Delete Profile empties the app folder and
  local state, then signs out and revokes the grant; a load that finds this
  device's uploaded file gone — `SyncError.profileDeleted` — wipes local
  state and restarts setup, unless a fresh listing shows another device set
  the account up again; a sign-in the app can't use — no YouTube channel, a
  permission left off — is not kept),
  `FeedModel` (the feed: `shown` is everything fetched that passes the
  filters, the watched chip — `watchedMode`, kept for the visit — and the
  time and topic chips, in the `feedSort` order; `topicChips` are counted
  after the filters and the watched chip, `unwatchedByChannel` ignores the
  chips; an item that becomes watched or unwatched on screen stays until a
  full load, a filter edit, a change of the watched, time, topic or group
  chip, or a group save or delete that changes the feed's selected groups,
  not when moving between pages; `watched` and `bars` are worked out from a
  mirror of the store's entries, `entries`, and each video's length;
  everything asked of the store about entries and settings goes through one
  queue, `storeCalls`, so saves land in the order made; `recordProgress`
  saves the player's position, `resumeAt` is where a video opens;
  `player` is the one `PlayerSession`, and replacing it
  saves the old one's position: `open` starts a card, large on a Mac and in
  the card on a phone, keeping the page's list for what plays next;
  `minimize`, `minimizeCard` (a page change, and a rebuild that drops the
  card, call it), `enlarge`, `expandToCard` (only on the page the item was
  started on, while that lists it; `cardIsListed` says whether that page
  still does, whatever page shows), `closePlayer`; `playbackEnded` follows
  `nextInQueue` and `endOutcome`; `playStarts` and `cardScrolls` count
  cards started by hand and cards to scroll into view;
  `groups` are the groups that exist, `toggleGroupChip` /
  `toggleChannelGroupChip` select them, `feedTitle` / `channelListTitle`
  are the two rows' titles, `clearFeedChips` / `clearChannelChips` their
  "Clear", which writes only the settings that had something selected, `saveGroup` / `deleteGroup` the editor's two writes; the group
  chips wait for a full load (`fullLoadShown`); during a load the previous feed stays,
  greyed out, and filters edited meanwhile win over the load's copy; an
  edit to a shown channel that lacks something its filter needs —
  `isMissing`: its mode's items, or the Shorts list — fetches just that,
  after the load if one runs, six fetches at a time; the daily limit shows
  its text in place of the partial-load notice, or as the error, and drops
  the fetches still waiting; refreshing on an off channel's page refetches
  it; after setup each load, and each channel fetched by itself, marks what
  the channels still waiting for the starting point have from before it
  (`markBeforeStart`); a failed load shows `Strings.message(for:signedOut:)`
  — never an exception's own text — and the sign-in button only when
  signing in fixes it; a load that was called off shows nothing and fails no
  channel; `loadProgress` is the running full
  load's fraction, nil otherwise and for a channel fetched by itself;
  `orderedChannels` is the held rows, those the channel list's chips keep:
  `reorderChannels()` works them out again — a full load and a change of
  the channel sort, time, topic or group chips call it, a list calls it when it
  appears and when its search changes — and between those an edit, a count
  or a single channel's fetch moves no row and takes none away, and a
  channel that comes to be kept goes last; `channelTopicChips` is that
  row's topics; `explainsNoChannels` is true once a full load is shown
  and a span, a topic or a group is chosen: a list then empty, by the chips alone or
  with its search, shows "No channels for the selected filter."), `Player` (`PlayerSession`: one video
  or one real playlist, its `place`, the page it was `startedOn` and its
  `queue`; it owns its WKWebView — IFrame API, element full screen
  and inline playback on; the page's base URL and the player's `origin` and
  `widget_referrer` are `PlayerPage.identity`, `https://<bundle id>` read
  from the bundle, as YouTube asks of a native app —
  so a view showing it can go and come back without restarting it; the page
  posts the player's state and, each second while playing, its position;
  every 250 ms it checks whether the web view is in no window, in a hidden
  or minimized window, or under a sheet or anything else presented, and
  pauses the video through the page's `cover()`, which plays it again once
  clear; a `cover()` that comes before YouTube's player is ready is kept
  and pauses the video as it starts, and one the page had no script for yet
  is asked again; a card's player in no window for a second is minimized;
  for half a second after it starts in a card, and after YouTube's full
  screen ends, a card under half showing keeps the player (`isSettling`)
  while its list scrolls it into view; `PlayerNavigation` opens a link
  pressed in YouTube's player in the browser, and loads the page again
  where the video was when the web view's process dies; the page's
  `onError` ends a video like its end does, without marking it;
  the checks end with the session, and `webView` is nil once it is closed;
  `isFullScreen`: the web view is in a view that is not a `PlayerHolder`,
  so YouTube's full screen has it — until it is back there is no covered
  check, a card going out of view doesn't minimize (the session does that
  afterwards if the card still doesn't show), and a holder asking for the
  web view waits;
  `showsFrame` is set while the last tap or hover was on the video, and
  `isFramed` is that outside a card — a card's player never has a frame
  and looks like the card with the video in it: on iOS
  a `TouchWatcher` on the window sees every touch begin and takes none
  (a touch anywhere else, so also the start of a scroll, hides the frame),
  on a Mac the overlay tracks the pointer and a `ScrollWatcher` hides the
  frame on any scroll; the frame fades in and out over 0.15 s, not under
  reduced motion; its buttons are 44 pt targets on iOS, reaching up out of
  the bar, and "Expand" or "Minimize" and "Close" are also accessibility
  actions of the player, there without a hover or a tap;
  `YouTubePlayerView` fills the box it is given and draws `PlayerFrame` —
  a 37 pt bar with the title, "Expand" (minimized) or "Minimize" (Mac's
  large player), and "Close", and a
  hairline — as its background, larger than the box, so nothing is ever
  over the video and it neither moves nor resizes;
  `minimizedPlayerRoom`: while the player is minimized, a bottom inset as
  high as it and its margins after a list's last row — the feed, a
  channel's page, the Channels list and Settings on iOS, the feed grid on
  a Mac), `GroupEditor` (a
  draft, saved only by "Save", which needs a name and one channel on; on
  iOS a sheet with "Cancel" and "Save" in its bar, the name, "Search
  channels", the rows, and "Delete Group" under them; on macOS it fills
  the details panel with one bottom row, "Delete Group" leading and
  Cancel / Save trailing; only the rows scroll; `ChipTitleButtons`, the
  pencil "Edit group" and the × "Clear"), `ChipViews` (`Chip`, a
  toggle or a removable phrase, which VoiceOver names "Remove {phrase}";
  `CycleChip`, as wide as its widest label and never drawn selected, which
  VoiceOver names by what it sets and its choice: "Playback: Play one",
  "Sort: Latest", "Time: All time", "Show: Unwatched"; `AutoplayChip`, a `CycleChip` reading "Play one"
  with auto-play off and "Auto-play" with it on; `ChipRow`, which fades out
  over 40 pt at an edge with chips beyond it and shows no scroll indicator:
  its leading chips, a divider, `NewGroupChip` — round, a + alone — and the
  group toggles, a divider, then the topic toggles; there is no clear chip;
  `FeedChipRow` (no group chips on a channel's page) and `ChannelChipRow`
  (sort, time, groups, topics) are the two rows; `NoChannelsForFilter`; `FlowLayout`), `FeedViews` (also `LoadProgressBar`: 3 pt
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
  intro, sign-in, "Choose channels", "Shorts", "Where to start", done; Back
  is on every screen but the first and the last, and from "Choose channels"
  it goes to the sign-in screen, where signing in again moves on.
  `GoogleSignInButton` is Google's own button on both platforms: the
  four-colour mark (`GoogleG` in the asset catalog, Google's paths, never
  recoloured), "Sign in with Google" in exactly that capitalisation, as the
  heading over it too, on white with a #747775 stroke in light and #131314
  with #8E918F in dark; it is never Sunflower.
  On Mac it sits centred under the sign-in screen's text with the agreement
  line below it, and the bottom row there holds only the dots and Back.
  `SignInAgreement`, the line "By signing in, you agree to SubTube's Terms
  and Privacy Policy." with its two links, sits directly under every
  `GoogleSignInButton`: setup's and the Mac Settings window's when signed
  out.
  "Choose channels" shows only skeleton rows while it loads, its rows by
  name (`channelsByName`), and under a failed load "Refresh", or the sign-in
  when only that helps.
  "Choose channels" loads channels only; its Next saves the switches and
  calls `FeedModel.prefetchEnabled()`, which fetches only the channels left
  on, so one turned off costs no quota; "Shorts"' Next saves the choice and
  calls it again, so a Hide or Only choice adds the Shorts lists; the first
  full load takes the prefetch when the feed opens; the starting point is
  kept on the device, with the channels that were on, until each has been
  fetched; the decisions are in `Setup.swift`),
  `SettingsViews` (also `Links`, the three addresses the apps open;
  `LegalLinks`, "Privacy Policy" and "Terms" side by side in Settings;
  `YouTubeAttribution`, "Videos from YouTube" as a small muted link to
  youtube.com, text only: after the last card or the empty text of the feed
  and of a channel's page, not while `FeedModel.showsSkeletons`, and at the
  end of the channel list;
  `ItemCard`'s progress bar is also the control that marks an item watched
  or unwatched (`FeedModel.toggleWatched`; the card stays where it is until
  the list is next built; none on the card of the item the player has, in
  any place — card, minimized or large — since the player's own saves
  would undo the mark): a clear button
  over the bar, never over the player — on a Mac an 18 pt strip inside the
  thumbnail's bottom edge, which shows a grey track and a 7 pt bar under
  the pointer, on iOS a 44 pt target centred on the bar, half over the
  thumbnail and half over the text, with no track, only the fill; the
  fill animates unless motion is reduced; on iOS `watchedSwipe()` also puts
  the toggle on the card's list row as the system's swipe actions, the same
  grey button on both edges with an icon over "Mark watched" or "Mark
  unwatched": a full swipe toggles and the row slides back, a short one
  leaves the button showing to be tapped; how far a full swipe is, its
  haptic, the edge swipe back and VoiceOver's row action are the system's;
  not on the card of the item the player has, nor during a load), `Brand` (also `LogoMark`, sized by its hull so only the
  hull takes layout room, and `Wordmark`, the logo beside the name with the
  hull as tall as the name's line; the one shimmer, `shimmering()`, and
  `skeleton()` for stand-ins: a first load shows skeleton cards, a reload
  sweeps the greyed feed with a dark band on light and a light band on dark;
  still under reduced motion; the card that holds the player is never
  greyed, swept or disabled), `channelsMatching` (the one "Search
  channels" filter, ignoring case and nothing else: the Channels tab, the
  group editor and setup), `channelsByName` (the one by-name order, the
  shared compare), `offChannelOpacity` (0.45, every list),
  `Strings`.
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
  only from the toolbar, and the group editor takes the same panel: opening
  one replaces the other and a change of page drops the draft; while a
  row's chips are selected the sidebar's "Channels" header and the window's
  title show the names, with the pencil and × after them — the window's
  names are a toolbar item in the removed title's place, with the video
  count the subtitle had under them; a channel's page keeps its name and
  gets only the ×; no Refresh
  button: clicking the sidebar row already
  showing refreshes, as does Feed → Refresh, Cmd-R), `MacPlayerOverlay`
  draws the one player in both places with one view, so the web view never
  changes parent, and the change between the two animates over 0.2 s, not
  under reduced motion: large over the dimmed app (a button), where a click
  beside it or Escape minimizes, and minimized, 356 by 200 at the window's bottom
  trailing corner, sized by the whole window and only moved left of the
  details panel while that is open, with the
  app in use behind; the frame shows while the pointer is over the video
  or its bar — a deliberate difference from the web app, which also shows
  it on pause, on a first click and on keyboard focus: the page here
  reports none of those to the overlay
  (the window's toolbar stays above it), `FeedCommands` (Feed menu),
  Settings scene (General, Account).
- `App/iOS/` — tab bar (Feed, Channels, Settings; tapping Feed while the feed shows
  scrolls to the top and refreshes, and pull to refresh stays); the Feed and
  Channels tabs have the standard large title, alone. The Channels list's
  first row is its chip row, then `ChannelSearchField`, which narrows what
  the chips keep. The chip row, Auto-play
  first, is the first row of the feed and of a channel's page; a channel's
  page has an inline title, the channel's name, with the Filters button
  beside it and, while it has topics selected, the × "Clear" before that;
  the load bar lies over the top edge of both lists, so under the
  Feed tab's large title until that collapses, then under the bar, and is
  not drawn while a card holds the player, which it could lie over. A channel's page is
  pushed from a feed card or the Channels list (unwatched count left of each
  switch), and its Filters
  button, the filter symbol `line.3.horizontal.decrease.circle`, opens the
  filter sheet over it; a card plays in place of its
  thumbnail, one at a time (never under 200 pt high, so on a narrow phone
  the playing card is a little taller than its thumbnail). When less than
  half of it shows (`onScrollVisibilityChange`), the page or tab changes,
  or the card leaves the list, the same web view moves to the overlay on
  the tab view (a card pressed while under half of it shows is first
  scrolled into view, no further than brings it in, and plays there):
  bottom trailing, 16 pt in and 16 pt above the tab bar (the
  Feed tab reports its bottom safe area for that); that move changes the
  web view's parent, so it is not animated. "Expand" restores the
  tab and stack the card was started on (`playerOrigin`), then
  `expandToCard`; a list that appears with the player in a card scrolls to
  it. When that page no longer lists the item, "Expand" does nothing and
  the player stays minimized — a deliberate difference from the web app,
  which plays it large, and from Android, which goes to the starting page:
  a phone has no large player. The app leaving the foreground saves and
  uploads inside a background task; the video is not paused by the app, as
  on the web and unlike Android. While a row's chips are selected its tab's title is
  inline, the names, with the pencil and × as trailing bar buttons.

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
from `../design/icons/sub-play-centred.svg` (all of the logo centred on the
tile; `Logo` in the asset catalog, shown beside the name, stays hull-centred).

## Copy

All user-facing text is in `App/Shared/Strings.swift`, error messages
included: SubtubeCore's errors carry none. The one exception is the fifteen
topic labels, `categoryNames` in SubtubeCore, which the shared fixtures
check and the chip order sorts by. New wording waiting for
approval is marked `COPY-DRAFT`. The same thing is worded the same on every
platform (web, Android); only capitalization follows the platform, except
"Sign in with Google", which is Google's wording everywhere.

Capitalization by kind of control: buttons and links you can see, and row
and section labels in a form, are title case on both platforms; headings of
a screen, sheet or panel, and the tooltips and VoiceOver names of icon
buttons, are title case on a Mac and sentence case on an iPhone; chips,
placeholders, body text, messages, summaries and a dialog's question are
sentence case on both.

The iOS channel rows' one-line summary is `filterSummary` (`FeedViews`):
`filterSummaryParts` in SubtubeCore decides the parts, in the editor's order
with the topics last ("Only Music, Gaming", names by name ignoring case),
and `Strings.summary` words each.

## Run and look

- `xcodebuild -project SubTube.xcodeproj -scheme SubTube -destination 'platform=macOS' -allowProvisioningUpdates build`
- `xcodebuild -project SubTube.xcodeproj -scheme SubTube -destination 'generic/platform=iOS Simulator' build CODE_SIGN_IDENTITY=-`
- The Mac app keeps the refresh token in the data protection keychain
  (`kSecUseDataProtectionKeychain`, as on iOS), so rebuilding doesn't sign
  it out; that needs the `keychain-access-groups` entitlement, which only
  the team's development certificate can sign. A machine without it, or a
  copy to take pictures of, builds with `CODE_SIGN_IDENTITY=-
  CODE_SIGN_ENTITLEMENTS=` and its own `-derivedDataPath`: that copy runs
  `-demo` but can't keep a sign-in. Never build ad hoc into Xcode's own
  DerivedData: it replaces the signed copy.
- Debug builds take launch arguments to show screens without a Google
  sign-in: `-demo` (mockup data, no network), plus `-select:<channelId>`,
  `-play` (with `-video:<videoId>` the card plays that real video, which
  needs the network but no sign-in; use it to check the player after any
  change to `PlayerPage`), `-signedOut`, `-nux`, `-nuxStep:<0-5>`; iOS also
  `-tab:channels|settings`, `-channel:<channelId>` (with `-tab:channels`,
  opens that channel's page), `-filter:<channelId>` (the page, then its filter
  sheet), `-channelTime:<none|day|week|month>` and `-channelTopics:<id,id>` (the
  Channels list's time and topic chips; both platforms), `-topics:<id,id>`
  (the feed's), `-groups` (the demo channels in three groups),
  `-groupChips:<name,name>` and `-channelGroupChips:<name,name>`,
  `-newGroup`, `-editGroup:<name>`, `-toggleWatched:<index>` (presses the
  bar of that card of the feed), macOS `-barHover` (every card's bar as
  under the pointer); with `-play`: `-minimized`,
  `-playerFrame`, `-minimizeAfter:<seconds>`, iOS `-expandAfter:<seconds>`,
  and `-mute`, which mutes the player as soon as it is ready — always pass
  it with `-video:`, `-bottom` (the filter sheet, the feed, the Channels list and Settings
  start scrolled to the end); macOS also `-sidebarCollapsed`; both platforms
  take `-loading` (the feed as
  during a reload, its bar stopped at three channels of eight; with `-empty`,
  as during the first load), `-unwatched` (the
  watched chip on Unwatched; the demo otherwise opens on All) and `-confirmDelete` (the Delete
  Profile confirmation, once Settings shows); macOS `-settings` with
  `-snapshot:` opens the Settings window first. Values ride in the same
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
   major bump. It waits for the Apple and shared jobs of `build.yml`
   (`swift test` on a Mac runner), rewrites that platform's line, commits `ios v<version>` /
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
  belongs to its `PlayerSession`, not to the row. Moved from the card's
  holder to the overlay's and back in one update, it kept playing on the
  iPhone 17 simulator (2026-10-05).
- Nothing may be drawn over the player, not even an invisible view: the
  frame is a background, taps are watched from the window, and hover from
  a region that only reads the pointer.
- `~/Library/Containers/cc.hafa.subtube` can be unreadable from a terminal.
  A copy built with `CODE_SIGN_ENTITLEMENTS=` and its own
  `-derivedDataPath` is not sandboxed and writes `-snapshot:` to
  `$(getconf DARWIN_USER_TEMP_DIR)snapshots/<name>`.
