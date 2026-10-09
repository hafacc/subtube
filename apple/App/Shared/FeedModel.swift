import Foundation
import Observation
import SubtubeCore
import os

/// Errors kept out of the interface.
let appLog = Logger(subsystem: "cc.hafa.subtube", category: "app")

/// The feed for one account.
///
/// What is shown is every fetched item that passes the filters, the watched
/// chip and the time and topic chips, in the chosen order. An item that
/// becomes watched or unwatched while on screen stays until a full load
/// finishes, a filter is edited, or the watched, time or topic chip changes;
/// moving between the feed and channel pages keeps it. While a load runs the
/// previous feed stays.
/// How much a load fetches: the channels alone, or their items too.
private enum LoadDepth: Comparable {
  case channels
  case items
}

@MainActor @Observable
final class FeedModel {
  /// Returning to the app after this long away loads the feed again.
  private static let staleAfter: TimeInterval = 15 * 60

  let account: ChannelSummary
  private let auth: GoogleAuth
  private let store: SyncStore
  private let probe = ShortsProbe()
  /// Everything asked of the store about watched entries and settings, in
  /// the order asked.
  @ObservationIgnored private let storeCalls:
    AsyncStream<@Sendable (SyncStore) async -> Void>.Continuation

  /// The channels with their filters, subscriptions first as YouTube lists
  /// them; edits apply here at once and sync through Drive.
  private(set) var channels: [ChannelFilter] = [] {
    didSet {
      // compiling a pattern is the costly part, so a filter that didn't change keeps its own
      let before = Dictionary(oldValue.map { ($0.channelId, $0) }) { first, _ in first }
      var recompiled: [String: CompiledFilter] = [:]
      for channel in channels where recompiled[channel.channelId] == nil {
        if before[channel.channelId] == channel, let unchanged = compiled[channel.channelId] {
          recompiled[channel.channelId] = unchanged
        } else {
          recompiled[channel.channelId] = compileFilter(channel)
        }
      }
      compiled = recompiled
      modes = Dictionary(channels.map { ($0.channelId, $0.contentMode) }) { first, _ in first }
      channelGroups = Dictionary(channels.map { ($0.channelId, $0.groups) }) { first, _ in first }
      let names = groupNames(channelGroups.values)
      if !names.elementsEqual(groups, by: sameScalars) {
        groups = names
      }
    }
  }
  /// The channel lists' rows as last worked out; edits neither move nor
  /// remove them.
  private var heldOrder = HeldChannelOrder()
  private var compiled: [String: CompiledFilter] = [:]
  /// Every listed channel's groups, by channel id.
  private var channelGroups: [String: [String]] = [:]
  /// The groups that exist, in chip order.
  private(set) var groups: [String] = []
  /// Every filter saved on any device as of the last load, by channel id;
  /// the channels no longer listed are read from here.
  private var savedFilters: [String: JSONObject] = [:]
  /// Whether each channel shows uploads or playlists.
  private var modes: [String: ContentMode] = [:]
  /// The channels the account subscribes to on YouTube.
  private(set) var subscribedIds = Set<String>()
  /// Every item fetched, for the feed or a channel page.
  private var items: [String: FeedItem] = [:] {
    didSet { index = nil }
  }
  /// `items` by channel; nil until asked for after they changed.
  @ObservationIgnored private var index: ItemIndex?
  /// Each `publishedAt` read so far, in milliseconds since the epoch; nil
  /// inside for one that isn't a time.
  @ObservationIgnored private var publishedTimes: [String: Int64?] = [:]
  /// What each channel's items have been fetched as.
  private var fetched: [String: Set<FetchMark>] = [:]
  /// The loaded items' watched entries, as last read from the store or
  /// edited here.
  private var entries: [String: WatchedEntry] = [:]
  private var editSerial = 0
  /// The `editSerial` of each entry's last edit here.
  private var editedAt: [String: Int] = [:]
  /// The loaded items that are watched.
  private(set) var watched = Set<String>()
  /// How full each loaded video's progress bar is, from 0 to 1; a video with
  /// no bar is absent.
  private(set) var bars: [String: Double] = [:]
  /// The items on screen, in the order shown.
  private(set) var shown: [FeedItem] = []
  /// The topic chips to show, as category ids in row order.
  private(set) var topicChips: [String] = []
  /// The channel lists' topic chips, as category ids in row order.
  private(set) var channelTopicChips: [String] = []
  /// The channels the channel lists' chips keep; nil while they keep all.
  private var chipChannels: Set<String>?
  /// Whether a full load has been shown; the group chips wait for it.
  private(set) var fullLoadShown = false
  /// Each on channel's unwatched items that pass its filter, counted;
  /// channels with none are absent.
  private(set) var unwatchedByChannel: [String: Int] = [:]
  /// The `publishedAt` of the newest of the items ``unwatchedByChannel``
  /// counts, by channel id.
  private var newestUnwatchedByChannel: [String: String] = [:]
  /// Became watched or unwatched here since the list was last rebuilt for
  /// good; these stay on screen whatever the watched chip lists.
  private var staying = Set<String>()

  /// The synced settings, as of the last load plus changes made here since.
  private(set) var settings = SyncedSettings()
  private var settingEdits = 0
  /// Which of watched and unwatched items the page lists; kept for the visit.
  private(set) var watchedMode = WatchedMode.visitStart
  /// Fixes the random order until the next full load or reshuffle.
  private var shuffleSeed = newShuffleSeed()
  /// The time the time chips count back from.
  private var chipClock = epochMilliseconds()

  /// The channel page shown, or nil for the whole feed.
  var selectedChannel: String? {
    didSet {
      if selectedChannel != oldValue {
        viewChanged()
      }
    }
  }

  /// The single-channel fetches running or waiting for a slot.
  private var fetching = Set<ChannelKind>()
  private var activeFetches = 0
  private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
  /// Goes up when YouTube's daily limit refuses a fetch; fetches that waited
  /// through it aren't sent.
  private var refusals = 0
  /// Filters edited while a load ran; the load's own copy is older.
  private var editsDuringLoad: [String: ChannelFilter] = [:]
  /// Channels to fetch once the running load ends.
  private var fetchAfterLoad = Set<String>()
  /// Whether a single channel is being fetched.
  var channelLoading: Bool { !fetching.isEmpty }
  /// The items of the channels left on in the first run, on their way since
  /// "Choose channels"; the next full load takes it.
  private var setupPrefetch: Prefetch?
  /// The last call telling `setupPrefetch` which channels to have.
  private var prefetchCall: Task<Void, Never>?

