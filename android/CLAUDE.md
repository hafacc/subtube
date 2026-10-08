# subtube — Android

The Android app: Kotlin, Jetpack Compose, Material 3. An Android Studio project
(Gradle wrapper, version catalog in `gradle/libs.versions.toml`). The behaviour
every client shares is in `../shared/`.

## Modules

- `:core` — plain JVM (Kotlin, kotlinx.serialization, OkHttp, coroutines), no
  Android: everything below the UI.
  - `Patterns.kt` — the shared filter-pattern language: `PATTERN_META_REGEX`
    (a port of `shared/tools/pattern.ts`, checked equal to
    `shared/patterns/meta-regex.txt`), `isValidPattern`, `toEnginePattern`,
    `compilePattern`.
  - `Filters.kt` — `filterFromJson` / `filterToJson` (unknown fields and
    unchanged unrecognized values are written back; channel identity is never
    stored), `compileFilter`, `passesFilter`. A filter's optional `topics`
    (YouTube category ids) keeps only videos in one of them. A pattern is
    applied only when it reads back as phrases; `editedFilter`, which
    `SyncStore.setFilters` saves through, writes any other as empty.
  - `Phrases.kt` — `phrasesToPattern` / `patternToPhrases` (null = not
    phrases) / `phrasePatternOnly`.
  - `Progress.kt` — what a watched entry means: `isWatchedEntry` (marked, or
    a position in the last 10 seconds of a video longer than that),
    `resumePosition`, `progressFraction` (the card's bar).
  - `SyncMerge.kt` — the Drive device file kept as raw JSON entries:
    `readDeviceFile` (forgiving reader), merge (newest `at`, tie → greater
    device id), `channelsFor`. A watched entry's optional `seen`
    (`entrySeen`) is when this device last had it among a full load's items:
    `refreshSeen` sets it on the own entries a load returned (only when
    missing, not a time, or a day old; `at` untouched), and `pruneDeviceFile`
    drops own entries whose later of `at` and `seen` is 30 days old or more
    (`shared/fixtures/prune.json`). The schema check `deviceFileProblems`
    is in the tests (`core/src/test/.../DeviceFileSchema.kt`), which run it
    over what the store writes and the shared example files; the app itself
    never calls it. `JsonValues.kt` — the JSON readers every file shares
    (`stringOrNull`, `stringsOrNull`, `booleanValue`, `MAX_SAFE_INTEGER`).
  - `SyncStore.kt` — own file in memory + local storage (written off the
    caller's thread by one writer, one call at a time in the order the edits
    were made; `awaitWrites` is for tests), debounced upload,
    re-downloads only changed files, ignores non-`device-<id>.json` names,
    never overwrites an own file it can't read. `setWatched` with several ids
    and `setFilters` are one edit, so one upload. A watched entry is written
    by `markedEntry` (a mark keeps the entry's `position`, an unmark drops
    it) or `playedEntry` (`position`, with `watched` true only when the
    player reported the end); `setProgress` keeps a position on the device at
    once and starts an upload only when told to; `watchedEntry(id)` is what
    `Progress.kt` reads. `noteLoaded(ids)`, which the view model calls with
    each full load's items (not a single channel's fetch), refreshes `seen`,
    prunes, and uploads only when either changed something. Edits the Drive copy lacks
    (`unsent`: an upload failed, or the app was killed first) are uploaded
    again after the next `load`, and at once by `saveUnsent`, which the app
    calls when it leaves the screen; it asks whether anything is unsent only
    once it has the save lock, so two calls together upload once. A token
    Google refuses (401) is replaced once (`replaceToken`) and the load, save
    or delete made again. A `deleteProfile` that fails part-way
    forgets its file id and upload mark, so the next save lists the folder
    and makes a new file. `deleteProfile` deletes every
    file in the app folder, then everything local. It remembers (storage key
    `subtube.uploaded.<account>`) that its own file was uploaded; a listing
    without that file (`wasDeletedElsewhere`) is looked at a second time
    before it is believed: the mark is read before the listing is asked for,
    and then the file is asked for by its id (`DriveClient.exists`; gone
    confirms) or, with no id known, the folder is listed again. Only a
    confirmed absence drops everything local, raises `deletedElsewhere` and
    throws `ProfileDeletedException`, after which the store uploads nothing.
  - `YouTube.kt`, `Drive.kt`, `GoogleHttp.kt` — Data API and Drive REST.
    `GoogleApi` says how each words a refusal, as the web reads them: a
    YouTube 403 naming `ACCESS_TOKEN_SCOPE_INSUFFICIENT` or
    `insufficientPermissions`, or a Drive 403 with `insufficient`, is a
    missing permission; a YouTube 403 whose body has
    `error.errors[].reason` `quotaExceeded` or `dailyLimitExceeded`
    (`isDailyLimit`; not `rateLimitExceeded`) is a `DailyLimitException`:
    never retried, no token renewed. A channel YouTube has no uploads list
    for (404) has no uploads, not a failure. A subscription sent without
    thumbnails is listed; one without a channel id is left out.
  - `Shorts.kt`, `ShortsProbe.kt` — `UUSH` classification; OkHttp probe with
    redirects off. A channel YouTube has no Shorts list for (404) has no
    Shorts and nothing is probed (`fetchShortIds` gives an empty set); the
    probe runs only when the list couldn't be read (5xx twice running, or
    no answer: `fetchShortIds` gives null). `withoutShortsList`: uploads fetched without the Shorts
    list (a candidate stays unjudged, so no "Short" tag).
  - `FeedLoader.kt` — subscriptions + sync, followed channels' names via
    `channels.list?id=` (cached in `ChannelIdentityCache`; asked again only
    when missing or over a day old; a failed lookup leaves the id as the
    name, and an id YouTube no longer knows is remembered like a found one,
    so it isn't asked for at every load),
    per-channel fetch. `ChannelItems` is a channel's entries with their mode
    and whether its Shorts list was read. The Shorts list is requested only
    when `needsShorts(filter)` (uploads, Shorts on Hide or Only);
    `completeItems` returns what is held when it `covers` the filter, asks
    for the Shorts list alone (`addShortsMarks`, one request, none without a
    candidate) when only that lacks, and fetches everything otherwise.
    `fetchChannels`: once the daily limit refuses a request the channels not
    yet asked for are skipped and count as failed (`FeedData.dailyLimit`);
    its `onFinished` (the load's `onProgress`) counts each channel that is
    through, fetched, failed or skipped. `loadProgress(finished, total)` is
    the load bar's fraction: `LOAD_PROGRESS_START` (0.05) while the
    subscription list is read (`total` null), the rest shared out by channel.
    `keptAfterLoad`: after a full load a loaded channel
    keeps nothing of its other kind (uploads/playlists).
    `Prefetch.kt` — `Prefetch` fetches the channels `fetchOnly` names, 6 at a
    time, before the feed opens; a later `fetchOnly` keeps what is fetched or
    being fetched for channels still named (adding only the Shorts list when
    a filter has come to need it), queues the new ones and takes the others
    out of the queue; it stops asking after the daily limit. The `load` given
    one builds on what it has for each enabled channel.
    A channel saved with `followed: true` is read and shown; the app has no
    way to add or remove one.
  - `UnwatchedPassing.kt` — `unwatchedPassing`: a channel's entries of the
    kind it shows that pass its filter and aren't watched (the channel
    list's counts).
  - `TextOrder.kt` — the one case-insensitive compare (`foldCase`: each code
    point lowercased alone with `Locale.ROOT`; `compareCodePoints`;
    `ignoringCase`) behind the title sort, channel names and chip labels,
    and `matchesSearch`, the one search over channel names (ignores case
    only). `channelsByName` (`ChannelOrder.kt`) is the order of every list
    of channel names, first run's too.
  - `Settings.kt` — the synced settings (`SettingName`: `feedSort`,
    `channelSort`, `autoplay`, `timeChip`, `topicChips`, `groupChips`, and
    the channel list's own `channelTimeChip`, `channelTopicChips` and
    `channelGroupChips`, read the same way and independent of the feed's). `readSettings` turns
    the merged `settings` entries into `Settings`; a missing or unknown value
    reads as the default and its entry is kept. `SyncStore.settingEntries()` /
    `settings()` / `setSetting(name, value)`. `DeviceFile.settings` is null
    for a file without the section, which is then written back without it;
    the merged view always has one.
  - `FeedOrder.kt` — `sortFeed`: the feed's four orders (`FeedSort`: newest,
    shortest, title, random, as the sort chip cycles), every
    one ending in `byNewest` (newest first, equal times by id). Random sorts
    by `shuffleKey`, an FNV-1a hash of seed and id (`newShuffleSeed` picks a
    seed; the view model picks one at each full load).
  - `WatchedMode.kt` — the watched chip: `modeFiltered` (Unwatched / Watched
    / All, plus the entries that changed sides on screen), `autoplayAdvances`
    (not in Watched), `emptiedBySelection` (which empty text a page shows).
  - `ChannelOrder.kt` — `orderChannels` by `ChannelSort`. Newest (the
    default): on with something fetched by newest fetched item
    (`newestFetched`), then on with nothing fetched; filters and watched
    marks don't count, so an edit or a mark never reorders the list. Name.
    Unwatched: by `unwatchedCounts`, ties in the newest order. Off channels
    are last, by name, in every sort. `listedOrder(ordered, kept)` is the rows
    a list takes when it is put in order (`kept`: the ids its chips keep, null
    for all), and `heldOrder(held, ordered, kept)` the rows it keeps while it
    is on screen: the ids as last taken, minus those gone, then newly kept
    ones; a row the chips stop keeping stays.
  - `ChannelChips.kt` — the channel list's chips
    (`shared/fixtures/channel-chips.json`): `passingItems` (every on
    channel's fetched entries of its kind that pass its filter, watched or
    not; the topic chips are `chipRow` over them) and `chipKeptChannels` (the
    channels with one such entry inside the time span and a selected topic;
    null when neither is chosen).
  - `Chips.kt` — the fifteen topics (`CATEGORY_NAMES`, by YouTube category
    id, kept on `Video.categoryId`; `topicLabel` is null for any other id,
    which gets no chip and matches nothing), the topic chips' order
    (`chipRow`), the filter sheet's (`editorTopics`), what the time and topic
    chips keep (`chipFiltered`, `TimeChip`), and setup's starting point
    (`startMarks`, `StartFrom`).
  - `Groups.kt` — groups of channels (`shared/fixtures/groups.json`): a
    filter's `groups` are names (`groupName`: trimmed of the listed white
    space, 1 to 24 code points; `groupsFromJson` drops anything else). A
    group exists while a listed channel names it (`groupNames`, in chip
    order). `chipTitle` is what a chip row's title shows (selected groups,
    then topics, and the one group "Edit group" opens),
    `groupKeptChannels` the channels the selected groups keep (`keptByBoth`
    joins it with the time and topic chips' set). `saveGroup`, `deleteGroup`,
    `renameGroup` and `setMembers` return a `GroupEdit`: the changed filters
    and the changed `groupChips` / `channelGroupChips`.
  - `Player.kt` — the one player's rules, with no Android
    (`shared/fixtures/player.json`): `Playing` (the entry, its `PlayerPlace`
    — card or minimized; `LARGE` is the other clients', kept only so the
    shared fixture's cases run — the page it was
    started on and that page's list and watched chip then, `PlayQueue`),
    `played`, `minimized`, `afterPageChange` (a card on another page or gone
    from the list → minimized), `afterCardMeasured` (a card that can't hold
    the player → minimized), `expanded`, `afterEnd` (`nextInQueue` then
    `endOutcome`: the next unwatched entry of the list it started from, in
    its card when the page showing lists it, else minimized; with nothing
    next a card's player closes and the minimized one stays, stopped on the
    ended video, until Close or Expand: `EndOutcome.Stay`), `minimizedSize` (356×200dp, narrower on a screen under 388dp,
    never under 200 either way) and `cardHolds` (half of the thumbnail
    showing, and at least 200dp each way).
  - `SetUp.kt` — first run's rules: `commonShortsFilter` (the Shorts choice
    it starts on), and the starting point kept per channel
    (`shared/fixtures/setup-start.json`): `PendingStart`
    (the choice, when setup finished, the channels on then and not yet
    loaded), `applyStart` (marks a fetched channel's entries from before the
    starting point and takes it off the list; a failed or skipped channel
    keeps waiting) and its text form for the preferences.
  - `Swipe.kt` — `swipeMarks`: whether a card has been swiped far enough
    sideways to mark it (`SWIPE_MARK_SHARE`, a quarter of its width).
  - `Autoplay.kt` — `nextUnwatched`: the next unwatched entry after the one
    that ended, in the order shown.
  - `Playback.kt` — `Playback`: one entry in one player, with no Android:
    saves a video's position (`tick` every 5 s on the device; with an upload
    on pause, on leaving and, at once, when the app leaves the screen), marks
    it at the player's reported end and calls `onEnded`. Nothing is saved for
    a live broadcast or a playlist; a playlist is marked when its last video
    ends.
