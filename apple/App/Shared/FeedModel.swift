import Foundation
import Observation
import SubtubeCore
import os

/// Errors kept out of the interface.
let appLog = Logger(subsystem: "cc.hafa.subtube", category: "app")

/// The feed for one account.
///
/// What is shown is every fetched item that passes the filters, newest first.
/// With watched hidden, a card marked watched stays, dimmed, until a full
/// load finishes, a filter is edited or Hide Watched is toggled; moving
/// between the feed and channel pages keeps it. While a load runs the
/// previous feed stays.
@MainActor @Observable
final class FeedModel {
  /// Returning to the app after this long away loads the feed again.
  private static let staleAfter: TimeInterval = 15 * 60
  /// How many of a channel's items a filter preview lists.
  private static let previewLength = 20

  let account: ChannelSummary
  private let auth: GoogleAuth
  private let store: SyncStore
  private let probe = ShortsProbe()

  /// The channels with their filters, in sidebar order; edits apply here at
  /// once and sync through Drive.
  private(set) var channels: [ChannelFilter] = [] {
    didSet {
      compiled = Dictionary(channels.map { ($0.channelId, compileFilter($0)) }) { first, _ in first }
    }
  }
  private var compiled: [String: CompiledFilter] = [:]
  /// The channels the account subscribes to on YouTube.
  private(set) var subscribedIds = Set<String>()
  /// Every item fetched, for the feed or a channel page.
  private var items: [String: FeedItem] = [:]
  /// The channels whose items in a kind are all in `items`.
  private var fetched = Set<ChannelKind>()
  private(set) var watched = Set<String>()
  /// The ids on screen, in the order shown.
  private(set) var order: [String] = []
  /// Marked watched since the list was last rebuilt for good; these stay on
  /// screen while watched is hidden.
  private var justWatched = Set<String>()

  /// The channel page shown, or nil for the whole feed.
  var selectedChannel: String? { didSet { viewChanged() } }
  var hideWatched = true {
    didSet {
      justWatched = []
      rebuild()
    }
  }

  /// The single-channel fetches running or waiting for a slot.
  private var fetching = Set<ChannelKind>()
  private var activeFetches = 0
  private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
  /// Filters edited while a load ran; the load's own copy is older.
  private var editsDuringLoad: [String: ChannelFilter] = [:]
  /// Channels to fetch once the running load ends.
  private var fetchAfterLoad = Set<String>()
  /// Whether a single channel is being fetched.
  var channelLoading: Bool { !fetching.isEmpty }
  /// Channels whose filter preview couldn't be fetched.
  private(set) var previewFailed: Set<String> = []