  private(set) var loading = false
  /// How far the running full load is, from 0 to 1; nil when none runs.
  private(set) var loadProgress: Double?
  /// Whether the channels are known: a full or a channels-only load finished.
  private(set) var channelsLoaded = false
  /// The demo feed: nothing loads or syncs.
  private var offline = false
  private(set) var error: String?
  /// Whether only an interactive sign-in can fix `error`.
  private(set) var needsReconnect = false
  var notice: String?
  /// What is playing; one item at a time. Replacing it saves the old one's
  /// position.
  var player: PlayerSession? {
    didSet {
      if oldValue !== player {
        oldValue?.close()
      }
    }
  }
  /// Counts the cards played by hand, so a view can note where each started.
  private(set) var playStarts = 0
  /// Counts the times the playing card is to be scrolled into view.
  private(set) var cardScrolls = 0
  /// The Google account's name and address, once asked.
  private(set) var user: DriveUser?
  private(set) var lastSyncedAt: Date?
  /// When a full load last succeeded.
  private var lastLoadedAt = Date.distantPast
  /// What a load asked for while another was running wanted.
  private var loadAskedMeanwhile: LoadDepth?
  /// Called when a load finds the profile was deleted from another device.
  var onProfileDeleted: (() -> Void)?

  init(account: ChannelSummary, auth: GoogleAuth) {
    self.account = account
    self.auth = auth
    let directory = URL.applicationSupportDirectory.appendingPathComponent("subtube")
    let store = SyncStore(
      accountId: account.channelId, tokens: auth, directory: directory, deviceId: deviceId())
    self.store = store
    let (calls, continuation) = AsyncStream.makeStream(
      of: (@Sendable (SyncStore) async -> Void).self)
    storeCalls = continuation
    Task.detached {
      for await call in calls {
        await call(store)
      }
    }
    Task { [weak self] in
      // what this device last knew, until the first load has Drive's
      let kept = await store.settings()
      if let self, self.settingEdits == 0, !self.channelsLoaded {
        self.settings = kept
        self.rebuild()
        self.reorderChannels()
      }
    }
  }

  deinit {
    storeCalls.finish()
  }

  /// Change the store after every earlier change; nothing in the demo feed.
  private func write(_ change: @escaping @Sendable (SyncStore) async -> Void) {
    if !offline {
      storeCalls.yield(change)
    }
  }

  /// Read the store once every earlier change has reached it.
  private func read<Value: Sendable>(_ value: @escaping @Sendable (SyncStore) async -> Value)
    async -> Value
  {
    await withCheckedContinuation { continuation in
      storeCalls.yield { store in continuation.resume(returning: await value(store)) }
    }
  }

  /// Unwatched items the whole feed would show, whatever page is open or
  /// chip selected.
  var unwatchedCount: Int {
    unwatchedByChannel.values.reduce(0, +)
  }

  /// Whether the page shows stand-in cards: nothing to show yet, and a load
  /// running.
  var showsSkeletons: Bool {
    shown.isEmpty && (loading || channelLoading)
  }

  /// What an empty page says.
  var emptyText: String {
    if emptiedBySelection(
      mode: watchedMode, timeChip: settings.timeChip, topicChips: settings.topicChips,
      groupSelected: selectedChannel == nil
        && !selectedGroups(groups, selected: settings.groupChips).isEmpty)
    {
      Strings.noVideosForFilter
    } else {
      Strings.noMatches
    }
  }

  /// The channels every channel list shows, in order: those its chips kept
  /// at the last ``reorderChannels()``, with channels kept since then at the
  /// end.
  var orderedChannels: [ChannelFilter] {
    let byId = Dictionary(channels.map { ($0.channelId, $0) }) { first, _ in first }
    return heldOrder.ids.compactMap { byId[$0] }
  }

  /// What the feed's or a channel page's title shows while chips are
  /// selected; a channel's page has no groups.
  var feedTitle: ChipTitle {
    chipTitle(
      groups: selectedChannel == nil ? groups : [], groupChips: settings.groupChips,
      topics: topicChips, topicChips: settings.topicChips)
  }

  /// What the channel lists' title shows while chips are selected.
  var channelListTitle: ChipTitle {
    chipTitle(
      groups: groups, groupChips: settings.channelGroupChips, topics: channelTopicChips,
      topicChips: settings.channelTopicChips)
  }

  /// Whether a channel list that is empty says so: a full load has been
  /// shown and its time chip, a topic chip or a group chip is chosen.
  var explainsNoChannels: Bool {
    fullLoadShown && chipChannels != nil
  }

  /// Work the channel lists' rows and order out again. A list asks when it
  /// appears and when its search changes; a full load and a change of a
  /// channel list chip do it themselves.
  func reorderChannels() {
    var order = heldOrder
    order.recompute(freshChannelOrder(), kept: listKept)
    if order != heldOrder {
      heldOrder = order
    }
  }

  /// Keep the channel lists' rows in place, adding channels kept since.
  private func holdChannels() {
    var order = heldOrder
    order.hold(freshChannelOrder(), kept: listKept)
    if order != heldOrder {
      heldOrder = order
    }
  }

  /// The channel ids in the order their sort gives them now.
  private func freshChannelOrder() -> [String] {
    let newest = itemIndex().newest
    return channelOrder(
      channels.map { channel in
        ChannelOrderEntry(
          id: channel.channelId, title: channel.title, enabled: channel.enabled,
          newest: newest[channel.channelId],
          unwatched: unwatchedByChannel[channel.channelId] ?? 0,
          newestUnwatched: newestUnwatchedByChannel[channel.channelId])
      }, sort: listOrder)
  }

  /// The channels the channel lists keep, nil for all of them. The Mac's
  /// sidebar has no chips, so it keeps every channel whatever the phone
  /// apps' chips have selected.
  private var listKept: Set<String>? {
    #if os(macOS)
      nil
    #else
      chipChannels
    #endif
  }

  /// The channel lists' order: the Mac's sidebar is always newest unwatched
  /// first, whatever the phone apps' sort is.
  private var listOrder: ChannelListOrder {
    #if os(macOS)
      .newestUnwatched
    #else
      settings.channelSort.order
    #endif
  }

  func channel(_ channelId: String) -> ChannelFilter? {
    channels.first { $0.channelId == channelId }
  }

  /// Whether the channel is shown because it was added in subtube.
  func isFollowedOnly(_ channelId: String) -> Bool {
    !subscribedIds.contains(channelId) && channel(channelId)?.followed == true
  }

  /// Everything fetched for a channel, whatever its filter keeps.
  func channelFetched(_ channelId: String) -> [FeedItem] {
    itemIndex().byChannel[channelId] ?? []
  }