- `:app` — `cc.hafa.subtube`, minSdk 26, compile/target 37.
  - `MainActivity.kt` — edge-to-edge, Navigation 3 `NavDisplay` over
    `SubtubeViewModel.backStack` (predictive back comes from Navigation 3).
    The manifest's `configChanges` names every change Compose follows by
    itself (rotation and size, dark theme, density, font size, language,
    layout direction, a keyboard attached), so none re-creates the activity,
    which would destroy the player's web view and reload its page.
  - `ui/SubtubeViewModel.kt` — session, back stack, first run, feed, player.
    The feed (`feed`, a `ShownList`: cards plus the topic chips counted over
    them) is every fetched item that passes the filters, the watched chip
    (`watchedMode`, per visit, not synced) and the time and topic chips, in
    the `feedSort` order. A full load (Refresh, startup, back after 15
    minutes away) keeps the previous feed, greyed out and not tappable, and
    swaps in the new one when it finishes; `loadFraction` is how far it has
    come (null when none runs; not set by a single channel's fetch). Filter
    edits only re-filter; a
    channel is fetched on its own only when its filter needs something not
    fetched (`isMissing`: its mode's entries, or the Shorts list, which is
    then the only request), at most 6 at once. `watched` and `bars` are read
    from the store's entries with each video's length. A card that becomes
    watched or unwatched (`staying`) stays in the feed and on its channel's
    page until a full load, a filter edit, a change of the watched, time,
    topic or group chips (a group saved or deleted only when it changes the
    feed's selected groups) or a channel's page opening or closing; the
    sort, the tabs and single-channel fetches leave it. `settings`
    are the synced ones, re-read after every load; `setAutoplay`,
    `setFeedSort`, `setChannelSort`, `setTimeChip`, `toggleTopicChip`,
    `clearTopicChips`, `toggleGroupChip`, `clearFeedChips`,
    `setChannelTimeChip`, `toggleChannelTopicChip`, `toggleChannelGroupChip`,
    `clearChannelChips` change one here and in Drive, all through
    `changeSetting`; the clear ones write nothing for a row with nothing
    selected. `groups` is the groups
    that exist; the feed keeps only the selected groups' channels, and
    `feedTitle`, `channelsTitle` and `channelPageTitle` are the titles'
    `ChipTitle`s. `saveGroup` and `deleteGroup` save a `GroupEdit` (filters
    as one edit, then the settings) over every saved filter, listed or not;
    an edit that changes nothing saves nothing and rebuilds nothing.
    `playing` is the one player (`Player.kt`'s `Playing`): `play` puts it in
    the pressed card; `selectTab`, `pop`, `showChannel` and every `recompute`
    send a card's player to the corner when its page or card is gone
    (`pageChanged`), and nothing but `closePlayer`, sign-out and a card's
    player ending with nothing next removes it. `play` also asks the page's
    list for the pressed card (`cardRequest`), so a card pressed with less
    than half its thumbnail showing is scrolled into view and plays there.
    `playerFullscreen` keeps a card's player its card's while the video
    fills the screen and for 0.5 s after. `playerSlotMoved` / `playerSlotGone` /
    `playerViewMoved` are the playing card's thumbnail and its list reporting
    where they are (pixels, for drawing; `cardHolds` in dp decides):
    less than half showing minimizes. The thumbnail's box is the whole of
    it, also the part scrolled out of the list. `expandPlayer` goes back to the page
    the video was started on and, when that page lists the card, gives it the
    player and sets `cardRequest`, which that page's `FeedList` answers by
    scrolling the card into view and
    calling `cardShown`, also when that scroll is cut short by a touch or
    another scroll; until then the card needn't hold the player, and a
    card that still can't afterwards minimizes. `playbackEnded` is
    `afterEnd`, with the same request for a next card. `playerFramed` is
    whether the minimized player's frame shows (never for a card), `playerCovers` how many sheets and dialogs are
    open. The view model is the player's `PlaybackFeed` (`recordProgress`,
    `setWatched`, `findItem`), and `resumeAt` is where a video starts.
    `PlayerFlowTest` (Robolectric, no screen) covers these moves.
    The daily limit shows as the notice banner ("SubTube has reached
    YouTube's daily limit…") in place of the partial-load one, and as the
    step's error in first run; single-channel fetches still waiting are
    dropped.
    A refused token is renewed once and the call retried (`withToken`; the
    store does the same for its own calls). Banners (`describe`): no token
    without the user says "Sign in again to load your feed.", a refused one
    "Your Google session ended…", a missing permission "SubTube needs both
    permissions…"; only those three carry the "Sign in" button
    (`UiMessage.offersSignIn`). Anything else that fails says "Couldn't
    reach Google. Check your connection and try again." and what it was is
    logged, never shown; closing Google's sign-in page shows nothing. The
    empty-feed text is hidden while an error shows. A failed "Delete
    profile" or "Sign out" shows beside its own button (`deleteError`,
    `signOutError`), never in the feed's banner. The
    partial-load notice is a banner with Dismiss on the feed and channel pages.
    First run uses the app's own controls: `ChannelRow`, `ShortsChoice` and
    `Segmented` (the filter sheet's).
    First run: intro, sign-in, channels, Shorts, where to start, done. Next
    on "Choose channels" saves the switches as one edit and tells its
    `Prefetch` to fetch only the channels left on (nothing is fetched for a
    channel before that; going Back and pressing Next again fetches only the
    newly-on ones). The Shorts step's Next saves the choice for every channel
    when it changed and calls the prefetch again, so Hide or Only adds the
    Shorts lists. The starting point (Past day / Past week / All time) is
    kept in the preferences (`subtube.startFrom.<account>`: the choice, when
    setup finished and the channels on then) and applied a channel at a
    time: each full load, and each single channel's fetch, marks what it
    fetched of those channels from before the starting point and takes them
    off the list; a channel that failed or was skipped waits for a later
    load, and one turned on later never waited.
    "Open my feed" starts the one load, which takes the prefetch.
    After sign-in, first run lists the Drive app folder before "Choose
    channels"; another device's `device-*.json` there (`isAlreadySetUp`; this
    device's own doesn't count, since setup writes it before it is through)
    ends first run and opens the feed, and a failed listing shows the step's
    error. "Setup done" is kept per account (`AccountPrefs.isSetUpDone`):
    signing out leaves the marks, and signing in as an account without one
    runs first run from "Choose channels", wherever the sign-in was started.
    "Sign out" uploads what is unsent and forgets the account and its token
    on this device; it does not revoke Google's grant, so other devices stay
    signed in, and a sign-in from signed out asks Google for its account
    chooser. Signing out cancels a running load.
    Settings' "Delete profile" calls the store, revokes Google's grant, then
    signs out to the first setup screen; a profile deleted from another device restarts first run at
    the channel step, still signed in. `sessionEpoch` keeps a load begun on a
    replaced store from changing anything.
    `orderedChannels` is the rows of the channels tab: the channels its group, time
    and topic chips keep (`chipChannels`; every channel when none is
    chosen), by the `channelSort` setting (setup's "Choose channels" list
    stays by title), held between `reorderChannels` calls so no row moves or
    leaves while the tab is on screen: the rows are taken on entering the tab
    (`selectTab`, or `pop` back to it), after each full load, when the sort
    chip, the time chip, a group chip or a topic chip changes and when the search text
    changes (the screen calls it). `updateFilter`, a single channel's fetch
    and a watched mark pin the rows shown first (`holdChannelOrder`); rows
    still show the channel's current switch, count and dimming. The tab's chip
    row (`ChannelChipRow`: sort, time, a divider, "New group", the group
    chips, a divider, the topic chips of `channelTopics`) sits under its top bar, above the list, where
    the feed's row sits, and stays there while the search field is open; the
    search narrows the rows further. "No channels for the selected filter." shows
    when a group, a span or a topic is chosen (`channelChipsChosen`, true only once a
    full load has been shown) and no row is left, by the chips alone or with
    the search text; a search that leaves none with neither chosen shows
    nothing. Each on channel with unwatched entries
    shows their count left of its switch (`unwatchedByChannel`). There is no
    Refresh button: pulling the list down refreshes, and
    so does tapping the Feed tab while the feed is showing, which also scrolls
    it to the top. The
    feed's title is "Feed"; the wordmark is only on first run's intro.
    A channel's page (`Screen.ChannelPage`, `ui/ChannelScreen.kt`) opens from a
    card's channel name or a row of the channels tab (`showChannel`; one page
    at a time, and a playing card goes to the corner); its top bar is Back, title,
    "Clear" while a topic is selected, the filter button (`SubtubeIcons.Filters`, three shortening lines; the
    gear is only the Settings tab), and it keeps the tab bar, on the tab it
    was opened from.
    `channelFeed` is what it shows: the
    channel's fetched entries that pass its filter and the chips, on or off,
    with the feed's chips and cards (`FeedChipRow`, `FeedList`). A
    channel that is off or never fetched is fetched into `items` for its page;
    a refresh refetches an off one too. The filter button on the page opens
    the filter sheet, which has no list of its own.
  - `ui/*Screen.kt`, `ui/FilterSheet.kt` — one file per screen. The filter
    sheet hides Shorts, Live, the minimum length and Topics while Show is
    Playlists; its pattern is edited as phrases (`PhraseField`: Done or a
    comma makes a chip, pressing a chip removes it, Backspace in the empty
    field removes the last, noticed through an invisible first character),
    and "Topics" lists all fifteen as toggles. Every single-choice row
    (Show, Matches, Match in, Case, Shorts, Live, first run's Shorts and
    starting point, and Settings' Theme) is the one full-width `Segmented`
    (`ui/Components.kt`), and every search over channels is the one
    `SearchField` there (first run, the channels tab's top bar, the group
    editor); chips are only for
    what can have several on (topics, phrases).
  - `ui/Links.kt` — the links out of the app (`openInBrowser`). Settings
    ends with "Privacy policy" and "Terms" side by side
    (https://subtube.hafa.cc/privacy, `/terms`); first run's sign-in step has
    `SignInAgreement` ("By signing in, you agree to SubTube's Terms and
    Privacy Policy.", both linked) under its button, which is
    `GoogleSignInButton` (`ui/Components.kt`): Google's standard button, its
    four-colour mark (`drawable/google_g.xml`, never recoloured) on white
    with a #747775 outline and #1F1F1F text, or on #131314 with #8E918F and
    #E3E3E3 in the dark theme. The banner's "Sign in" is a plain text button. `YouTubeAttribution` is
    "Videos from YouTube", text only, a link to youtube.com: the last row of
    `FeedList` (feed and channel pages, after the cards or the empty text,
    not during the first load's skeletons) and of the channels tab's list.
    Their wording is approved text; don't reword it.
    `MainNavigationBar` (`ui/Components.kt`) draws its own items so the
    current tab's highlight covers icon and label. `Wordmark` sizes the logo
    so its hull (0.518 of the drawing) is four fifths of the name's line
    height; only the hull takes up room and the tower rises above it.
  - `ui/ChipRow.kt` — `Chip` (a toggle, or a removable phrase, which
    TalkBack names "Remove {phrase}") and
    `CycleChip` (shows the current choice, a press moves to the next; as wide
    as its widest label; TalkBack names it by what it sets and its choice:
    "Playback: Play one", "Sort: Latest", "Time: All time", "Show: Unwatched"), the same box selected or not, `AutoplayChip`
    (a `CycleChip` over the `autoplay` setting: "Play one" when off, the
    default, "Auto-play" when on; never drawn selected; private to this
    file), `ChipRow` (the row both lists use: its leading chips; with
    `GroupChips`, given once a load has been shown and never on a channel's
    page, a divider, the round + "New group" chip and the group chips; then,
    when there are topic chips, a divider and the topic chips) and
    `FeedChipRow`: auto-play, sort, time, watched, then the groups and topics;
    it scrolls sideways and fades out over 40dp at a side that has chips
    beyond it (`fadingScrollEdges`). `ChipTitleText` is a top bar's title
    while its row has a group or topic selected (the names joined with ", ",
    one line) and `ChipTitleActions` the actions that go with it: the pencil
    "Edit group" with exactly one group selected, and × "Clear", each
    fading and widening in and out (`TitleAction`); the channels tab's
    Search follows them.
  - `ui/GroupEditor.kt` — the group editor, a bottom sheet
    (`GroupEditorState` opens it from the + chip or the pencil): title,
    "Name" (one over 24 code points is kept as typed and can't be saved;
    Done only hides the keyboard), "Channels"
    with the "Search channels" field over every listed channel by name as a
    `ChannelRow` whose switch is membership (only off channels are dimmed),
    and a bottom row with "Delete group" (only while the group still exists; deletes at once),
    Cancel and Save. It edits a draft: only Save writes, and Save needs a
    name and one channel on. Only the rows scroll. Cancel, Save and Delete
    slide the sheet away (`sheetState.hide()`) before it is removed, as the
    filter sheet's Done does.
  - `ui/PlayerHost.kt` — the one player. `PlayerHost` wraps `NavDisplay` in
    `MainActivity` and lays a single WebView over the screens; the view is
    never re-created or given another parent while something plays, only
    moved and resized (`PlayerBoxes` works out where; `shown` is derived
    state, so a scrolling card moves the view in the layout phase without
    recomposing anything): over the playing card's thumbnail
    (`PlayerCardSlot`, an empty box at least 200dp high that reports its
    whole box, `positionInRoot` and size, not `boundsInRoot`, which is cut
    to what the list shows; the video is cut off where the card's list
    ends) or in the bottom trailing corner, 24dp in and 8dp above the
    navigation bar (`PlayerDock`, which `MainNavigationBar` reports its top
    edge to) or the keyboard. While it is a card's and that card has not
    been laid out (the frame after a press, or a list still scrolling to
    the card) it is drawn nowhere, at no size. The move between card and
    corner is not animated: a web view redraws a new size late, so the
    video would show stretched on the way.
    The same view takes each next entry by loading a new page. The page
    reports as JSON messages through `SubtubePlayer.postMessage`
    (`PlayerBridge`), each carrying the page's token, a random UUID made per
    load (`PlayerPage.load`); any other token is dropped. Where the WebView
    has message listeners (androidx.webkit's `addWebMessageListener`, asked
    of `WebViewFeature`), only the page's own origin and main frame get the
    object, so the YouTube frames inside cannot call it; an older WebView
    falls back to `addJavascriptInterface`, where the token alone keeps
    them out. `PlayerPage` also holds what may play: `cover` (a sheet or
    dialog is open: `CoversPlayer`, called by the filter sheet, the group
    editor and the delete confirmation, pauses and plays again after, if
    that is what paused it) and `stop` / `start` (the activity's ON_STOP and
    ON_START: the position is saved at once and the video pauses, and stays
    paused on return). A page that reports it started playing while covered
    or stopped is paused at once, so a page still loading when the app
    leaves cannot play in the background. It drives one `Playback` per
    entry, saves on leaving, and shows the WebView's full-screen custom view
    over the activity's window, turned to landscape unless the video is a
    Short. When the IFrame API doesn't load, the web view is hidden and the
    failure text stands in its place. When the web view's renderer is gone
    (killed by the system, or crashed) the player closes
    (`onRenderProcessGone`); unhandled, that would take the app down. To a
    screen reader the player is named by the video's title, else "Player",
    with the actions "Expand" or "Minimize", and "Close".
    A video in its card has nothing of ours around it. The frame
    (`PlayerFrame`) is the minimized player's only: drawn behind the video,
    1dp past its sides and bottom with a 48dp bar above (title, "Expand",
    "Close"), fading in and out. The host watches every touch on its way
    down (`PointerEventPass.Initial`, nothing consumed): one on the
    minimized video shows the frame, one anywhere else but the frame, which
    is also how a scroll starts, hides it. That is deliberately not the
    web's rule, which also shows the frame when the player reports a pause
    or play the app didn't ask for, and on hover. Lists and Settings keep
    `minimizedPlayerRoom` under their last row while the player is in the
    corner. `PlayerPageTest` covers the token, covering and stop/start;
    `PlayerLayoutTest` runs the real list in the real activity (a card
    partly under the list's edge, and a scroll to the next card cut short).
    `FeedCard` draws a 4dp Sunflower bar along the thumbnail's bottom edge
    (`WatchedBar`), with no track along the rest; the bar is a
    control for marking: `WatchedBarTarget`, a 48dp strip reaching 32dp up
    over the thumbnail and 16dp down over the text (taking no room, above
    both, and short of the title's first line, which still plays), calls
    `setWatched` with the opposite state ("Mark watched" / "Mark unwatched")
    and never plays. The fill runs to its new width unless animation is
    off. Swiping the card sideways, either way, does the same
    (`SwipeToMark`, a Material `SwipeToDismissBox` that never dismisses):
    the card follows the finger over a strip (`MarkStrip`: an eye, or a
    struck-through eye, and the same text, at the side being uncovered) and
    always settles back; let go at a quarter of its width or more
    (`swipeMarks` in `:core`'s `Swipe.kt`, whatever the speed) it is marked,
    and a tick is felt on getting that far. The box is made with its
    deprecated `confirmValueChange`, always false, because that is the only
    way it settles back instead of sliding its content away; it never says
    when the finger lifts, so a `pointerInput` ahead of it watches for that
    (`PointerEventPass.Initial`, nothing consumed). With animation off the
    card stays put under the finger and only the mark changes. The
    thumbnail, where a screen reader finds "play", carries the mark as a
    custom action. The card stays where it is until the list is next rebuilt. The
    card of the entry the player has, in the card or in the corner, has no
    strip, no action and no swipe: the player's next save of its position would undo
    the mark (decided for every client). The card holding the player also
    has no `animateItem`, because the player cannot follow a card that
    slides. Watched cards are not dimmed. `MarkWatchedTest` presses the
    strip and swipes the card in the real activity.
  - `ui/Loading.kt` — how loading looks: `Modifier.shimmer` (the one shimmer:
    a band 40% of what it crosses wide, crossing every 1.4 s, off when the
    system's animator scale is 0;
    lighter and cut to their shapes on skeletons, and with `overCards` black
    at 16% on light or white at 22% on dark across the whole list area, gaps
    included) and the skeletons (`SkeletonCards`, `SkeletonChannelRows`), which
    screen readers get as one indeterminate progress. `FeedList` shows
    skeleton cards instead of the pull spinner while a load has nothing to
    show, and runs the `overCards` shimmer over the greyed cards on a reload (the pull
    spinner then shows only where the shimmer is off); first run
    shows skeleton rows alone, with no heading, while its channel list loads,
    and keeps the search field and the count when there are no subscriptions. `LoadProgressBar` is a 3dp
    Sunflower bar laid over the top edge of the feed and of a channel page
    (under the top bar, over the chip row, taking no room) showing
    `loadFraction`: it moves to each value in 0.2 s, runs to the end when the
    load finishes and fades out, gone 0.5 s after; with animation off it jumps and vanishes. It has
    progress semantics while a load runs and no text.
  - `ui/Theme.kt` — Sunflower light/dark schemes (no dynamic color) on
    slightly blue greys, white page on light and `#121418` on dark, plus
    `MaterialTheme.brand.accent` (dark gold on light) for text-coloured
    accents, since `primary` is Sunflower. The logo is `drawable/logo.xml`, the same on light and dark:
    `design/icons/sub-play.svg`'s paths under the same translate and scale.
    The launcher icon (`ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`)
    is those paths at 2.42, placed so the smallest circle holding all of the
    logo, tower included, is centred on the 108dp canvas: launchers cut the
    icon to a circle, and centring the logo's box instead leaves it looking
    low. It sits inside the 66dp safe circle. `ui/SubtubeIcons.kt` — the
    mockups' stroke icons as `ImageVector`s.
  - `auth/GoogleAuth.kt` — Play services `AuthorizationClient`; expiry from
    tokeninfo (the token goes in the request's body, not its address).
    `authorize(chooseAccount)` asks for the account chooser on a sign-in from
    signed out; `signOut` only clears the token on this device and throws
    when Play services can't (shown as "Couldn't reach Google…" beside Sign out); `revoke` withdraws the grant (delete profile).

## Build, test, run

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :core:test :app:assembleDebug
```

`:core:test` loads every fixture in `../shared/fixtures` (path passed as the
`subtube.shared` system property in `core/build.gradle.kts`). Install with
`adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## Demo mode (debug builds only)

`app/src/debug/kotlin/cc/hafa/subtube/Demo.kt` shows the app on made-up data
(the Apple apps' `-demo` channels and videos) with no sign-in and nothing
loaded, saved or synced; the release source set has a no-op in its place. It
is read from the launch intent, through `SubtubeViewModel.showDemo`:

```sh
adb shell am start -S -n cc.hafa.subtube/.MainActivity --ez demo true \
  --es screen channel --es channel UCTwo
```

`screen` is `feed` (default), `channels`, `settings`, `channel` (with
`channel` = `UCOne` … `UCEight`, default `UCOne`), `player` (the feed with
its first unwatched card playing in place), `minimized` (the same with the
player in the corner) or `setup` (with `step` = `intro`,
`sign_in`, `channels`, `shorts`, `start`, `done`). `--es loading first` or
`reload` shows a load running (skeleton cards, or the feed greyed out, with
the load bar at 3 channels of 7);
`--es watched all` sets the watched chip. Channels One, Three and Five are
in the group "Woodworking", Two and Six in "Evenings". The filter sheet, the
group editor and the delete confirmation are opened by tapping. The player still asks
YouTube for the made-up video id.

## Screenshots without a device

`app/src/testDebug/kotlin/cc/hafa/subtube/ScreenshotsTest.kt` starts the real
`MainActivity` under Robolectric, gives it `demoData(…)` and saves each
screen as a PNG with Roborazzi (both test-only dependencies; JUnit 4 and
Compose's `ui-test-junit4` come with them). Phone-sized (411×914dp at 420dpi),
light, plus some dark ones, the channels tab with a time and a topic chip chosen (Past month, so it empties once the demo's dates are over 30 days old) and with nothing for the selection, the feed's chip row scrolled to its topic chips, the group screens (a group selected in each list, a group and a topic, both editors), the player (in its card, and in the corner with and without the frame, over another tab, and on a 360dp-wide screen), a one-card feed (so the line at the end of the list shows), a card held part-way through a swipe each way and the loading states (first load, and reload in light and dark; taken with the test
clock stopped part-way through a shimmer sweep). The web view
comes out black. `PlayerFlowTest`, `PlayerPageTest`, `PlayerLayoutTest` and
`MarkWatchedTest` run in the same task.

```sh
./gradlew :app:testDebugUnitTest -Pscreenshots=/some/folder
```

Without `-Pscreenshots` the PNGs go to `app/build/screenshots`.

## Releases (Google Play)

`.github/workflows/android-cut.yml` (run by hand with patch/minor/major)
waits for the Android and shared jobs of `build.yml`, bumps `versionName` and `versionCode` in
`app/build.gradle.kts` on main, commits and tags `android-v<version>`, then
starts `android-publish.yml` on that tag. That one has two jobs. `bundle`
restores the upload keystore, builds the signed bundle, keeps it as the
run's artifact (`subtube-android-v<version>`) and makes the GitHub release
with notes since the previous `android-v` tag. `play` uploads that same
bundle as a draft (`:app:publishReleaseBundle --artifact-dir`, Gradle Play
Publisher, track `internal`); if Play refuses, re-run the failed job and it
uploads the bundle already built. Roll the draft out and promote it in the
Play Console.
Both workflows and `build.yml` install Java 25, the version
`gradle/gradle-daemon-jvm.properties` says the build runs on.

Signing: `storeFile`, `storePassword`, `keyAlias` and `keyPassword` come from
`android/keystore.properties` (git-ignored) or `-Psubtube.<name>`. Without
them a release build is debug-signed: `./gradlew :app:bundleRelease` works
and installs locally, but Play won't accept it. Never commit a keystore.

Secrets (repository secrets, no environment): `ANDROID_KEYSTORE` (the upload
keystore, base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON` (a service account with
release access to the app in Play). The publisher can't create the app: the
first bundle is uploaded by hand in the Play Console. So the first cut's `play` job
fails, and the bundle to upload is that run's artifact. Play re-signs with its
own app signing key, so the store build needs its own Android OAuth client
(that key's SHA-1) beside the upload key's and the debug key's.

## Sign-in setup

There is no client id in the code. Google matches the app by package name
and signing certificate: create an **Android** OAuth client in the
`subtube-dev` Cloud project with package `cc.hafa.subtube` and the SHA-1 of
each signing key (debug: `keytool -list -v -keystore ~/.android/debug.keystore
-storepass android`). Until it exists, sign-in fails.

## Gotchas

- The player page's base URL, and the `origin` and `widget_referrer` it
  hands the embed, are `https://<application id>` (`playerOrigin` in
  `ui/PlayerHost.kt`, from `Context.packageName`): YouTube's rules want a
  native app to identify itself by its own id, and with no referrer at all
  the embed is refused (error 153). It pauses on stop, and a page that
  starts playing while stopped is paused too (no background play).
- The player has played a video in its card on a Pixel 8a (the web view
  needs `MATCH_PARENT` layout params, or the page's 100% height is 0 and
  the video is black). Still unverified there: that the web
  view keeps playing while it is moved and resized, that it follows a
  scrolling card without trailing a frame behind, that its rounded corners
  clip the video, that a touch on the video reaches both YouTube's
  controls and the frame, and that the message listener's origin rule
  matches a page loaded with `loadDataWithBaseURL` (if it didn't, nothing
  the player reports would arrive: no saved position, no next video).
- The swipe on a card has never run on a device. Unverified there: how it
  feels beside the list's own scroll, the tick, and that the system's back
  gesture, which starts within the 16dp margin and a little of the card,
  leaves enough of the card to start a swipe on.
- A screen under 388dp wide has thumbnails under 200dp high, so the playing
  card's box grows to 200dp while it holds the player.
- Sign-out no longer revokes, so that the next silent token is for the
  account picked in Google's chooser has not been checked on a device.
- Never edit `../shared`; change the spec there first, then this client.
- `local.properties` is machine-specific and ignored; without it, set
  `ANDROID_HOME` to the SDK.
