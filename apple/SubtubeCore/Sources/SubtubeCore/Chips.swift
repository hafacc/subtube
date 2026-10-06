import Foundation

/// The topics: YouTube's fifteen video categories by `snippet.categoryId`,
/// with their labels (shared/fixtures/feed-chips.json).
public let categoryNames: [String: String] = [
  "1": "Film & Animation",
  "2": "Autos & Vehicles",
  "10": "Music",
  "15": "Pets & Animals",
  "17": "Sports",
  "19": "Travel & Events",
  "20": "Gaming",
  "22": "People & Blogs",
  "23": "Comedy",
  "24": "Entertainment",
  "25": "News & Politics",
  "26": "Howto & Style",
  "27": "Education",
  "28": "Science & Technology",
  "29": "Nonprofits & Activism",
]

/// A category id's label; nil for an id that is not one of the fifteen.
public func topicLabel(_ categoryId: String?) -> String? {
  categoryId.flatMap { categoryNames[$0] }
}

/// The ids among `categoryIds` that are topics, each once, in the order given.
public func knownTopics(_ categoryIds: [String]) -> [String] {
  var seen = Set<String>()
  return categoryIds.filter { topicLabel($0) != nil && seen.insert($0).inserted }
}

/// The time chips: how far back the feed reaches.
public enum TimeChip: String, Codable, Sendable, CaseIterable {
  /// All time.
  case anyTime = "none"
  case day
  case week
  /// 30 days.
  case month

  /// The span's length in milliseconds; nil for all time.
  public var milliseconds: Int64? {
    switch self {
    case .anyTime: nil
    case .day: 86_400_000
    case .week: 7 * 86_400_000
    case .month: 30 * 86_400_000
    }
  }
}

/// Where setup starts the feed: everything older is marked watched.
public enum StartFrom: String, Codable, Sendable, CaseIterable {
  case day
  case week
  /// Nothing is marked.
  case all

  /// The time chip that drops exactly what this starting point marks.
  public var timeChip: TimeChip {
    switch self {
    case .day: .day
    case .week: .week
    case .all: .anyTime
    }
  }
}

/// An RFC 3339 time, with or without fractional seconds, in milliseconds
/// since the epoch; nil when it isn't one.
public func parseTimestamp(_ text: String) -> Int64? {
  let date =
    (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    ?? (try? Date(text, strategy: .iso8601))
  return date.map { epochMilliseconds($0) }
}

/// Whether `publishedAt` is at or after `now` less the chip's span. A time
/// that can't be read is never within a span.
public func publishedWithin(_ publishedAt: String, _ timeChip: TimeChip, now: Int64) -> Bool {
  if let span = timeChip.milliseconds {
    if let published = parseTimestamp(publishedAt) {
      return now - published <= span
    } else {
      return false
    }
  } else {
    return true
  }
}

private func byCountThenLabel(_ counts: [String: Int]) -> [String] {
  counts
    .map { (id: $0.key, count: $0.value, label: foldCase(categoryNames[$0.key] ?? "")) }
    .sorted { left, right in
      if left.count != right.count {
        return left.count > right.count
      } else {
        return left.label.lexicographicallyPrecedes(right.label)
      }
    }
    .map(\.id)
}

private func countTopics(_ items: [FeedItem], into start: [String: Int]) -> [String: Int] {
  var counts = start
  for case let topic? in items.map(\.topic) {
    counts[topic, default: 0] += 1
  }
  return counts
}

/// The topic chips for a list, as category ids in row order: every topic an
/// item has plus every selected one, by how many items have it, most first,
/// then by label ignoring case.
public func chipRow(_ items: [FeedItem], selected: [String]) -> [String] {
  byCountThenLabel(
    countTopics(
      items, into: Dictionary(knownTopics(selected).map { ($0, 0) }) { first, _ in first }))
}

/// All fifteen topics for a channel's filter editor: by how many of its
/// fetched videos have each, most first, then by label.
public func editorTopics(_ items: [FeedItem]) -> [String] {
  byCountThenLabel(countTopics(items, into: categoryNames.mapValues { _ in 0 }))
}

/// The items the chips keep, in the order given: inside the time chip's
/// span, and in a selected topic when any is selected.
public func chipFiltered(
  _ items: [FeedItem], timeChip: TimeChip, topicChips: [String], now: Int64
) -> [FeedItem] {
  let wanted = Set(knownTopics(topicChips))
  return items.filter { item in
    publishedWithin(item.publishedAt, timeChip, now: now)
      && (wanted.isEmpty || item.topic.map(wanted.contains) ?? false)
  }
}

/// The items a channel list's chips look at, in the order given: of the
/// channels that are on, every fetched item of the kind the channel shows
/// that passes its filter, watched or not. `filters` and `modes` are by
/// channel id; a channel with no mode shows videos.
public func listedItems(
  _ items: some Sequence<FeedItem>, filters: [String: CompiledFilter],
  modes: [String: ContentMode]
) -> [FeedItem] {
  items.filter { item in
    if let filter = filters[item.channelId], filter.enabled {
      let shows: Bool
      switch item {
      case .video: shows = modes[item.channelId] != .playlists
      case .playlist: shows = modes[item.channelId] == .playlists
      }
      return shows && itemPassesFilter(item, filter)
    } else {
      return false
    }
  }
}

/// The channels a channel list's chips keep, by id
/// (shared/fixtures/channel-chips.json): those with at least one of `items`
/// that is inside the time chip's span and, when a topic is selected, in a
/// selected topic. Nil when no span and no topic is chosen, which keeps
/// every channel. `items` is ``listedItems(_:filters:modes:)``.
public func chipKeptChannels(
  _ items: [FeedItem], timeChip: TimeChip, topicChips: [String], now: Int64
) -> Set<String>? {
  if timeChip == .anyTime && knownTopics(topicChips).isEmpty {
    return nil
  } else {
    return Set(
      chipFiltered(items, timeChip: timeChip, topicChips: topicChips, now: now).map(\.channelId))
  }
}

/// The ids setup's starting point marks watched: every item published before
/// `now` less the span, whether or not it passes a filter.
public func startMarks(_ items: [FeedItem], start: StartFrom, now: Int64) -> [String] {
  if start == .all {
    return []
  } else {
    return items.filter { !publishedWithin($0.publishedAt, start.timeChip, now: now) }.map(\.id)
  }
}

private func pendingStartKey(_ accountId: String) -> String {
  "subtube.startFrom.\(accountId)"
}

/// Keep setup's starting point on this device for the account's next feed load.
public func keepPendingStart(
  accountId: String, start: StartFrom, defaults: UserDefaults = .standard
) {
  if start == .all {
    defaults.removeObject(forKey: pendingStartKey(accountId))
  } else {
    defaults.set(start.rawValue, forKey: pendingStartKey(accountId))
  }
}

/// Setup's starting point for the account, handed over once.
public func takePendingStart(accountId: String, defaults: UserDefaults = .standard) -> StartFrom {
  let key = pendingStartKey(accountId)
  let kept = defaults.string(forKey: key).flatMap(StartFrom.init(rawValue:))
  defaults.removeObject(forKey: key)
  return kept ?? .all
}