  private func itemIndex() -> ItemIndex {
    // read even when the index is there, so a view that asks is redrawn when the items change
    let all = items
    if let index {
      return index
    } else {
      var built = ItemIndex()
      for item in all.values {
        built.byChannel[item.channelId, default: []].append(item)
        if let known = built.newest[item.channelId],
          !known.utf8.lexicographicallyPrecedes(item.publishedAt.utf8)
        {
          continue
        }
        built.newest[item.channelId] = item.publishedAt
      }
      index = built
      return built
    }
  }

  /// An item's `publishedAt` in milliseconds since the epoch, read once for
  /// each time; nil when it isn't one.
  private func publishedTime(_ item: FeedItem) -> Int64? {
    if let known = publishedTimes[item.publishedAt] {
      return known
    } else {
      let read = parseTimestamp(item.publishedAt)
      publishedTimes[item.publishedAt] = .some(read)
      return read
    }
  }

  /// When an item was published; nil when YouTube sent something unexpected.
  func publishedDate(_ item: FeedItem) -> Date? {
    publishedTime(item).map { Date(timeIntervalSince1970: Double($0) / 1000) }
  }

  /// Whether an item is the kind its channel currently shows.
  private func matchesMode(_ item: FeedItem) -> Bool {
    let mode = modes[item.channelId] ?? .videos
    switch item {
    case .video: return mode == .videos
    case .playlist: return mode == .playlists
    }
  }

  private func isOnDemand(_ channelId: String) -> Bool {
    channel(channelId)?.enabled != true
  }

  /// Everything the feed and the channel lists could show, watched or not:
  /// the one pass of the filters over everything fetched.
  private func feedPassing() -> [FeedItem] {
    listedItems(items.values, filters: compiled, modes: modes)
  }

  /// Everything a page could show, watched or not, out of `feedPassing`
  /// (``feedPassing()``); `page` is a channel's id, or nil for the feed.
  private func passing(on page: String?, feedPassing: [FeedItem]) -> [FeedItem] {
    if let page {
      let filter = compiled[page]
      if filter?.enabled == true {
        return feedPassing.filter { $0.channelId == page }
      } else {
        // a channel that is off is not among them
        return channelFetched(page).filter { item in
          matchesMode(item) && (filter.map { itemPassesFilter(item, $0) } ?? true)
        }
      }
    } else {
      return feedPassing
    }
  }

  /// What a page lists, unordered: `beforeChips` after the filters and the
  /// watched chip, `kept` after the group, time and topic chips too. `page`
  /// is a channel's id, or nil for the feed; another page than the one
  /// showing is listed as it will be once it is opened. `feedPassing` is
  /// ``feedPassing()``.
  private func listed(on page: String?, feedPassing: [FeedItem])
    -> (beforeChips: [FeedItem], kept: [FeedItem])
  {
    let beforeChips = modeFiltered(
      passing(on: page, feedPassing: feedPassing), mode: watchedMode, watched: watched,
      staying: page == selectedChannel ? staying : [])
    let inGroups = groupFiltered(
      beforeChips,
      kept: page == nil ? groupKeptChannels(channelGroups, selected: settings.groupChips) : nil)
    return (
      beforeChips,
      chipFiltered(
        inGroups, timeChip: settings.timeChip, topicChips: settings.topicChips, now: chipClock,
        published: publishedTime)
    )
  }

  /// Work out what the page shows, both rows' topic chips, the unwatched
  /// counts and the channels the channel lists' chips keep.
  private func rebuild() {
    let listed = feedPassing()
    let (beforeChips, kept) = self.listed(on: selectedChannel, feedPassing: listed)
    topicChips = chipRow(beforeChips, selected: settings.topicChips)
    shown = sortFeed(kept, by: settings.feedSort, seed: shuffleSeed)
    var counts: [String: Int] = [:]
    var newestUnwatched: [String: String] = [:]
    for item in listed where !watched.contains(item.id) {
      counts[item.channelId, default: 0] += 1
      if let known = newestUnwatched[item.channelId],
        !known.utf8.lexicographicallyPrecedes(item.publishedAt.utf8)
      {
        continue
      }
      newestUnwatched[item.channelId] = item.publishedAt
    }
    unwatchedByChannel = counts
    newestUnwatchedByChannel = newestUnwatched
    channelTopicChips = chipRow(listed, selected: settings.channelTopicChips)
    chipChannels = keptByBoth(
      groupKeptChannels(channelGroups, selected: settings.channelGroupChips),
      chipKeptChannels(
        listed, timeChip: settings.channelTimeChip, topicChips: settings.channelTopicChips,
        now: chipClock, published: publishedTime))
    holdChannels()
    if let player, player.place == .card, !shown.contains(where: { $0.id == player.item.id }) {
      minimize()
    }
  }

  private func viewChanged() {
    // a card plays in its list; another page is another list
    minimizeCard()
    staying = []
    rebuild()
    if let selectedChannel {
      fetchIfMissing(selectedChannel)
    }
  }

  /// The first load, and a load on returning after a while away.
  func appeared() {
    if Date().timeIntervalSince(lastLoadedAt) > Self.staleAfter {
      Task { await load() }
    }
  }

  func refresh() {
    Task { await load() }
  }

  /// Signed in again: load again, the channels alone while setup shows.
  func reconnected(items: Bool = true) {
    error = nil
    needsReconnect = false
    Task { await load(items: items) }
  }

  /// Put what `entries` holds for one item into `watched` and `bars`; says
  /// whether it is watched.
  @discardableResult
  private func readEntry(_ id: String, durationSeconds: Double) -> Bool {
    let entry = entries[id]
    let isWatchedNow = isWatched(entry, durationSeconds: durationSeconds)
    // only what differs is written: every write redraws the cards
    if isWatchedNow != watched.contains(id) {
      if isWatchedNow {
        watched.insert(id)
      } else {
        watched.remove(id)
      }
    }
    let bar = progressFraction(entry, durationSeconds: durationSeconds)
    if bars[id] != bar {
      bars[id] = bar
    }
    return isWatchedNow
  }

  /// Read the synced watched state of a batch of items. An entry edited
  /// here while the store was asked keeps the edit.
  private func applyEntries(_ batch: [FeedItem]) async {
    let asked = editSerial
    let ids = batch.map(\.id)
    let stored = offline ? entries : await read { await $0.watchedEntries(ids) }
    for item in batch {
      if (editedAt[item.id] ?? 0) <= asked {
        entries[item.id] = stored[item.id]
      }
      readEntry(item.id, durationSeconds: Double(item.durationSeconds))
    }
  }

  private func edit(_ id: String, _ change: (WatchedEntry?, Int64) -> WatchedEntry) {
    editSerial += 1
    editedAt[id] = editSerial
    entries[id] = change(entries[id], epochMilliseconds())
  }

  /// Show an item's entry as just saved; one that changed sides stays on
  /// screen.
  private func entryChanged(_ id: String, durationSeconds: Double) {
    let wasWatched = watched.contains(id)
    if readEntry(id, durationSeconds: durationSeconds) != wasWatched {
      staying.insert(id)
      rebuild()
    }
  }

