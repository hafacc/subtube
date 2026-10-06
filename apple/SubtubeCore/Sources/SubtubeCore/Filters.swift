import Foundation

/// A channel filter made ready to apply.
public struct CompiledFilter: Sendable {
  /// Whether the main feed loads the channel.
  public var enabled: Bool
  /// Nil when the filter has no pattern, or one that isn't phrases (read as
  /// none).
  public var regex: NSRegularExpression?
  /// Whether the pattern keeps or drops what it finds.
  public var mode: FilterMode
  /// What the pattern searches.
  public var scope: FilterScope
  /// Videos shorter than this many seconds are dropped; 0 keeps every length.
  public var minDurationSeconds: Int
  /// Which broadcast kinds are kept.
  public var liveFilter: LiveFilter
  /// Which of Shorts and other videos are kept.
  public var shortsFilter: ShortsFilter
  /// The categories kept; empty keeps every one.
  public var topics: Set<String>
}

/// Compile a channel's filter (shared/fixtures/filters.json). A pattern that
/// is not built from phrases reads as no pattern.
public func compileFilter(_ filter: ChannelFilter) -> CompiledFilter {
  CompiledFilter(
    enabled: filter.enabled,
    regex: phrasePatternOnly(filter.regex).isEmpty
      ? nil : compilePattern(filter.regex, caseSensitive: filter.caseSensitive),
    mode: filter.mode,
    scope: filter.searchScope,
    minDurationSeconds: filter.minDurationSeconds,
    liveFilter: filter.liveFilter,
    shortsFilter: filter.shortsFilter,
    topics: Set(knownTopics(filter.topics))
  )
}

private func regexMatches(_ regex: NSRegularExpression, _ text: String) -> Bool {
  regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

/// Whether a feed item passes its channel's filter. The broadcast, Shorts,
/// duration and topic gates apply to videos only, and run before the pattern.
public func itemPassesFilter(_ item: FeedItem, _ compiled: CompiledFilter) -> Bool {
  if case .video(let video) = item {
    // A channel that gates on Shorts also holds back what it couldn't judge,
    // so a Short never shows in a feed that drops them.
    if compiled.shortsFilter != .all {
      guard let isShort = video.isShort else { return false }
      if compiled.shortsFilter == .normal && isShort {
        return false
      }
      if compiled.shortsFilter == .shorts && !isShort {
        return false
      }
    }
    let status = video.liveStatus ?? .normal
    if status == .upcoming {
      return false
    }
    if compiled.liveFilter == .vod && status == .normal {
      return false
    }
    if compiled.liveFilter == .normal && status != .normal {
      return false
    }
    // An unknown duration (absent or 0, e.g. live) is kept.
    if compiled.minDurationSeconds > 0, let duration = video.durationSeconds, duration > 0,
      duration < compiled.minDurationSeconds
    {
      return false
    }
    if !compiled.topics.isEmpty && !(video.categoryId.map(compiled.topics.contains) ?? false) {
      return false
    }
  }
  if let regex = compiled.regex {
    // Title and description are searched separately so a match can't span both.
    let matches =
      (compiled.scope != .description && regexMatches(regex, item.title))
      || (compiled.scope != .title && regexMatches(regex, item.description))
    return matches == (compiled.mode == .include)
  } else {
    return true
  }
}
