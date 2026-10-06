/// A video this close to its end, in seconds, is watched.
public let finishedWithinSeconds = 10.0

extension WatchedEntry {
  /// How far the video has been played, in seconds; nil when the entry has
  /// no position or holds anything but a number that isn't negative.
  public var position: Double? {
    let seconds: Double?
    switch extra["position"] {
    case .integer(let whole): seconds = Double(whole)
    case .double(let fraction): seconds = fraction
    default: seconds = nil
    }
    return seconds.flatMap { $0 >= 0 ? $0 : nil }
  }
}

/// Whether a video is watched (shared/fixtures/watch-progress.json): marked
/// so, or played into the last ``finishedWithinSeconds`` of a length longer
/// than that.
public func isWatched(_ entry: WatchedEntry?, durationSeconds: Double = 0) -> Bool {
  if entry?.watched == true {
    return true
  } else if let position = entry?.position, durationSeconds > finishedWithinSeconds {
    return position >= durationSeconds - finishedWithinSeconds
  } else {
    return false
  }
}

/// Where a video starts when opened, in seconds: its position unless it is
/// watched.
public func resumePosition(_ entry: WatchedEntry?, durationSeconds: Double = 0) -> Double {
  if isWatched(entry, durationSeconds: durationSeconds) {
    return 0
  } else {
    return entry?.position ?? 0
  }
}

/// How full a video's progress bar is, from 0 to 1; nil for no bar.
public func progressFraction(_ entry: WatchedEntry?, durationSeconds: Double = 0) -> Double? {
  if isWatched(entry, durationSeconds: durationSeconds) {
    return 1
  } else if let position = entry?.position, durationSeconds > 0 {
    return min(1, position / durationSeconds)
  } else {
    return nil
  }
}

/// A watched entry after a mark at `now`: marking watched keeps its position,
/// unmarking drops it, or a position near the end would read as watched again.
/// Unknown fields are kept.
public func markedEntry(_ prior: WatchedEntry?, now: Int64, watched: Bool) -> WatchedEntry {
  var extra = prior?.extra ?? [:]
  if !watched {
    extra["position"] = nil
  }
  return WatchedEntry(at: now, watched: watched, extra: extra)
}

/// A watched entry after its video played to `position` seconds; `ended`
/// when the player reported the end, which alone marks it watched here.
/// Unknown fields are kept.
public func playedEntry(_ prior: WatchedEntry?, now: Int64, position: Int, ended: Bool)
  -> WatchedEntry
{
  var extra = prior?.extra ?? [:]
  extra["position"] = .integer(Int64(position))
  return WatchedEntry(at: now, watched: ended, extra: extra)
}