  /// The length of a loaded video, in seconds; 0 when it isn't loaded or has
  /// none.
  private func length(of id: String) -> Double {
    Double(items[id]?.durationSeconds ?? 0)
  }

  /// Load everything: channels, filters, watched marks and every enabled
  /// channel's items.
  func load() async {
    await load(items: true)
  }

  /// Load the channels and their filters only, for the first run before it
  /// knows which channels stay on.
  func loadChannels() async {
    await load(items: false)
  }

  /// Fetch the items of the channels that are on, and of no others, ahead of
  /// the first full load. What an earlier call fetched or is fetching for a
  /// channel still on is kept, with the Shorts list added when its filter
  /// has come to need it.
  func prefetchEnabled() {
    guard !offline else { return }
    let prefetch =
      setupPrefetch
      ?? Prefetch(
        fetchAll: { [weak self] channel in
          guard let self else { throw CancellationError() }
          return try await self.fetchItems(channel)
        },
        addShorts: { [weak self] channel, have in
          guard let self else { throw CancellationError() }
          return try await self.addShorts(channel, have)
        })
    setupPrefetch = prefetch
    let wanted = channels.filter(\.enabled)
    prefetchCall = Task { [earlier = prefetchCall] in
      await earlier?.value
      await prefetch.fetchOnly(wanted)
    }
  }

  /// Load now, or once the load that is running ends: a full load asked for
  /// while setup's channels-only one runs must not be lost.
  private func load(items wantsItems: Bool) async {
    appLog.notice("load asked items=\(wantsItems) loading=\(self.loading) offline=\(self.offline)")
    guard !offline else { return }
    if loading {
      loadAskedMeanwhile = max(loadAskedMeanwhile ?? .channels, wantsItems ? .items : .channels)
    } else {
      await loadNow(items: wantsItems)
      let next = loadAskedMeanwhile
      loadAskedMeanwhile = nil
      // one that asked for no more than the load just made is already answered
      if next == .items, !wantsItems {
        // in a task of its own: this one may be a view's, called off when the view left
        Task { await self.load(items: true) }
      }
    }
  }

  private func loadNow(items wantsItems: Bool) async {
    loading = true
    loadProgress = wantsItems ? loadFraction(finished: 0, total: nil) : nil
    error = nil
    needsReconnect = false
    defer {
      loading = false
      loadProgress = nil
      editsDuringLoad = [:]
    }
    let sink = FeedLoadSink(
      channels: { [weak self] loaded in await self?.receiveChannels(loaded) },
      progress: { [weak self] finished, total in
        await self?.receiveProgress(finished: finished, total: total)
      })
    let prefetched = wantsItems ? setupPrefetch : nil
    if wantsItems {
      setupPrefetch = nil
      await prefetchCall?.value
      prefetchCall = nil
    }
    do {
      let result = try await loadFeed(
        tokens: auth, store: store, probe: probe.function, sink: sink, items: wantsItems,
        prefetched: prefetched, known: wantsItems ? heldDetails() : [:])
      let fresh = result.fetched.values.flatMap(\.items)
      appLog.notice(
        "loaded items=\(wantsItems) channels=\(result.channels.count) on=\(result.channels.filter(\.enabled).count) fetched=\(result.fetched.count) failed=\(result.failed.count) videos=\(fresh.count) limit=\(result.dailyLimit)"
      )
      let settingsAsked = settingEdits
      let synced = await read { await $0.settings() }
      if settingEdits == settingsAsked {
        settings = synced
      }
      savedFilters = await read { await $0.savedFilters() }
      await applyEntries(fresh)
      subscribedIds = Set(result.subscriptions.map(\.channelId))
      channels = keepingEdits(result.channels, edits: editsDuringLoad)
      if wantsItems {
        // what the load didn't fetch (channels off, failed or added meanwhile) stays
        var kept = items.filter { result.fetched[$0.value.channelId] == nil }
        for item in fresh {
          kept[item.id] = item
        }
        items = kept
        publishedTimes = [:]
        for (channelId, got) in result.fetched {
          fetched[channelId] = nil
          markFetched(channelId, got)
        }
        for channelId in result.failed {
          // so an edit to it fetches it again
          fetched[channelId] = nil
        }
        if result.dailyLimit {
          notice = Strings.dailyLimit
        } else {
          notice = result.failed.isEmpty ? nil : Strings.partialLoad
        }
        shuffleSeed = newShuffleSeed()
        chipClock = epochMilliseconds()
        markBeforeStart(Set(result.fetched.keys), fresh)
        let loadedIds = fresh.map(\.id)
        write { await $0.noteLoaded(loadedIds) }
        staying = []
      }
      rebuild()
      if wantsItems {
        fullLoadShown = true
        reorderChannels()
      }
      await refreshSyncTime()
      if wantsItems, !result.dailyLimit, let selectedChannel, isOnDemand(selectedChannel) {
        // the page of a channel that is off isn't part of the load
        try? await fetchChannel(selectedChannel, again: true)
      }
      channelsLoaded = true
      if wantsItems {
        lastLoadedAt = Date()
      }
    } catch SyncError.profileDeleted {
      appLog.notice("load ended: profile deleted elsewhere")
      onProfileDeleted?()
    } catch {
      if isCancellation(error) {
        appLog.notice("load called off")
      }
      fail(error)
    }
    let waiting = fetchAfterLoad
    fetchAfterLoad = []
    for channelId in waiting {
      fetchIfMissing(channelId)
    }
  }

  /// After setup, mark what these channels, each fetched whole, have from
  /// before its starting point watched, as one edit; a channel that was on
  /// then and isn't among them keeps waiting for its first fetch.
  private func markBeforeStart(_ fetched: Set<String>, _ fetchedItems: [FeedItem]) {
    guard let pending = pendingStart(accountId: account.channelId) else { return }
    let (marks, remaining) = applyPendingStart(pending, fetched: fetched, items: fetchedItems)
    if remaining != pending {
      keepPendingStart(accountId: account.channelId, remaining)
    }
    let ids = marks.filter { entries[$0]?.watched != true }
    if !ids.isEmpty {
      for id in ids {
        edit(id) { prior, at in markedEntry(prior, now: at, watched: true) }
        readEntry(id, durationSeconds: length(of: id))
      }
      write { await $0.setWatched(ids, watched: true) }
    }
  }

  private func receiveChannels(_ loaded: [ChannelFilter]) {
    channels = keepingEdits(loaded, edits: editsDuringLoad)
    // no rebuild follows here to do it
    holdChannels()
  }

