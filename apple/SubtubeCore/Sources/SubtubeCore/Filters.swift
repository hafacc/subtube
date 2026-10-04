import Foundation

/// A channel filter made ready to apply.
public struct CompiledFilter: Sendable {
  public var enabled: Bool
  /// Nil when the filter has no pattern, or an invalid one (read as none).
  public var regex: NSRegularExpression?
  public var mode: FilterMode
  public var scope: FilterScope
  public var minDurationSeconds: Int
  public var liveFilter: LiveFilter
  public var shortsFilter: ShortsFilter
}

/// Compile a channel's filter. An invalid pattern reads as no pattern.
public func compileFilter(_ filter: ChannelFilter) -> CompiledFilter {
  CompiledFilter(
    enabled: filter.enabled,
    regex: filter.regex.isEmpty
      ? nil : compilePattern(filter.regex, caseSensitive: filter.caseSensitive),
    mode: filter.mode,
    scope: filter.searchScope,
    minDurationSeconds: filter.minDurationSeconds,
    liveFilter: filter.liveFilter,
    shortsFilter: filter.shortsFilter
  )
}

private func regexMatches(_ regex: NSRegularExpression, _ text: String) -> Bool {
  regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

/// Whether a feed item passes its channel's filter. The broadcast, Shorts and
/// duration gates apply to videos only, and run before the pattern.
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
  }
  guard let regex = compiled.regex else { return true }
  // Title and description are searched separately so a match can't span both.
  let matches =
    (compiled.scope != .description && regexMatches(regex, item.title))
    || (compiled.scope != .title && regexMatches(regex, item.description))
  if compiled.mode == .include {
    return matches
  } else {
    return !matches
  }
}

/// Where the filter's pattern first matches a title, for highlighting it; nil
/// when it has no pattern, matches only the description, or doesn't match.
public func titleMatchRange(_ title: String, _ compiled: CompiledFilter) -> Range<String.Index>? {
  guard let regex = compiled.regex, compiled.scope != .description,
    let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
    match.range.length > 0
  else {
    return nil
  }
  return Range(match.range, in: title)
}

/// Why a pattern can't be saved, or nil when it can (the empty pattern can).
public func patternError(_ pattern: String) -> String? {
  if isValidPattern(pattern) {
    return nil
  } else {
    return String(
      localized: "SubTube can't use this pattern, so it isn't saved.")
  }
}

/// What a channel's "mark all" button does, and to which ids.
public enum MarkAll: Sendable, Equatable {
  /// Mark these watched: the shown cards not watched yet. Empty when
  /// nothing is shown.
  case watched([String])
  /// Every shown card is watched already: take all their marks off.
  case unwatched([String])
}

/// Choose what "mark all" does, given the cards a channel's page shows.
public func markAll(shown: [FeedItem], watched: Set<String>) -> MarkAll {
  let ids = shown.map(\.id)
  let unwatched = ids.filter { !watched.contains($0) }
  if unwatched.isEmpty && !ids.isEmpty {
    return .unwatched(ids)
  } else {
    return .watched(unwatched)
  }
}
