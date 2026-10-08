/// The orders the feed can be read in.
public enum FeedSort: String, Codable, Sendable, CaseIterable {
  /// Newest first.
  case newest
  /// Oldest first.
  case oldest
  /// Shortest first; playlists and videos without a length last.
  case shortest
  /// Longest first; playlists and videos without a length still last.
  case longest
  /// By title, ignoring case.
  case title
  /// By title, ignoring case, from the end.
  case titleReversed
  /// In an order fixed by a seed.
  case random

  /// The order this one reverses; nil for an order that reverses none.
  public var forward: FeedSort? {
    switch self {
    case .oldest: .newest
    case .longest: .shortest
    case .titleReversed: .title
    case .newest, .shortest, .title, .random: nil
    }
  }
}

/// The sort chips, in row order: each holds an order and, after it, its
/// reverse. Random has none.
public let feedSortChips: [[FeedSort]] = [
  [.newest, .oldest], [.shortest, .longest], [.title, .titleReversed], [.random],
]

/// What a press of a sort chip does.
public enum SortChipPress: Sendable, Hashable {
  /// Order the feed this way.
  case choose(FeedSort)
  /// Put the random order in another random order.
  case reshuffle
}

/// What pressing the sort chip that shows `shown` does while the feed is in
/// the order `current`: an unselected chip is chosen as it shows, the
/// selected one turns round, and Random, which has no reverse, reshuffles.
public func sortChipPress(shown: FeedSort, current: FeedSort) -> SortChipPress {
  if let chip = feedSortChips.first(where: { $0.contains(shown) }), chip.contains(current) {
    if let other = chip.first(where: { $0 != current }) {
      return .choose(other)
    } else {
      return .reshuffle
    }
  } else {
    return .choose(shown)
  }
}

/// Newest first; equal times by id ascending. Both compare as plain ASCII.
/// Every other order ends in this one.
public func byNewest(_ left: FeedItem, _ right: FeedItem) -> Bool {
  if left.publishedAt != right.publishedAt {
    return right.publishedAt.utf8.lexicographicallyPrecedes(left.publishedAt.utf8)
  } else {
    return left.id.utf8.lexicographicallyPrecedes(right.id.utf8)
  }
}

/// Where the random order puts an item: the 32-bit FNV-1a hash of the UTF-8
/// bytes of the seed in decimal, a colon, and the item's id; smaller first.
public func shuffleKey(seed: UInt32, id: String) -> UInt32 {
  var hash: UInt32 = 2_166_136_261
  for byte in "\(seed):\(id)".utf8 {
    hash = (hash ^ UInt32(byte)) &* 16_777_619
  }
  return hash
}

/// A seed for the random order, picked anew at each full load and whenever
/// the user asks for another shuffle.
public func newShuffleSeed() -> UInt32 {
  UInt32.random(in: UInt32.min...UInt32.max)
}

/// A video's length in seconds; nil for a playlist or a video without one.
private func sortableDuration(_ item: FeedItem) -> Int? {
  if case .video(let video) = item, let seconds = video.durationSeconds, seconds != 0 {
    return seconds
  } else {
    return nil
  }
}

/// The items in one of the feed's orders (shared/fixtures/feed-order.json).
///
/// `newest` goes by `publishedAt`; `title` ignores case as
/// ``precedesIgnoringCase(_:_:)`` does; `shortest` goes by length, with
/// playlists and videos without one last; `random` goes by
/// ``shuffleKey(seed:id:)``, so it holds for as long as `seed` does.
/// `oldest`, `longest` and `titleReversed` turn the first key round and
/// nothing else: items without a length stay last, and ties in any order go
/// newest first, then by id (``byNewest(_:_:)``).
public func sortFeed(_ items: [FeedItem], by sort: FeedSort, seed: UInt32 = 0) -> [FeedItem] {
  struct Keyed {
    var item: FeedItem
    var title: [Unicode.Scalar] = []
    var shuffle: UInt32 = 0
    var duration: Int?
  }
  let forward = sort.forward ?? sort
  let reversed = forward != sort
  let keyed = items.map { item in
    switch forward {
    case .title: Keyed(item: item, title: foldCase(item.title))
    case .random: Keyed(item: item, shuffle: shuffleKey(seed: seed, id: item.id))
    case .shortest: Keyed(item: item, duration: sortableDuration(item))
    default: Keyed(item: item)
    }
  }
  /// Whether `left` goes first by the chosen order alone; nil on a tie.
  func primary(_ left: Keyed, _ right: Keyed) -> Bool? {
    switch forward {
    case .title:
      return left.title == right.title
        ? nil : left.title.lexicographicallyPrecedes(right.title) != reversed
    case .shortest:
      switch (left.duration, right.duration) {
      case (nil, nil): return nil
      case (nil, _): return false
      case (_, nil): return true
      case (let leftSeconds?, let rightSeconds?):
        return leftSeconds == rightSeconds ? nil : (leftSeconds < rightSeconds) != reversed
      }
    case .random:
      return left.shuffle == right.shuffle ? nil : left.shuffle < right.shuffle
    default:
      let leftTime = left.item.publishedAt
      let rightTime = right.item.publishedAt
      return !reversed || leftTime == rightTime
        ? nil : leftTime.utf8.lexicographicallyPrecedes(rightTime.utf8)
    }
  }
  return keyed
    .sorted { left, right in primary(left, right) ?? byNewest(left.item, right.item) }
    .map(\.item)
}