  /// Move the load's bar on; reports arrive out of order, and from the start
  /// again when the load is retried, so it never moves back.
  private func receiveProgress(finished: Int, total: Int) {
    if let shown = loadProgress {
      loadProgress = max(shown, loadFraction(finished: finished, total: total))
    }
  }

  /// Show why a load failed; nothing for one that was called off.
  private func fail(_ caught: Error) {
    if let message = Strings.message(for: caught, signedOut: Strings.reconnectToLoad) {
      appLog.error("load failed: \(String(describing: caught), privacy: .public)")
      needsReconnect = Strings.signingInFixes(caught)
      error = message
    }
  }

  /// Run `work` with a valid token, renewing it once if Google refuses it.
  private func withToken<Result>(_ work: (String) async throws -> Result) async throws -> Result {
    do {
      return try await work(try await auth.validToken())
    } catch GoogleAPIError.tokenExpired {
      return try await work(try await auth.refreshedToken())
    }
  }

  /// The details of the held videos that YouTube needn't be asked for again,
  /// by video id; those of one channel, or of all.
  private func heldDetails(of channelId: String? = nil) -> [String: VideoDetails] {
    var details: [String: VideoDetails] = [:]
    let held = channelId.map(channelFetched) ?? Array(items.values)
    for case .video(let video) in held {
      details[video.videoId] = settledDetails(video)
    }
    return details
  }

  private func fetchItems(_ channel: ChannelFilter) async throws -> ChannelItems {
    let probe = probe.function
    let known = heldDetails(of: channel.channelId)
    return try await withToken { token in
      try await fetchChannelItems(
        channel, client: YouTubeClient(accessToken: token), probe: probe, known: known)
    }
  }

  private func addShorts(_ channel: ChannelFilter, _ have: ChannelItems) async throws
    -> ChannelItems
  {
    let probe = probe.function
    return try await withToken { token in
      try await addShortsMarks(
        channelId: channel.channelId, to: have, client: YouTubeClient(accessToken: token),
        probe: probe)
    }
  }

  private func loadChannel(_ channelId: String) async {
    do {
      try await fetchChannel(channelId)
    } catch {
      if case GoogleAPIError.dailyLimit = error {
        // every waiting channel would be refused too
        refusals += 1
        fetchAfterLoad = []
      }
      fail(error)
    }
  }

  /// Run `work` when one of the fetch slots is free.
  private func withFetchSlot<Result>(_ work: () async throws -> Result) async rethrows -> Result {
    if activeFetches < fetchConcurrency {
      activeFetches += 1
    } else {
      // the slot is handed over by whoever finishes
      await withCheckedContinuation { fetchWaiters.append($0) }
    }
    defer {
      if fetchWaiters.isEmpty {
        activeFetches -= 1
      } else {
        fetchWaiters.removeFirst().resume()
      }
    }
    return try await work()
  }

  private func markFetched(_ channelId: String, _ got: ChannelItems) {
    var marks = fetched[channelId] ?? []
    switch got.mode {
    case .playlists:
      marks.insert(.playlists)
    case .videos:
      marks.insert(.videos)
      if got.shorts {
        marks.insert(.shorts)
      } else {
        marks.remove(.shorts)
      }
    }
    fetched[channelId] = marks
  }

  /// Whether a filter needs something not fetched for its channel: its
  /// mode's items, or the Shorts list.
  private func isMissing(_ filter: ChannelFilter) -> Bool {
    let marks = fetched[filter.channelId] ?? []
    return !marks.contains(filter.contentMode == .playlists ? .playlists : .videos)
      || (needsShorts(filter) && !marks.contains(.shorts))
  }

  /// The uploads held for a channel, as fetched; nil when it has none.
  private func fetchedUploads(_ channelId: String) -> ChannelItems? {
    if let marks = fetched[channelId], marks.contains(.videos) {
      return ChannelItems(
        mode: .videos, shorts: marks.contains(.shorts),
        items: items.values.filter { item in
          if case .video = item { item.channelId == channelId } else { false }
        })
    } else {
      return nil
    }
  }

  /// Fetch what a channel's filter lacks, unless it's on its way: nothing,
  /// only the Shorts list, or its items; `again` fetches the items even so.
  private func fetchChannel(_ channelId: String, again: Bool = false) async throws {
    guard !offline else { return }
    let target =
      channel(channelId) ?? ChannelFilter(channelId: channelId, title: channelId, thumbnail: "")
    let kind = ChannelKind(channelId: channelId, mode: target.contentMode)
    guard again || isMissing(target), !fetching.contains(kind) else { return }
    fetching.insert(kind)
    defer { fetching.remove(kind) }
    let refusalsBefore = refusals
    let got: ChannelItems? = try await withFetchSlot {
      if refusals != refusalsBefore {
        return nil
      } else {
        return try await completeItems(
          target, have: again ? nil : fetchedUploads(channelId),
          fetchAll: { [weak self] channel in
            guard let self else { throw CancellationError() }
            return try await self.fetchItems(channel)
          },
          addShorts: { [weak self] channel, have in
            guard let self else { throw CancellationError() }
            return try await self.addShorts(channel, have)
          })
      }
    }
    guard let got else { return }
    await applyEntries(got.items)
    markBeforeStart([channelId], got.items)
    let fresh = Set(got.items.map(\.id))
    for (id, item) in items where item.channelId == channelId && !fresh.contains(id) {
      let sameKind: Bool
      switch item {
      case .video: sameKind = got.mode == .videos
      case .playlist: sameKind = got.mode == .playlists
      }
      if sameKind {
        items[id] = nil
      }
    }
    for item in got.items {
      items[item.id] = item
    }
    markFetched(channelId, got)
    rebuild()
    // the filter may have come to need more while this ran
    fetchIfMissing(channelId)
  }

  /// Fetch a channel that is shown but lacks something its filter needs;
  /// while a load runs, once it ends.
  private func fetchIfMissing(_ channelId: String) {
    guard let filter = channel(channelId), filter.enabled || selectedChannel == channelId,
      isMissing(filter)
    else { return }
    if loading {
      fetchAfterLoad.insert(channelId)
    } else {
      Task { await loadChannel(channelId) }
    }
  }

  func updateFilter(_ filter: ChannelFilter) {
    guard let index = channels.firstIndex(where: { $0.channelId == filter.channelId }) else {
      return
    }
    channels[index] = filter
    if loading {
      editsDuringLoad[filter.channelId] = filter
    }
    write { await $0.setFilter(filter) }
    staying = []
    rebuild()
    fetchIfMissing(filter.channelId)
  }

