import Foundation
import os

private let loaderLog = Logger(subsystem: "cc.hafa.subtube", category: "feed")

/// 50 is the Data API's most per playlistItems page, still 1 quota unit.
public let uploadsPerChannel = 50
/// How many channels load at once.
public let fetchConcurrency = 6

/// Run `worker` over `items` with at most `limit` at once, keeping order.
public func mapWithConcurrency<Item: Sendable, Result: Sendable>(
  _ items: [Item],
  limit: Int,
  _ worker: @escaping @Sendable (Item) async throws -> Result
) async throws -> [Result] {
  try await withThrowingTaskGroup(of: (Int, Result).self) { group in
    var results = [Result?](repeating: nil, count: items.count)
    var next = 0
    func startNext() {
      guard next < items.count else { return }
      let index = next
      let item = items[index]
      group.addTask { (index, try await worker(item)) }
      next += 1
    }
    for _ in 0..<min(limit, items.count) {
      startNext()
    }
    while let (index, result) = try await group.next() {
      results[index] = result
      startNext()
    }
    return results.compactMap { $0 }
  }
}

/// One channel's fetched items, with the mode they were fetched in.
public struct ChannelItems: Sendable, Hashable {
  /// Uploads or playlists.
  public var mode: ContentMode
  /// Whether the channel's Shorts list was read for them, so `isShort` is set
  /// wherever it can be.
  public var shorts: Bool
  /// The items, as fetched.
  public var items: [FeedItem]

  /// A channel's items fetched in `mode`.
  public init(mode: ContentMode, shorts: Bool = false, items: [FeedItem]) {
    self.mode = mode
    self.shorts = shorts
    self.items = items
  }
}

/// What a whole feed load found.
public struct FeedLoadResult: Sendable {
  /// The account's YouTube subscriptions.
  public var subscriptions: [Subscription]
  /// The channels with their filters, read again when the load finished so
  /// edits saved while it ran are in.
  public var channels: [ChannelFilter]
  /// Each fetched channel's items, by channel id.
  public var fetched: [String: ChannelItems]
  /// Channels that weren't fetched without failing the load.
  public var failed: Set<String>
  /// Whether YouTube's daily limit refused a request, after which none was
  /// sent.
  public var dailyLimit: Bool
}

/// Where a load reports as it goes, before it has finished.
public struct FeedLoadSink: Sendable {
  /// The channels with their filters, known before any items are.
  public var channels: @Sendable ([ChannelFilter]) async -> Void
  /// How many of the channels to fetch are finished, and how many there are;
  /// first with none finished, then once after each. Calls can arrive out of
  /// order, and start over when the load is retried.
  public var progress: @Sendable (_ finished: Int, _ total: Int) async -> Void

  /// A sink that hands the reports to these two.
  public init(
    channels: @escaping @Sendable ([ChannelFilter]) async -> Void,
    progress: @escaping @Sendable (_ finished: Int, _ total: Int) async -> Void = { _, _ in }
  ) {
    self.channels = channels
    self.progress = progress
  }
}

/// Whether a filter needs to know which videos are Shorts: uploads, with
/// Shorts hidden or the only ones shown (shared/fixtures/shorts.json).
public func needsShorts(_ filter: ChannelFilter) -> Bool {
  filter.contentMode != .playlists && filter.shortsFilter != .all
}

/// A channel's newest items: uploads or playlists, as its filter says. The
/// Shorts list is read only when the filter ``needsShorts(_:)``, and the
/// details of an upload in `known`, by video id, are not asked for.
public func fetchChannelItems(
  _ channel: ChannelFilter, client: YouTubeClient, probe: ShortsProbeFunction?,
  known: [String: VideoDetails] = [:]
) async throws -> ChannelItems {
  if channel.contentMode == .playlists {
    return ChannelItems(
      mode: .playlists,
      items: try await client.playlists(channelId: channel.channelId, channelTitle: channel.title)
        .map(FeedItem.playlist))
  } else {
    let shorts = needsShorts(channel)
    return ChannelItems(
      mode: .videos, shorts: shorts,
      items: try await client.uploads(
        channelId: channel.channelId, channelTitle: channel.title, maxResults: uploadsPerChannel,
        probe: probe, judgeShorts: shorts, known: known
      ).map(FeedItem.video))
  }
}

