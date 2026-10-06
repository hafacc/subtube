/// One part of the line that says what a channel's filter does.
public enum FilterSummaryPart: Sendable, Hashable {
  /// The channel shows playlists.
  case playlists
  /// The phrases the filter keeps or drops, and where it looks for them.
  case matching(phrases: [String], mode: FilterMode, scope: FilterScope)
  /// Shorts are hidden.
  case noShorts
  /// Only Shorts are shown.
  case shortsOnly
  /// Live videos are hidden.
  case noLive
  /// Only live videos are shown.
  case liveOnly
  /// Videos shorter than this many seconds are hidden.
  case hidesUnder(seconds: Int)
  /// The names of the topics videos are kept in, by name ignoring case.
  case topics([String])
  /// Nothing is filtered out.
  case allVideos
}

/// What a channel's filter does, in the order its editor lists the fields;
/// a filter that keeps everything is `allVideos` alone.
public func filterSummaryParts(_ channel: ChannelFilter) -> [FilterSummaryPart] {
  var parts: [FilterSummaryPart] = []
  if channel.contentMode == .playlists {
    parts.append(.playlists)
  }
  let phrases = patternToPhrases(channel.regex) ?? []
  if !phrases.isEmpty {
    parts.append(.matching(phrases: phrases, mode: channel.mode, scope: channel.searchScope))
  }
  // the editor has none of these fields for playlists
  if channel.contentMode != .playlists {
    switch channel.shortsFilter {
    case .all: break
    case .normal: parts.append(.noShorts)
    case .shorts: parts.append(.shortsOnly)
    }
    switch channel.liveFilter {
    case .all: break
    case .normal: parts.append(.noLive)
    case .vod: parts.append(.liveOnly)
    }
    if channel.minDurationSeconds > 0 {
      parts.append(.hidesUnder(seconds: channel.minDurationSeconds))
    }
    let topics = knownTopics(channel.topics).compactMap { topicLabel($0) }
    if !topics.isEmpty {
      parts.append(.topics(topics.sorted(by: precedesIgnoringCase)))
    }
  }
  if parts.isEmpty {
    parts.append(.allVideos)
  }
  return parts
}