  /// Save several filters as one edit, fetching nothing; the first run
  /// fetches through ``prefetchEnabled()``.
  func saveFilters(_ filters: [ChannelFilter]) {
    guard !filters.isEmpty else { return }
    let edited = Dictionary(filters.map { ($0.channelId, $0) }) { _, last in last }
    channels = keepingEdits(channels, edits: edited)
    if loading {
      editsDuringLoad.merge(edited) { _, new in new }
    }
    write { await $0.setFilters(filters) }
    staying = []
    rebuild()
  }

  private func saveSetting(_ name: SettingName, _ value: JSONValue) {
    settingEdits += 1
    chipClock = epochMilliseconds()
    write { await $0.setSetting(name, value: value) }
    rebuild()
  }

  /// Order the feed, here at once and on every device through Drive.
  func setFeedSort(_ sort: FeedSort) {
    settings.feedSort = sort
    saveSetting(.feedSort, .string(sort.rawValue))
  }

  /// Put the random order in another random order.
  func reshuffle() {
    shuffleSeed = newShuffleSeed()
    rebuild()
  }

  /// Order the channel lists.
  func setChannelSort(_ sort: ChannelSort) {
    settings.channelSort = sort
    saveSetting(.channelSort, .string(sort.rawValue))
    reorderChannels()
  }

  /// Turn auto-play on or off.
  func setAutoplay(_ isOn: Bool) {
    settings.autoplay = isOn
    saveSetting(.autoplay, .bool(isOn))
  }

  /// Choose how far back the feed reaches.
  func setTimeChip(_ timeChip: TimeChip) {
    settings.timeChip = timeChip
    staying = []
    saveSetting(.timeChip, .string(timeChip.rawValue))
  }

  /// `selected` with a category id or a group's name taken out, or added at
  /// the end; names are told apart by code point.
  private func toggled(_ chip: String, in selected: [String]) -> [String] {
    if selected.contains(where: { sameScalars($0, chip) }) {
      return selected.filter { !sameScalars($0, chip) }
    } else {
      return selected + [chip]
    }
  }

  private func setTopicChips(_ categoryIds: [String]) {
    settings.topicChips = categoryIds
    staying = []
    saveSetting(.topicChips, .array(categoryIds.map(JSONValue.string)))
  }

  /// Select a topic chip by its category id, or deselect it.
  func toggleTopicChip(_ categoryId: String) {
    setTopicChips(toggled(categoryId, in: settings.topicChips))
  }


  /// Select one of the feed's group chips by its name, or deselect it.
  func toggleGroupChip(_ group: String) {
    settings.groupChips = toggled(group, in: settings.groupChips)
    staying = []
    saveSetting(.groupChips, .array(settings.groupChips.map(JSONValue.string)))
  }

  /// The title's "Clear" on the feed or a channel's page: deselect the
  /// page's topic chips and, on the feed, its group chips.
  func clearFeedChips() {
    if selectedChannel == nil && !settings.groupChips.isEmpty {
      settings.groupChips = []
      staying = []
      saveSetting(.groupChips, .array([]))
    }
    if !settings.topicChips.isEmpty {
      setTopicChips([])
    }
  }

  /// Choose how far back the channel lists reach.
  func setChannelTimeChip(_ timeChip: TimeChip) {
    settings.channelTimeChip = timeChip
    saveSetting(.channelTimeChip, .string(timeChip.rawValue))
    reorderChannels()
  }

  private func setChannelTopicChips(_ categoryIds: [String]) {
    settings.channelTopicChips = categoryIds
    saveSetting(.channelTopicChips, .array(categoryIds.map(JSONValue.string)))
    reorderChannels()
  }

  /// Select one of the channel lists' topic chips by its category id, or
  /// deselect it.
  func toggleChannelTopicChip(_ categoryId: String) {
    setChannelTopicChips(toggled(categoryId, in: settings.channelTopicChips))
  }

  /// Select one of the channel lists' group chips by its name, or deselect
  /// it.
  func toggleChannelGroupChip(_ group: String) {
    settings.channelGroupChips = toggled(group, in: settings.channelGroupChips)
    saveSetting(.channelGroupChips, .array(settings.channelGroupChips.map(JSONValue.string)))
    reorderChannels()
  }

  /// The channel lists' title's "Clear": deselect their group and topic
  /// chips.
  func clearChannelChips() {
    if !settings.channelGroupChips.isEmpty {
      settings.channelGroupChips = []
      saveSetting(.channelGroupChips, .array([]))
      reorderChannels()
    }
    if !settings.channelTopicChips.isEmpty {
      setChannelTopicChips([])
    }
  }

  /// The listed channels in a group, by id.
  func members(of group: String) -> Set<String> {
    Set(channels.filter { channel in channel.groups.contains { sameScalars($0, group) } }
      .map(\.channelId))
  }

  /// Every saved filter by channel id: the listed channels' as they are
  /// here, the others' as last loaded.
  private func everySavedFilter() -> [String: JSONObject] {
    savedFilters.merging(channels.map { ($0.channelId, $0.storedFilter) }) { _, listed in listed }
  }

  private var groupSelections: GroupSelections {
    GroupSelections(
      groupChips: settings.groupChips, channelGroupChips: settings.channelGroupChips)
  }

  /// The feed's selected groups that exist, which is what its group chips filter by.
  private var feedGroups: [String] {
    selectedGroups(groups, selected: settings.groupChips)
  }

  /// Show a group edit here at once and save it as one edit. A card marked
  /// while on screen leaves only if the feed's selected groups change.
  private func apply(_ edit: GroupEdit) {
    guard !edit.isEmpty else { return }
    let selectedBefore = feedGroups
    savedFilters.merge(edit.channels) { _, edited in edited }
    let edited = groupEdited(channels, by: edit)
    if !edited.isEmpty {
      channels = keepingEdits(channels, edits: edited)
      if loading {
        editsDuringLoad.merge(edited) { _, new in new }
      }
    }
    if let groupChips = edit.groupChips {
      settings.groupChips = groupChips
    }
    if let channelGroupChips = edit.channelGroupChips {
      settings.channelGroupChips = channelGroupChips
    }
    settingEdits += 1
    write { await $0.applyGroupEdit(edit) }
    if !feedGroups.elementsEqual(selectedBefore, by: sameScalars) {
      staying = []
    }
    rebuild()
  }

  /// The group editor's "Save": `members`, listed channels' ids, become the
  /// group's channels and it takes `name`; `group` is nil for a new one.
  func saveGroup(_ group: String?, name: String, members: [String]) {
    apply(
      SubtubeCore.saveGroup(
        everySavedFilter(), listed: channels.map(\.channelId), selections: groupSelections,
        group: group, name: name, members: members))
  }

  /// Delete a group; its channels stay.
  func deleteGroup(_ group: String) {
    apply(SubtubeCore.deleteGroup(everySavedFilter(), selections: groupSelections, group: group))
  }

