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

  /// The channels with their filters, in sidebar order; edits apply here at
  /// once and sync through Drive.
  private(set) var channels: [ChannelFilter] = [] {
    didSet {
      compiled = Dictionary(channels.map { ($0.channelId, compileFilter($0)) }) { first, _ in first }
      modes = Dictionary(channels.map { ($0.channelId, $0.contentMode) }) { first, _ in first }
      holdChannels()
    }
  }
  /// The channel lists' rows as last worked out; edits neither move nor
  /// remove them.
  private var heldOrder = HeldChannelOrder()
  private var compiled: [String: CompiledFilter] = [:]
  /// Whether each channel shows uploads or playlists.
  private var modes: [String: ContentMode] = [:]
  /// The channels the account subscribes to on YouTube.
  private(set) var subscribedIds = Set<String>()
  /// Every item fetched, for the feed or a channel page.
  private var items: [String: FeedItem] = [:]
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
  /// Whether a full load has been shown.
  private var fullLoadShown = false
  /// Each on channel's unwatched items that pass its filter, counted;
  /// channels with none are absent.
  private(set) var unwatchedByChannel: [String: Int] = [:]
  /// Became watched or unwatched here since the list was last rebuilt for
  /// good; these stay on screen whatever the watched chip lists.
  private var staying = Set<String>()

  /// The synced settings, as of the last load plus changes made here since.
  private(set) var settings = SyncedSettings()
  private var settingEdits = 0
  /// Which of watched and unwatched items the page lists; kept for the visit.
  private(set) var watchedMode = WatchedMode.unwatched
  /// Fixes the random order until the next full load.
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
  /// The Google account's name and address, once asked.
  private(set) var user: DriveUser?
  private(set) var lastSyncedAt: Date?
  private var lastLoadedAt = Date.distantPast
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
      mode: watchedMode, timeChip: settings.timeChip, topicChips: settings.topicChips)
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

  /// Whether a channel list that is empty says so: a full load has been
  /// shown and its time chip or a topic chip is chosen.
  var explainsNoChannels: Bool {
    fullLoadShown && chipChannels != nil
  }

  /// Work the channel lists' rows and order out again. A list asks when it
  /// appears and when its search changes; a full load and a change of a
  /// channel list chip do it themselves.
  func reorderChannels() {
    var order = heldOrder
    order.recompute(freshChannelOrder(), kept: chipChannels)
    if order != heldOrder {
      heldOrder = order
    }
  }

  /// Keep the channel lists' rows in place, adding channels kept since.
  private func holdChannels() {
    var order = heldOrder
    order.hold(freshChannelOrder(), kept: chipChannels)
    if order != heldOrder {
      heldOrder = order
    }
  }

  /// The channel ids in the order their sort gives them now.
  private func freshChannelOrder() -> [String] {
    var newest: [String: String] = [:]
    for item in items.values {
      if let known = newest[item.channelId],
        !known.utf8.lexicographicallyPrecedes(item.publishedAt.utf8)
      {
        continue
      }
      newest[item.channelId] = item.publishedAt
    }
    return channelOrder(
      channels.map { channel in
        ChannelOrderEntry(
          id: channel.channelId, title: channel.title, enabled: channel.enabled,
          newest: newest[channel.channelId],
          unwatched: unwatchedByChannel[channel.channelId] ?? 0)
      }, sort: settings.channelSort)
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
    items.values.filter { $0.channelId == channelId }
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

  /// Everything the current view could show, watched or not.
  private func passing() -> [FeedItem] {
    items.values.filter { item in
      guard selectedChannel == nil || item.channelId == selectedChannel, matchesMode(item)
      else { return false }
      let filter = compiled[item.channelId]
      if selectedChannel == nil && filter?.enabled != true {
        return false
      } else if let filter {
        return itemPassesFilter(item, filter)
      } else {
        return true
      }
    }
  }

  /// Work out what the page shows, both rows' topic chips, the unwatched
  /// counts and the channels the channel lists' chips keep.
  private func rebuild() {
    let beforeChips = modeFiltered(
      passing(), mode: watchedMode, watched: watched, staying: staying)
    topicChips = chipRow(beforeChips, selected: settings.topicChips)
    shown = sortFeed(
      chipFiltered(
        beforeChips, timeChip: settings.timeChip, topicChips: settings.topicChips, now: chipClock),
      by: settings.feedSort, seed: shuffleSeed)
    let listed = listedItems(items.values, filters: compiled, modes: modes)
    var counts: [String: Int] = [:]
    for item in listed where !watched.contains(item.id) {
      counts[item.channelId, default: 0] += 1
    }
    unwatchedByChannel = counts
    channelTopicChips = chipRow(listed, selected: settings.channelTopicChips)
    chipChannels = chipKeptChannels(
      listed, timeChip: settings.channelTimeChip, topicChips: settings.channelTopicChips,
      now: chipClock)
    holdChannels()
    #if os(iOS)
      // a card that left the list stops playing
      if let playing = player?.item.id, !shown.contains(where: { $0.id == playing }) {
        player = nil
      }
    #endif
  }

  private func viewChanged() {
    #if os(iOS)
      // a card plays in its list; another page is another list
      player = nil
    #endif
    rebuild()
    if let selectedChannel {
      fetchIfMissing(selectedChannel)
    }
  }

  /// The first load, and a load on returning after a while away.
  func appeared() {
    if Date().timeIntervalSince(lastLoadedAt) > Self.staleAfter {
      lastLoadedAt = Date()
      Task { await load() }
    }
  }

  func refresh() {
    Task { await load() }
  }

  func reconnected() {
    error = nil
    needsReconnect = false
    Task { await load() }
  }

  /// Put what `entries` holds for one item into `watched` and `bars`; says
  /// whether it is watched.
  @discardableResult
  private func readEntry(_ id: String, durationSeconds: Double) -> Bool {
    let entry = entries[id]
    let isWatchedNow = isWatched(entry, durationSeconds: durationSeconds)
    if isWatchedNow {
      watched.insert(id)
    } else {
      watched.remove(id)
    }
    bars[id] = progressFraction(entry, durationSeconds: durationSeconds)
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

  private func load(items wantsItems: Bool) async {
    guard !loading, !offline else { return }
    loading = true
    loadProgress = wantsItems ? loadFraction(finished: 0, total: nil) : nil
    error = nil
    defer {
      loading = false
      loadProgress = nil
      editsDuringLoad = [:]
      if wantsItems {
        lastLoadedAt = Date()
      }
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
        prefetched: prefetched)
      let fresh = result.fetched.values.flatMap(\.items)
      let settingsAsked = settingEdits
      let synced = await read { await $0.settings() }
      if settingEdits == settingsAsked {
        settings = synced
      }
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
        for (channelId, got) in result.fetched {
          fetched[channelId] = nil
          markFetched(channelId, got)
        }
        for channelId in result.failed {
          // so an edit to it fetches it again
          fetched[channelId] = nil
        }
        if result.dailyLimit {
          notice = GoogleAPIError.dailyLimit.localizedDescription
        } else {
          notice = result.failed.isEmpty ? nil : Strings.partialLoad
        }
        shuffleSeed = newShuffleSeed()
        chipClock = epochMilliseconds()
        markBeforeStart(fresh)
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
    } catch SyncError.profileDeleted {
      onProfileDeleted?()
    } catch {
      fail(error)
    }
    let waiting = fetchAfterLoad
    fetchAfterLoad = []
    for channelId in waiting {
      fetchIfMissing(channelId)
    }
  }

  /// After setup, mark what was fetched from before its starting point
  /// watched, as one edit.
  private func markBeforeStart(_ fresh: [FeedItem]) {
    let now = epochMilliseconds()
    let ids = startMarks(
      fresh, start: takePendingStart(accountId: account.channelId), now: now
    ).filter { entries[$0]?.watched != true }
    guard !ids.isEmpty else { return }
    for id in ids {
      edit(id) { prior, at in markedEntry(prior, now: at, watched: true) }
      readEntry(id, durationSeconds: length(of: id))
    }
    write { await $0.setWatched(ids, watched: true) }
  }

  private func receiveChannels(_ loaded: [ChannelFilter]) {
    channels = keepingEdits(loaded, edits: editsDuringLoad)
  }

  /// Move the load's bar on; reports arrive out of order, and from the start
  /// again when the load is retried, so it never moves back.
  private func receiveProgress(finished: Int, total: Int) {
    if let shown = loadProgress {
      loadProgress = max(shown, loadFraction(finished: finished, total: total))
    }
  }

  private func fail(_ caught: Error) {
    switch caught {
    case AuthError.signInRequired:
      needsReconnect = true
      error = Strings.reconnectToLoad
    case GoogleAPIError.tokenExpired:
      needsReconnect = true
      error = Strings.sessionEnded
    case GoogleAPIError.insufficientScope:
      needsReconnect = true
      error = Strings.needsPermissions
    default:
      error = caught.localizedDescription
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

  private func fetchItems(_ channel: ChannelFilter) async throws -> ChannelItems {
    let probe = probe.function
    return try await withToken { token in
      try await fetchChannelItems(channel, client: YouTubeClient(accessToken: token), probe: probe)
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
    guard let marks = fetched[channelId], marks.contains(.videos) else { return nil }
    return ChannelItems(
      mode: .videos, shorts: marks.contains(.shorts),
      items: items.values.filter { item in
        if case .video = item { item.channelId == channelId } else { false }
      })
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

  /// `selected` with a category id taken out, or added at the end.
  private func toggled(_ categoryId: String, in selected: [String]) -> [String] {
    if selected.contains(categoryId) {
      return selected.filter { $0 != categoryId }
    } else {
      return selected + [categoryId]
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

  /// Deselect every topic chip.
  func clearTopicChips() {
    setTopicChips([])
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

  /// Deselect every one of the channel lists' topic chips.
  func clearChannelTopicChips() {
    setChannelTopicChips([])
  }

  /// List unwatched items, watched ones, or both.
  func setWatchedMode(_ mode: WatchedMode) {
    watchedMode = mode
    staying = []
    rebuild()
  }

  /// Mark a video or playlist watched, keeping a video's position.
  func markWatched(_ id: String) {
    edit(id) { prior, at in markedEntry(prior, now: at, watched: true) }
    write { await $0.setWatched([id], watched: true) }
    entryChanged(id, durationSeconds: length(of: id))
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
        try? await store.flush()
      }
    }
    let known = length(of: id)
    entryChanged(id, durationSeconds: known > 0 ? known : playerDuration)
  }

  /// Where a video starts when opened, in seconds.
  func resumeAt(_ id: String) -> Double {
    resumePosition(entries[id], durationSeconds: length(of: id))
  }

  /// What auto-play plays after `endedId` on this page; nil when it doesn't
  /// move on.
  func autoplayNext(after endedId: String) -> FeedItem? {
    if settings.autoplay && autoplayAdvances(watchedMode) {
      nextUnwatched(shown, after: endedId, watched: watched)
    } else {
      nil
    }
  }

  /// Play a card; whatever was playing stops and saves its position.
  func open(_ item: FeedItem) {
    player = PlayerSession(item, feed: self, startAt: resumeAt(item.id))
  }

  /// The playing item is over: auto-play's next item takes its place.
  func playbackEnded(_ session: PlayerSession) {
    guard player === session else { return }
    if let next = autoplayNext(after: session.item.id) {
      open(next)
    } else {
      #if os(iOS)
        player = nil
      #endif
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
    do {
      try await store.deleteProfile()
    } catch GoogleAPIError.tokenExpired {
      _ = try await auth.refreshedToken()
      try await store.deleteProfile()
    }
  }

  /// Upload edits still waiting out the pause.
  func flush() async {
    guard !offline else { return }
    await read { _ = try? await $0.flush() }
  }

  /// The app is leaving the foreground: save what is playing and upload.
  func leftForeground() async {
    player?.save(upload: .now)
    await flush()
  }
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
      feed.watchedMode = CommandLine.arguments.contains("-unwatched") ? .unwatched : .all
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
      feed.rebuild()
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
