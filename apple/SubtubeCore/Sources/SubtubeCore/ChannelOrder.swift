/// What a channel list needs to know to place one channel.
public struct ChannelOrderEntry: Sendable, Hashable {
  public var id: String
  public var title: String
  public var enabled: Bool
  /// The `publishedAt` of the newest item passing the channel's filter.
  public var newestPassing: String?

  public init(id: String, title: String, enabled: Bool, newestPassing: String?) {
    self.id = id
    self.title = title
    self.enabled = enabled
    self.newestPassing = newestPassing
  }
}

/// The order of every channel list, as ids.
///
/// Channels that are on with something passing come first, by their newest
/// passing item, newest first; then channels that are on with nothing
/// passing; then channels that are off. Ties and the two tail groups go by
/// title, ignoring case, then by id.
public func channelOrder(_ channels: [ChannelOrderEntry]) -> [String] {
  func group(_ channel: ChannelOrderEntry) -> Int {
    if !channel.enabled {
      return 2
    } else if channel.newestPassing == nil {
      return 1
    } else {
      return 0
    }
  }
  let sorted = channels.sorted { left, right in
    let leftGroup = group(left)
    let rightGroup = group(right)
    let leftTitle = left.title.lowercased()
    let rightTitle = right.title.lowercased()
    if leftGroup != rightGroup {
      return leftGroup < rightGroup
    } else if leftGroup == 0, left.newestPassing != right.newestPassing {
      return (right.newestPassing ?? "").utf8.lexicographicallyPrecedes((left.newestPassing ?? "").utf8)
    } else if leftTitle != rightTitle {
      return leftTitle < rightTitle
    } else {
      return left.id.utf8.lexicographicallyPrecedes(right.id.utf8)
    }
  }
  return sorted.map(\.id)
}