  /// List unwatched items, watched ones, or both.
  func setWatchedMode(_ mode: WatchedMode) {
    watchedMode = mode
    staying = []
    rebuild()
  }

  /// Mark a video or playlist watched, keeping a video's position, or
  /// unmark it, forgetting the position.
  func setWatched(_ id: String, watched isWatched: Bool) {
    edit(id) { prior, at in markedEntry(prior, now: at, watched: isWatched) }
    write { await $0.setWatched([id], watched: isWatched) }
    entryChanged(id, durationSeconds: length(of: id))
  }

  /// Mark a video or playlist watched, keeping a video's position.
  func markWatched(_ id: String) {
    setWatched(id, watched: true)
  }

  /// A press on a card's progress bar: watched becomes unwatched, anything
  /// else watched. The card stays where it is until the list is next built.
  func toggleWatched(_ id: String) {
    setWatched(id, watched: !watched.contains(id))
  }

  /// Save how far a video has been played: `position` of `playerDuration`
  /// seconds, and whether the player reported the end. It is always kept on
  /// this device; `upload` says when Drive gets it.
  func recordProgress(
    _ id: String, position: Double, playerDuration: Double, ended: Bool, upload: ProgressUpload
  ) {
    let whole = position.isFinite ? max(0, Int(position.rounded(.down))) : 0
    edit(id) { prior, at in playedEntry(prior, now: at, position: whole, ended: ended) }
    write { store in
      await store.setProgress(id, position: whole, ended: ended, upload: upload != .later)
      if upload == .now {
        // started, not waited for: the queue must not stand behind an upload
        _ = await store.startFlush()
      }
    }
    let known = length(of: id)
    entryChanged(id, durationSeconds: known > 0 ? known : playerDuration)
  }

  /// Where a video starts when opened, in seconds.
  func resumeAt(_ id: String) -> Double {
    resumePosition(entries[id], durationSeconds: length(of: id))
  }

  private func play(_ item: FeedItem, place: PlayerPlace, page: String?, queue: PlayQueue) {
    player = PlayerSession(
      item, feed: self, startAt: resumeAt(item.id), place: place, startedOn: page, queue: queue)
  }

  /// Play a card, on a Mac over the dimmed window and on a phone in the
  /// card; whatever was playing stops and saves its position. The page's
  /// list and watched chip are kept as they are now for what plays next.
  func open(_ item: FeedItem) {
    #if os(macOS)
      let place = PlayerPlace.large
    #else
      let place = PlayerPlace.card
    #endif
    play(
      item, place: place, page: selectedChannel,
      queue: PlayQueue(items: shown, mode: watchedMode))
    playStarts += 1
    if place == .card {
      // a card pressed while under half of it shows is scrolled into view and plays there
      cardScrolls += 1
    }
  }

  /// Move the player to the window's corner, still playing.
  func minimize() {
    player?.place = .minimized
  }

  /// Minimize a player that is in a card.
  func minimizeCard() {
    if player?.place == .card {
      minimize()
    }
  }

  /// Draw a minimized player over the dimmed window again.
  func enlarge() {
    player?.place = .large
  }

  /// Whether the page the minimized player was started on still lists its
  /// item, whatever page shows now: only then can it go back in its card.
  var cardIsListed: Bool {
    if let player, player.place == .minimized {
      listed(on: player.startedOn, feedPassing: feedPassing()).kept
        .contains { $0.id == player.item.id }
    } else {
      false
    }
  }

  /// Put a minimized player back in its card and scroll that into view, when
  /// the page it was started on is showing and still lists it; it stays
  /// minimized otherwise.
  func expandToCard() {
    if let player, player.place == .minimized, player.startedOn == selectedChannel,
      shown.contains(where: { $0.id == player.item.id })
    {
      player.place = .card
      cardScrolls += 1
    }
  }

  /// Stop playing, saving the position, and remove the player.
  func closePlayer() {
    player = nil
  }

  /// The playing item is over: the next unwatched item of the list it was
  /// started from plays where the player is, or minimized when that is a
  /// card not on the page showing. With nothing next the large player stays
  /// and any other closes (shared/fixtures/player.json).
  func playbackEnded(_ session: PlayerSession) {
    guard player === session else { return }
    let next = nextInQueue(
      session.queue, after: session.item.id, watched: watched, autoplay: settings.autoplay)
    let nextCardShowing = next.map { item in shown.contains { $0.id == item.id } } ?? false
    switch endOutcome(
      place: session.place, hasNext: next != nil, nextCardShowing: nextCardShowing)
    {
    case .next(let place):
      if let next {
        play(next, place: place, page: session.startedOn, queue: session.queue)
        if place == .card {
          cardScrolls += 1
        }
      }
    case .stay:
      break
    case .close:
      player = nil
    }
  }

  /// Ask Google for the account's name and address, once.
  func loadUser() async {
    guard user == nil else { return }
    user = try? await withToken { token in try await DriveClient(accessToken: token).about() }
  }

  func refreshSyncTime() async {
    lastSyncedAt = await store.lastSyncedAt
  }

  /// Delete the profile from Drive, every device's files, and from this
  /// device.
  func deleteProfile() async throws {
    try await store.deleteProfile()
  }

  /// Upload edits still waiting out the pause.
  func flush() async {
    guard !offline else { return }
    // the queue only starts the upload, so nothing asked later waits behind it
    let upload = await read { await $0.startFlush() }
    _ = try? await upload?.value
  }

  /// The app is leaving the foreground: save what is playing and upload.
  func leftForeground() async {
    player?.save(upload: .now)
    await flush()
  }

  /// The app is quitting: have the playing position on disk before this
  /// returns, waiting no more than a second for it.
  func quitting() {
    guard !offline else { return }
    player?.save(upload: .later)
    let written = DispatchSemaphore(value: 0)
    write { store in
      await store.persist()
      written.signal()
    }
    // the store's queue runs off the main thread, so waiting here doesn't hold it up
    _ = written.wait(timeout: .now() + .seconds(1))
  }
}

/// The fetched items by channel, with each channel's newest `publishedAt`.
private struct ItemIndex {
  var byChannel: [String: [FeedItem]] = [:]
  var newest: [String: String] = [:]
}

/// One channel's items of one kind.
private struct ChannelKind: Hashable {
  let channelId: String
  let mode: ContentMode
}

/// What a channel's items have been fetched as.
private enum FetchMark {
  case videos
  case playlists
  /// The Shorts list was read for the uploads.
  case shorts
}

