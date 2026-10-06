/// The orders a channel list can be read in.
public enum ChannelSort: String, Codable, Sendable, CaseIterable {
  /// By each channel's newest fetched item.
  case newest
  /// By name, ignoring case.
  case name
  /// By how many unwatched items pass each channel's filter.
  case unwatched
}

/// What a channel list needs to know to place one channel.
public struct ChannelOrderEntry: Sendable, Hashable {
  /// The channel's id.
  public var id: String
  /// The channel's name.
  public var title: String
  /// Whether the main feed loads the channel.
  public var enabled: Bool
  /// The `publishedAt` of the channel's newest fetched item.
  public var newest: String?
  /// How many of the channel's unwatched fetched items pass its filter.
  public var unwatched: Int

  /// One channel's place in a list.
  public init(id: String, title: String, enabled: Bool, newest: String?, unwatched: Int = 0) {
    self.id = id
    self.title = title
    self.enabled = enabled
    self.newest = newest
    self.unwatched = unwatched
  }
}

/// The order of every channel list, as ids (shared/fixtures/channel-order.json).
///
/// Channels that are off go last, by name, in every sort. Those that are on
/// go, for `newest` (the default), by their newest fetched item, newest
/// first, whatever their filters and watched marks, then the ones with
/// nothing fetched; for `name`, by name; for `unwatched`, by
/// ``ChannelOrderEntry/unwatched``, most first, ties in `newest` order. By
/// name means by title ignoring case (``foldCase(_:)``), then by id.
public func channelOrder(_ channels: [ChannelOrderEntry], sort: ChannelSort = .newest) -> [String] {
  struct Keyed {
    var channel: ChannelOrderEntry
    var title: [Unicode.Scalar]
    // on with something fetched, on with nothing fetched
    var group: Int { channel.newest == nil ? 1 : 0 }
  }
  func byName(_ left: Keyed, _ right: Keyed) -> Bool {
    if left.title != right.title {
      return left.title.lexicographicallyPrecedes(right.title)
    } else {
      return left.channel.id.utf8.lexicographicallyPrecedes(right.channel.id.utf8)
    }
  }
  func byNewestVideo(_ left: Keyed, _ right: Keyed) -> Bool {
    if left.group != right.group {
      return left.group < right.group
    } else if left.group == 0, left.channel.newest != right.channel.newest {
      return (right.channel.newest ?? "").utf8
        .lexicographicallyPrecedes((left.channel.newest ?? "").utf8)
    } else {
      return byName(left, right)
    }
  }
  let sorted = channels
    .map { Keyed(channel: $0, title: foldCase($0.title)) }
    .sorted { left, right in
      if left.channel.enabled != right.channel.enabled {
        return left.channel.enabled
      } else if !left.channel.enabled || sort == .name {
        return byName(left, right)
      } else if sort == .unwatched, left.channel.unwatched != right.channel.unwatched {
        return left.channel.unwatched > right.channel.unwatched
      } else {
        return byNewestVideo(left, right)
      }
    }
  return sorted.map(\.channel.id)
}

/// The channels a channel list shows, in order, held while the list is on
/// screen so that a switch, a count or a filter edit never moves a row under
/// the hand or takes it away.
///
/// ``recompute(_:kept:)`` takes the order as ``channelOrder(_:sort:)`` gives
/// it now, less the channels the list's chips drop; a list does that when it
/// appears, after a full load, and when its sort, its chips or its search
/// change. In between, ``hold(_:kept:)`` keeps every row where it is:
/// channels that are gone leave, and new ones go to the end.
public struct HeldChannelOrder: Sendable, Hashable {
  /// The channel ids in the order shown.
  public private(set) var ids: [String] = []

  /// An order holding no channels yet.
  public init() {}

  /// Take `fresh`, the order as worked out now, less the channels not in
  /// `kept` (``chipKeptChannels(_:timeChip:topicChips:now:)``; nil keeps all).
  public mutating func recompute(_ fresh: [String], kept: Set<String>? = nil) {
    ids = fresh.filter { kept?.contains($0) ?? true }
  }

  /// Keep the rows shown for the channels in `fresh`, whether or not `kept`
  /// still has them, with the kept channels not shown before after them, in
  /// the order `fresh` has them.
  public mutating func hold(_ fresh: [String], kept: Set<String>? = nil) {
    let current = Set(fresh)
    let held = ids.filter(current.contains)
    let shown = Set(held)
    ids = held + fresh.filter { !shown.contains($0) && (kept?.contains($0) ?? true) }
  }
}