/// Uploads fetched without their channel's Shorts list, now with it: one
/// request, or none when no video could be a Short.
public func addShortsMarks(
  channelId: String, to fetched: ChannelItems, client: YouTubeClient, probe: ShortsProbeFunction?
) async throws -> ChannelItems {
  let videos = fetched.items.compactMap { item -> Video? in
    if case .video(let video) = item { video } else { nil }
  }
  return ChannelItems(
    mode: .videos, shorts: true,
    items: try await client.markShorts(
      videos, channelId: channelId, maxResults: uploadsPerChannel, probe: probe
    ).map(FeedItem.video))
}

/// Whether fetched items are what a filter needs: its mode, with Shorts marks
/// when it filters on them.
public func covers(_ fetched: ChannelItems, _ filter: ChannelFilter) -> Bool {
  fetched.mode == filter.contentMode && (fetched.shorts || !needsShorts(filter))
}

/// Fetches all of a channel's items.
public typealias FetchAllItems = @Sendable (ChannelFilter) async throws -> ChannelItems
/// Fetches the Shorts marks a channel's fetched uploads lack.
public typealias AddShortsMarks =
  @Sendable (ChannelFilter, ChannelItems) async throws -> ChannelItems

/// What a channel's filter needs, from what is already fetched for it where
/// that helps: nothing more, only the Shorts list, or everything.
public func completeItems(
  _ channel: ChannelFilter, have: ChannelItems?, fetchAll: FetchAllItems,
  addShorts: AddShortsMarks
) async throws -> ChannelItems {
  if let have, covers(have, channel) {
    return have
  } else if let have, have.mode == channel.contentMode {
    return try await addShorts(channel, have)
  } else {
    return try await fetchAll(channel)
  }
}