#if DEBUG
  extension FeedModel {
    /// The mockups' placeholder feed, for looking at the screens without a
    /// Google sign-in (launch with `-demo`). Nothing loads or syncs.
    static func demo(auth: GoogleAuth) -> FeedModel {
      let feed = FeedModel(
        account: ChannelSummary(channelId: "UCdemo", title: "Your Name", thumbnail: ""), auth: auth)
      feed.offline = true
      feed.channelsLoaded = true
      let names = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
      feed.channels = names.map { name in
        var channel = ChannelFilter(
          channelId: "UC\(name)", title: "Channel \(name)", thumbnail: "")
        switch name {
        case "One":
          channel.regex = phrasesToPattern(["Episode", "Q&A"])
          channel.topics = ["26"]
        case "Two": channel.shortsFilter = .normal
        case "Four": channel.contentMode = .playlists
        case "Five": channel.minDurationSeconds = 60
        case "Six": channel.liveFilter = .normal
        case "Seven": channel.enabled = false
        case "Eight": channel.followed = true
        default: break
        }
        return channel
      }
      feed.subscribedIds = Set(names.filter { $0 != "Eight" }.map { "UC\($0)" })
      // title, channel, seconds (or a playlist's video count), day counted
      // from 1 September 2026, watched, kind, category id, seconds played;
      // the same entries as Android's demo, so screenshots compare
      let rows: [(String, String, Int, Int, Bool, String, String, Int)] = [
        ("Woodworking Basics — Episode 12", "One", 1122, 24, true, "", "26", 0),
        ("Weekly Q&A, September (replay)", "Two", 3735, 25, true, "", "26", 0),
        ("Building a Shop Cart", "Three", 1450, 26, false, "", "26", 1100),
        ("Woodworking Basics — Episode 13", "One", 1267, 27, false, "", "26", 0),
        ("Garden Projects 2026", "Four", 14, 28, false, "playlist", "", 0),
        ("Sharpening Without a Jig", "Five", 598, 29, false, "", "27", 0),
        ("Quick tip: clamping odd shapes", "Two", 48, 30, false, "short", "26", 0),
        ("Kitchen Remodel, Part 4", "Six", 1964, 31, false, "", "26", 0),
        ("Trip Notes: Lake Day", "Three", 920, 32, false, "", "19", 0),
        ("Woodworking Basics — Episode 14", "One", 1195, 33, false, "", "26", 420),
        ("Tool Review: Block Planes", "Five", 1651, 34, false, "", "28", 200),
        ("Night Sky, October", "Seven", 668, 35, false, "", "28", 0),
        ("Shop update and Q&A", "One", 4360, 20, false, "", "26", 0),
      ]
      for (index, row) in rows.enumerated() {
        let (title, channel, seconds, day, watched, kind, category, played) = row
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day))!
        let publishedAt = date.formatted(.iso8601)
        let id = "demo\(index)"
        let item: FeedItem
        if kind == "playlist" {
          item = .playlist(
            Playlist(
              playlistId: id, channelId: "UC\(channel)", channelTitle: "Channel \(channel)",
              title: title, description: "", publishedAt: publishedAt, thumbnail: "",
              itemCount: seconds))
        } else {
          item = .video(
            Video(
              videoId: id, channelId: "UC\(channel)", channelTitle: "Channel \(channel)",
              title: title, description: "", publishedAt: publishedAt, thumbnail: "",
              durationSeconds: seconds, liveStatus: .normal, isShort: kind == "short",
              categoryId: category))
        }
        feed.items[id] = item
        if watched {
          feed.entries[id] = WatchedEntry(at: 0, watched: true)
        } else if played > 0 {
          feed.entries[id] = playedEntry(nil, now: 0, position: played, ended: false)
        }
        feed.readEntry(id, durationSeconds: Double(item.durationSeconds))
      }
      if CommandLine.arguments.contains("-watched") {
        feed.watchedMode = .watched
      }
      for channel in feed.channels {
        feed.fetched[channel.channelId] =
          channel.contentMode == .playlists ? [.playlists] : [.videos, .shorts]
      }
      if CommandLine.arguments.contains("-empty") {
        feed.items = [:]
      }
      if let span = debugArgument("channelTime").flatMap(TimeChip.init(rawValue:)) {
        feed.settings.channelTimeChip = span
      }
      if let topics = debugArgument("channelTopics") {
        feed.settings.channelTopicChips = topics.split(separator: ",").map(String.init)
      }
      if let topics = debugArgument("topics") {
        feed.settings.topicChips = topics.split(separator: ",").map(String.init)
      }
      if CommandLine.arguments.contains("-groups") {
        let demoGroups = [
          "Woodworking": ["One", "Three", "Five"], "Home": ["Six", "Four"],
          "Talks": ["Two", "Seven"],
        ]
        feed.channels = feed.channels.map { channel in
          var grouped = channel
          grouped.groups = demoGroups.filter { _, names in
            names.contains(String(channel.channelId.dropFirst(2)))
          }.keys.sorted()
          return grouped
        }
      }
      if let names = debugArgument("groupChips") {
        feed.settings.groupChips = names.split(separator: ",").map(String.init)
      }
      if let names = debugArgument("channelGroupChips") {
        feed.settings.channelGroupChips = names.split(separator: ",").map(String.init)
      }
      feed.rebuild()
      if let index = debugArgument("toggleWatched").flatMap(Int.init),
        feed.shown.indices.contains(index)
      {
        feed.toggleWatched(feed.shown[index].id)
      }
      feed.fullLoadShown = true
      feed.reorderChannels()
      feed.loading = CommandLine.arguments.contains("-loading")
      if feed.loading {
        feed.loadProgress = loadFraction(finished: 3, total: feed.channels.count)
      }
      return feed
    }

    /// Open the player on the demo feed's first unwatched video; with
    /// `videoId` that card plays the real video of that id.
    func demoPlay(videoId: String? = nil) {
      let unwatched = shown.filter { !watched.contains($0.id) }
      if let videoId, let card = unwatched.first(where: { $0.durationSeconds > 60 }),
        case .video(var video) = card
      {
        items[card.id] = nil
        entries[card.id] = nil
        video.videoId = videoId
        items[videoId] = .video(video)
        rebuild()
        open(.video(video))
      } else if let first = unwatched.first {
        open(first)
      }
      if CommandLine.arguments.contains("-minimized") {
        minimize()
      }
      if CommandLine.arguments.contains("-playerFrame") {
        player?.showsFrame = true
      }
      if let seconds = debugArgument("minimizeAfter").flatMap(Double.init) {
        Task {
          try? await Task.sleep(for: .seconds(seconds))
          minimize()
        }
      }
    }
  }

  /// The value of a `-name:value` launch argument. Values ride in the same
  /// argument because macOS opens any bare argument as a file, which keeps
  /// the main window from opening.
  func debugArgument(_ name: String) -> String? {
    CommandLine.arguments.first { $0.hasPrefix("-\(name):") }.map {
      String($0.dropFirst(name.count + 2))
    }
  }
#endif
