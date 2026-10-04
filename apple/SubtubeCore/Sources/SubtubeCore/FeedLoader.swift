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

/// What a whole feed load found.
public struct FeedLoadResult: Sendable {
  /// The account's YouTube subscriptions.
  public var subscriptions: [Subscription]
  /// The channels with their filters, read again when the load finished so
  /// edits saved while it ran are in.
  public var channels: [ChannelFilter]
  /// The channels whose items were fetched, with the filters they had then.
  public var fetched: [ChannelFilter]
  public var items: [FeedItem]
  /// Channels whose fetch failed without failing the load (e.g. a quota 403).
  public var failed: Set<String>
}

/// Where a load reports as it goes, before it has finished.
public struct FeedLoadSink: Sendable {
  /// The channels with their filters, known before any items are.
  public var channels: @Sendable ([ChannelFilter]) async -> Void

  public init(channels: @escaping @Sendable ([ChannelFilter]) async -> Void) {
    self.channels = channels
  }
}

/// One channel's feed entries: its uploads or its playlists.
public func fetchChannelItems(
  _ channel: ChannelFilter, client: YouTubeClient, probe: ShortsProbeFunction?
) async throws -> [FeedItem] {
  if channel.contentMode == .playlists {
    return try await client.playlists(channelId: channel.channelId, channelTitle: channel.title)
      .map(FeedItem.playlist)
  } else {
    return try await client.uploads(
      channelId: channel.channelId, channelTitle: channel.title, maxResults: uploadsPerChannel,
      probe: probe
    ).map(FeedItem.video)
  }
}

private func loadOnce(
  token: String, store: SyncStore, probe: ShortsProbeFunction?, sink: FeedLoadSink,
  items wantsItems: Bool, session: URLSession
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
    } catch let error as GoogleAPIError where error == .tokenExpired || error == .insufficientScope {
      throw error
    } catch {
      // the ids show until a later load gets the names
      loaderLog.error("channel names failed: \(String(describing: error), privacy: .public)")
    }
  }
  let channels = await store.channels(subscriptions: subscriptions)
  await sink.channels(channels)
  let wanted = wantsItems ? channels.filter(\.enabled) : []
  let failed = FailedChannels()
  let loaded = try await mapWithConcurrency(wanted, limit: fetchConcurrency) { channel -> [FeedItem] in
    do {
      return try await fetchChannelItems(channel, client: client, probe: probe)
    } catch let error as GoogleAPIError where error == .tokenExpired || error == .insufficientScope {
      throw error
    } catch {
      loaderLog.error(
        "channel \(channel.channelId, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      await failed.insert(channel.channelId)
      return []
    }
  }
  let failedIds = await failed.ids
  return FeedLoadResult(
    subscriptions: subscriptions,
    channels: await store.channels(subscriptions: subscriptions),
    fetched: wanted.filter { !failedIds.contains($0.channelId) },
    items: loaded.flatMap { $0 }, failed: failedIds)
}

private actor FailedChannels {
  var ids = Set<String>()
  func insert(_ id: String) { ids.insert(id) }
}

/// Load the feed: the subscriptions and the synced filters in parallel, then
/// every enabled channel's items, a few channels at a time; `items: false`
/// stops at the channels. A token that dies mid-load is renewed once and the
/// load retried.
public func loadFeed(
  tokens: any AccessTokenSource,
  store: SyncStore,
  probe: ShortsProbeFunction?,
  sink: FeedLoadSink,
  items: Bool = true,
  session: URLSession = .shared
) async throws -> FeedLoadResult {
  do {
    return try await loadOnce(
      token: try await tokens.validToken(), store: store, probe: probe, sink: sink, items: items,
      session: session)
  } catch GoogleAPIError.tokenExpired {
    return try await loadOnce(
      token: try await tokens.refreshedToken(), store: store, probe: probe, sink: sink,
      items: items, session: session)
  }
}