/// Channels' items fetched in the background before the feed opens, so setup
/// can fetch the channels left on while its later screens show.
///
/// ``fetchOnly(_:)`` names the channels to have, with the filters they will
/// be shown under; at most ``fetchConcurrency`` are fetched at a time. A
/// channel whose fetch fails has no items here and is left to the feed. Once
/// YouTube's daily limit refuses a request, nothing more is requested. The
/// load that gets it through ``loadFeed`` builds on ``items(_:)``.
public actor Prefetch {
  private final class Job {
    // the newest filter asked for; read when the job starts
    var channel: ChannelFilter
    // what an earlier job fetched or is fetching for the channel, to build on
    let before: Job?
    var started = false
    var outcome: ChannelItems??
    var waiters: [CheckedContinuation<ChannelItems?, Never>] = []

    init(channel: ChannelFilter, before: Job?) {
      self.channel = channel
      self.before = before
    }
  }

  private let fetchAll: FetchAllItems
  private let addShorts: AddShortsMarks
  // the newest job of every channel waiting, being fetched or fetched, wanted or not
  private var jobs: [String: Job] = [:]
  private var wanted = Set<String>()
  private var waiting: [Job] = []
  private var running = 0
  private var refused = false

  /// A prefetch that fetches a channel's items with `fetchAll`, and the
  /// Shorts marks fetched uploads lack with `addShorts`; it starts on nothing
  /// yet.
  public init(fetchAll: @escaping FetchAllItems, addShorts: @escaping AddShortsMarks) {
    self.fetchAll = fetchAll
    self.addShorts = addShorts
  }

  private func result(of job: Job) async -> ChannelItems? {
    if let outcome = job.outcome {
      return outcome
    } else {
      return await withCheckedContinuation { job.waiters.append($0) }
    }
  }

  private func settle(_ job: Job, _ outcome: ChannelItems?) {
    job.outcome = .some(outcome)
    for waiter in job.waiters {
      waiter.resume(returning: outcome)
    }
    job.waiters = []
  }

  /// Have exactly `channels`: what was fetched or is being fetched for them
  /// is kept, and added to when a channel's filter now needs more (the
  /// Shorts list, or its other content mode); the others among them are
  /// queued; and a channel not among them is taken out of the queue and has
  /// no items here.
  public func fetchOnly(_ channels: [ChannelFilter]) {
    wanted = Set(channels.map(\.channelId))
    for job in waiting where !wanted.contains(job.channel.channelId) {
      jobs[job.channel.channelId] = job.before
      if let before = job.before {
        Task { settle(job, await result(of: before)) }
      } else {
        settle(job, nil)
      }
    }
    waiting.removeAll { !wanted.contains($0.channel.channelId) }
    for channel in channels {
      let newest = jobs[channel.channelId]
      if let newest, !newest.started {
        newest.channel = channel
      } else if newest == nil || newest?.channel.contentMode != channel.contentMode
        || (needsShorts(channel) && !(newest.map { needsShorts($0.channel) } ?? false))
      {
        let job = Job(channel: channel, before: newest)
        jobs[channel.channelId] = job
        waiting.append(job)
      }
    }
    startWaiting()
  }

  private func startWaiting() {
    while running < fetchConcurrency, !waiting.isEmpty {
      let job = waiting.removeFirst()
      job.started = true
      running += 1
      Task {
        settle(job, await run(job))
        running -= 1
        startWaiting()
      }
    }
  }

  private func run(_ job: Job) async -> ChannelItems? {
    var have: ChannelItems?
    if let before = job.before {
      have = await result(of: before)
    }
    if refused {
      return have
    }
    do {
      return try await completeItems(
        job.channel, have: have, fetchAll: fetchAll, addShorts: addShorts)
    } catch {
      if case GoogleAPIError.dailyLimit = error {
        refused = true
      }
      loaderLog.error(
        "prefetch of \(job.channel.channelId, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      return have
    }
  }

  /// What was fetched for a channel, once its fetches end; nil when there is
  /// nothing.
  public func items(_ channelId: String) async -> ChannelItems? {
    if wanted.contains(channelId), let job = jobs[channelId] {
      return await result(of: job)
    } else {
      return nil
    }
  }
}

/// What fetching a load's channels came to.
public struct FetchedChannels: Sendable {
  /// Each fetched channel's items, by channel id.
  public var fetched: [String: ChannelItems] = [:]
  /// Channels that weren't fetched without ending the load; any makes it
  /// partial.
  public var failed = Set<String>()
  /// Whether YouTube's daily limit refused a request, after which none was
  /// sent.
  public var dailyLimit = false
}

private actor FetchTally {
  var tally = FetchedChannels()

  /// How many channels are fetched, failed or skipped.
  var finished: Int { tally.fetched.count + tally.failed.count }

  func fetched(_ channelId: String, _ items: ChannelItems) {
    tally.fetched[channelId] = items
  }

  /// Count a channel as failed; `dailyLimit` when that is why.
  func failed(_ channelId: String, dailyLimit: Bool = false) {
    tally.failed.insert(channelId)
    tally.dailyLimit = tally.dailyLimit || dailyLimit
  }
}

/// Fetch each channel with `fetchOne`, ``fetchConcurrency`` at a time. A
/// channel whose fetch fails is in `failed`; once one is refused for
/// YouTube's daily limit the rest aren't asked for and are in `failed` too. A
/// refused token or a missing permission ends the whole fetch. `finished` is
/// told how many channels are fetched, failed or skipped, after each one.
public func fetchChannels(
  _ channels: [ChannelFilter],
  finished: @escaping @Sendable (Int) async -> Void = { _ in },
  fetchOne: @escaping @Sendable (ChannelFilter) async throws -> ChannelItems
) async throws -> FetchedChannels {
  let tally = FetchTally()
  _ = try await mapWithConcurrency(channels, limit: fetchConcurrency) { channel -> Bool in
    if await tally.tally.dailyLimit {
      await tally.failed(channel.channelId)
      await finished(await tally.finished)
      return false
    }
    do {
      await tally.fetched(channel.channelId, try await fetchOne(channel))
      await finished(await tally.finished)
      return true
    } catch let error as GoogleAPIError where error == .tokenExpired || error == .insufficientScope {
      throw error
    } catch where isCancellation(error) {
      throw error
    } catch {
      loaderLog.error(
        "channel \(channel.channelId, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      var dailyLimit = false
      if case GoogleAPIError.dailyLimit = error {
        dailyLimit = true
      }
      await tally.failed(channel.channelId, dailyLimit: dailyLimit)
      await finished(await tally.finished)
      return false
    }
  }
  return await tally.tally
}

/// Whether an error only says the work was called off.
public func isCancellation(_ error: Error) -> Bool {
  error is CancellationError || (error as? URLError)?.code == .cancelled
}

private func loadOnce(
  token: String, store: SyncStore, probe: ShortsProbeFunction?, sink: FeedLoadSink,
  items wantsItems: Bool, prefetched: Prefetch?, known: [String: VideoDetails],
  session: URLSession
) async throws -> FeedLoadResult {
  let client = YouTubeClient(accessToken: token, session: session)
  async let subscribed = client.subscriptions()
  async let synced: Void = store.load()
  let subscriptions = try await subscribed
  try await synced
  let missing = await store.missingIdentities(subscriptions: subscriptions)
  if !missing.isEmpty {
    do {
      await store.remember(try await client.channelSummaries(missing))
    } catch let error as GoogleAPIError
      where error == .tokenExpired || error == .insufficientScope || error == .dailyLimit
    {
      throw error
    } catch {
      // the ids show until a later load gets the names
      loaderLog.error("channel names failed: \(String(describing: error), privacy: .public)")
    }
  }
  let channels = await store.channels(subscriptions: subscriptions)
  await sink.channels(channels)
  let wanted = wantsItems ? channels.filter(\.enabled) : []
  if wantsItems {
    await sink.progress(0, wanted.count)
  }
  let loaded = try await fetchChannels(
    wanted, finished: { await sink.progress($0, wanted.count) }
  ) { channel in
    try await completeItems(
      channel, have: await prefetched?.items(channel.channelId),
      fetchAll: { try await fetchChannelItems($0, client: client, probe: probe, known: known) },
      addShorts: {
        try await addShortsMarks(channelId: $0.channelId, to: $1, client: client, probe: probe)
      })
  }
  return FeedLoadResult(
    subscriptions: subscriptions,
    channels: await store.channels(subscriptions: subscriptions),
    fetched: loaded.fetched, failed: loaded.failed, dailyLimit: loaded.dailyLimit)
}

/// Load the feed: the subscriptions and the synced filters in parallel, then
/// every enabled channel's items, a few channels at a time; `items: false`
/// stops at the channels. What `prefetched` has for a channel is built on
/// instead of fetched again, and the details of a video in `known`, by video
/// id (``settledDetails(_:)`` of the videos already held), are not asked for.
/// A token that dies mid-load is renewed once and the load retried;
/// YouTube's daily limit is never retried.
public func loadFeed(
  tokens: any AccessTokenSource,
  store: SyncStore,
  probe: ShortsProbeFunction?,
  sink: FeedLoadSink,
  items: Bool = true,
  prefetched: Prefetch? = nil,
  known: [String: VideoDetails] = [:],
  session: URLSession = .shared
) async throws -> FeedLoadResult {
  do {
    return try await loadOnce(
      token: try await tokens.validToken(), store: store, probe: probe, sink: sink, items: items,
      prefetched: prefetched, known: known, session: session)
  } catch GoogleAPIError.tokenExpired {
    return try await loadOnce(
      token: try await tokens.refreshedToken(), store: store, probe: probe, sink: sink,
      items: items, prefetched: prefetched, known: known, session: session)
  }
}