  private(set) var loading = false
  /// Whether a full load has finished since sign-in.
  private(set) var hasLoaded = false
  /// Whether the channels are known: a full or a channels-only load finished.
  private(set) var channelsLoaded = false
  /// The demo feed: nothing loads or syncs.
  private var offline = false
  private(set) var error: String?
  /// Whether only an interactive sign-in can fix `error`.
  private(set) var needsReconnect = false
  var notice: String?
  var player: PlayerSession?
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
    store = SyncStore(
      accountId: account.channelId, tokens: auth, directory: directory, deviceId: deviceId())
  }

  /// The items on screen, in order.
  var shown: [FeedItem] {
    let source = passing()
    return order.compactMap { source[$0] }
  }

  /// Unwatched items the whole feed would show.
  var unwatchedCount: Int {
    items.values.count { item in
      guard let filter = compiled[item.channelId], filter.enabled, matchesMode(item) else {
        return false
      }
      return !watched.contains(item.id) && itemPassesFilter(item, filter)
    }
  }

  /// The channels in the order every channel list shows them.
  var orderedChannels: [ChannelFilter] {
    var newest: [String: String] = [:]
    for item in items.values where matchesMode(item) {
      guard let filter = compiled[item.channelId], itemPassesFilter(item, filter) else { continue }
      if let known = newest[item.channelId],
        !known.utf8.lexicographicallyPrecedes(item.publishedAt.utf8)
      {
        continue
      }
      newest[item.channelId] = item.publishedAt
    }
    let ids = channelOrder(
      channels.map { channel in
        ChannelOrderEntry(
          id: channel.channelId, title: channel.title, enabled: channel.enabled,
          newestPassing: newest[channel.channelId])
      })
    let byId = Dictionary(channels.map { ($0.channelId, $0) }) { first, _ in first }
    return ids.compactMap { byId[$0] }
  }

  func channel(_ channelId: String) -> ChannelFilter? {
    channels.first { $0.channelId == channelId }
  }

  /// Whether the channel is shown because it was added in subtube.
  func isFollowedOnly(_ channelId: String) -> Bool {
    !subscribedIds.contains(channelId) && channel(channelId)?.followed == true
  }

  private func mode(_ channelId: String) -> ContentMode {
    channel(channelId)?.contentMode ?? .videos
  }

  /// Whether an item is the kind its channel currently shows.
  private func matchesMode(_ item: FeedItem) -> Bool {
    switch item {
    case .video: mode(item.channelId) == .videos
    case .playlist: mode(item.channelId) == .playlists
    }
  }

  private func isOnDemand(_ channelId: String) -> Bool {
    channel(channelId)?.enabled != true
  }

  /// Everything the current view could show, watched or not, by id.
  private func passing() -> [String: FeedItem] {
    let source: [FeedItem]
    if let selectedChannel {
      source = channelItems(selectedChannel) ?? []
    } else {
      source = Array(items.values)
    }
    var shown: [String: FeedItem] = [:]
    for item in source where matchesMode(item) {
      let filter = compiled[item.channelId]
      if selectedChannel == nil && filter?.enabled != true {
        continue
      }
      if let filter, !itemPassesFilter(item, filter) {
        continue
      }
      shown[item.id] = item
    }
    return shown
  }

  /// A channel's items of the kind it shows, or nil if they weren't fetched.
  private func channelItems(_ channelId: String) -> [FeedItem]? {
    guard fetched.contains(ChannelKind(channelId: channelId, mode: mode(channelId))) else {
      return nil
    }
    return items.values.filter { $0.channelId == channelId && matchesMode($0) }
  }

  /// Show what passes now, newest first.
  private func rebuild() {
    order = feedOrder(
      passing().values, watched: watched, hideWatched: hideWatched, justWatched: justWatched)
  }

  private func viewChanged() {
    rebuild()
    if let selectedChannel, isOnDemand(selectedChannel) {
      Task { await loadChannel(selectedChannel) }
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

  private func applyWatched(_ batch: [FeedItem]) async {
    let marked = await store.watchedAmong(batch.map(\.id))
    for item in batch {
      if marked.contains(item.id) {
        watched.insert(item.id)
      } else {
        watched.remove(item.id)
      }
    }
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

  private func load(items wantsItems: Bool) async {
    guard !loading, !offline else { return }
    loading = true
    error = nil
    defer {
      loading = false
      editsDuringLoad = [:]
      if wantsItems {
        lastLoadedAt = Date()
      }
    }
    let sink = FeedLoadSink(channels: { [weak self] loaded in await self?.receiveChannels(loaded) })
    do {
      let result = try await loadFeed(
        tokens: auth, store: store, probe: probe.function, sink: sink, items: wantsItems)
      await applyWatched(result.items)
      if wantsItems {
        let loadedIds = Set(result.fetched.map(\.channelId))
        // what the load didn't fetch (channels off, failed or added meanwhile) stays
        var kept = items.filter { !loadedIds.contains($0.value.channelId) }
        for item in result.items {
          kept[item.id] = item
        }
        items = kept
        fetched = fetched.filter { !loadedIds.contains($0.channelId) }
          .union(result.fetched.map { ChannelKind(channelId: $0.channelId, mode: $0.contentMode) })
        notice = result.failed.isEmpty ? nil : Strings.partialLoad
        justWatched = []
      }
      subscribedIds = Set(result.subscriptions.map(\.channelId))
      channels = keepingEdits(result.channels, edits: editsDuringLoad)
      rebuild()
      await refreshSyncTime()
      if wantsItems, let selectedChannel, isOnDemand(selectedChannel) {
        // the page of a channel that is off isn't part of the load
        try? await fetchChannel(selectedChannel, again: true)
      }
      channelsLoaded = true
    } catch SyncError.profileDeleted {
      onProfileDeleted?()
    } catch {
      fail(error)
    }
    if wantsItems {
      hasLoaded = true
    }
    let waiting = fetchAfterLoad
    fetchAfterLoad = []
    for channelId in waiting {
      Task { await loadChannel(channelId) }
    }
  }

  private func receiveChannels(_ loaded: [ChannelFilter]) {
    channels = keepingEdits(loaded, edits: editsDuringLoad)
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

  private func fetchItems(_ channel: ChannelFilter) async throws -> [FeedItem] {
    let probe = probe.function
    return try await withToken { token in
      try await fetchChannelItems(channel, client: YouTubeClient(accessToken: token), probe: probe)
    }
  }

  private func loadChannel(_ channelId: String) async {
    do {
      try await fetchChannel(channelId)
    } catch {
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

  /// Fetch one channel's items of the kind it shows, unless they're here or
  /// on their way; `again` fetches them even so.
  private func fetchChannel(_ channelId: String, again: Bool = false) async throws {
    guard !offline else { return }
    let target =
      channel(channelId) ?? ChannelFilter(channelId: channelId, title: channelId, thumbnail: "")
    let kind = ChannelKind(channelId: channelId, mode: target.contentMode)
    guard again || !fetched.contains(kind), !fetching.contains(kind) else { return }
    fetching.insert(kind)
    defer { fetching.remove(kind) }
    let batch = try await withFetchSlot { try await fetchItems(target) }
    await applyWatched(batch)
    let fresh = Set(batch.map(\.id))
    for (id, item) in items where item.channelId == channelId && !fresh.contains(id) {
      let sameKind: Bool
      switch item {
      case .video: sameKind = target.contentMode == .videos
      case .playlist: sameKind = target.contentMode == .playlists
      }
      if sameKind {
        items[id] = nil
      }
    }
    for item in batch {
      items[item.id] = item
    }
    fetched.insert(kind)
    rebuild()
  }

  /// Fetch a channel that is shown but whose items are missing; while a load
  /// runs, once it ends.
  private func fetchIfMissing(_ channelId: String) {
    guard let filter = channel(channelId), filter.enabled || selectedChannel == channelId,
      channelItems(channelId) == nil
    else { return }
    if loading {
      fetchAfterLoad.insert(channelId)
    } else {
      Task { await loadChannel(channelId) }
    }
  }

  /// A channel's newest items for a filter preview, newest first; nil until
  /// they're fetched with ``loadPreview(_:)``.
  func previewItems(_ channelId: String) -> [FeedItem]? {
    channelItems(channelId).map { Array($0.sorted(by: byNewest).prefix(Self.previewLength)) }
  }

  /// The channels the first run can try a filter on: on, uploads, and not
  /// keeping only what a pattern matches.
  var exampleCandidates: [ChannelFilter] {
    orderedChannels.filter { channel in
      channel.enabled && channel.contentMode == .videos
        && (channel.regex.isEmpty || channel.mode == .exclude)
    }
  }

  /// The first run's example channel: the candidate with the most Shorts
  /// among its fetched videos, then the one with the newest upload, then the
  /// lower channel id.
  func exampleChannel() -> String? {
    let ranked = exampleCandidates.map { channel in
      let fetched = channelItems(channel.channelId) ?? []
      let shorts = fetched.count {
        if case .video(let video) = $0 { video.isShort == true } else { false }
      }
      let newest = fetched.map(\.publishedAt).max() ?? ""
      return (channelId: channel.channelId, shorts: shorts, newest: newest)
    }
    let best = ranked.max { left, right in
      if left.shorts != right.shorts {
        return left.shorts < right.shorts
      } else if left.newest != right.newest {
        return left.newest.utf8.lexicographicallyPrecedes(right.newest.utf8)
      } else {
        return right.channelId.utf8.lexicographicallyPrecedes(left.channelId.utf8)
      }
    }
    return best?.channelId
  }

  /// Make sure ``previewItems(_:)`` has something for the channel.
  func loadPreview(_ channelId: String) async {
    guard previewItems(channelId) == nil else { return }
    previewFailed.remove(channelId)
    do {
      try await fetchChannel(channelId)
    } catch {
      appLog.error("filter preview failed: \(String(describing: error), privacy: .public)")
      previewFailed.insert(channelId)
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
    Task { await store.setFilter(filter) }
    justWatched = []
    rebuild()
    fetchIfMissing(filter.channelId)
  }

  /// Save several filters as one edit, fetching nothing; the first run
  /// follows it with a full load.
  func saveFilters(_ filters: [ChannelFilter]) {
    guard !filters.isEmpty else { return }
    let edited = Dictionary(filters.map { ($0.channelId, $0) }) { _, last in last }
    channels = keepingEdits(channels, edits: edited)
    if loading {
      editsDuringLoad.merge(edited) { _, new in new }
    }
    Task { await store.setFilters(filters) }
    justWatched = []
    rebuild()
  }

  func toggleWatched(_ item: FeedItem) {
    setWatched(item.id, !watched.contains(item.id))
  }

  /// The player marks each video as you leave it.
  func markWatched(_ id: String) {
    if !watched.contains(id) {
      setWatched(id, true)
    }
  }

  /// Take a watched mark off.
  func unmarkWatched(_ id: String) {
    if watched.contains(id) {
      setWatched(id, false)
    }
  }

  private func setWatched(_ id: String, _ isWatched: Bool) {
    if isWatched {
      watched.insert(id)
      justWatched.insert(id)
    } else {
      watched.remove(id)
    }
    Task { await store.setWatched(id, watched: isWatched) }
  }

  /// The cards the channel's page shows, or would show if it were open.
  private func shownFor(_ channelId: String) -> [FeedItem] {
    if selectedChannel == channelId {
      return shown
    } else {
      guard let filter = compiled[channelId] else { return [] }
      return (channelItems(channelId) ?? []).filter {
        itemPassesFilter($0, filter) && (!hideWatched || !watched.contains($0.id))
      }
    }
  }

  /// What the channel's "mark all" button would do now.
  func markAllChoice(_ channelId: String) -> MarkAll {
    markAll(shown: shownFor(channelId), watched: watched)
  }

  /// Mark the channel's shown cards watched, or unwatched when all of them
  /// already are. Like a single mark, the cards stay where they are.
  func applyMarkAll(_ channelId: String) {
    switch markAllChoice(channelId) {
    case .watched(let ids):
      watched.formUnion(ids)
      justWatched.formUnion(ids)
      Task { await store.setWatched(ids, watched: true) }
    case .unwatched(let ids):
      watched.subtract(ids)
      Task { await store.setWatched(ids, watched: false) }
    }
  }

  /// The item with this id, if the feed or a channel page has it.
  func item(_ id: String) -> FeedItem? {
    items[id]
  }

  func open(_ item: FeedItem) {
    player = PlayerSession(item, feed: self)
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
    try? await store.flush()
  }
}

/// One channel's items of one kind.
private struct ChannelKind: Hashable {
  let channelId: String
  let mode: ContentMode
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
          channel.regex = #"Episode \d+"#
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
      let rows: [(String, String, Int, Int, Bool, String)] = [
        ("Woodworking Basics — Episode 12", "One", 1122, 24, true, ""),
        ("Weekly Q&A, September (replay)", "Two", 3735, 25, true, ""),
        ("Building a Shop Cart", "Three", 1450, 26, false, ""),
        ("Woodworking Basics — Episode 13", "One", 1267, 27, false, ""),
        ("Garden Projects 2026", "Four", 14, 28, false, "playlist"),
        ("Sharpening Without a Jig", "Five", 598, 29, false, ""),
        ("Quick tip: clamping odd shapes", "Two", 48, 30, false, "short"),
        ("Kitchen Remodel, Part 4", "Six", 1964, 31, false, ""),
        ("Trip Notes: Lake Day", "Three", 920, 32, false, ""),
        ("Woodworking Basics — Episode 14", "One", 1195, 33, false, ""),
        ("Tool Review: Block Planes", "Five", 1651, 34, false, ""),
        ("Night Sky, October", "Seven", 668, 35, false, ""),
        ("Shop update and Q&A", "One", 4360, 20, false, ""),
      ]
      for (index, row) in rows.enumerated() {
        let (title, channel, seconds, day, watched, kind) = row
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
              durationSeconds: seconds, liveStatus: .normal, isShort: kind == "short"))
        }
        feed.items[id] = item
        if watched {
          feed.watched.insert(id)
        }
      }
      feed.hideWatched = false
      feed.fetched = Set(
        feed.channels.map { ChannelKind(channelId: $0.channelId, mode: $0.contentMode) })
      feed.hasLoaded = true
      if CommandLine.arguments.contains("-empty") {
        feed.items = [:]
      }
      feed.rebuild()
      feed.loading = CommandLine.arguments.contains("-loading")
      return feed
    }

    /// Open the player on the demo feed's first unwatched card.
    func demoPlay() {
      if let first = shown.first(where: { !watched.contains($0.id) }) {
        open(first)
      }
    }
  }
#endif
