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

  /// The video of a playlist that was playing, which ``position`` is into;
  /// nil when the entry has none or holds anything but a string.
  public var video: String? {
    extra["video"]?.stringValue
  }

  /// How far through a playlist that is, from 0 to 1; nil when the entry has
  /// none or holds anything but a number in that range.
  public var progress: Double? {
    let fraction: Double?
    switch extra["progress"] {
    case .integer(let whole): fraction = Double(whole)
    case .double(let part): fraction = part
    default: fraction = nil
    }
    return fraction.flatMap { $0 >= 0 && $0 <= 1 ? $0 : nil }
  }
}

/// Where in a playlist its player is.
public struct PlaylistPlace: Sendable, Equatable {
  /// The id of the playing video.
  public let video: String
  /// How far through the playlist that is, from 0 to 1
  /// (``playlistProgress(index:count:position:durationSeconds:)``).
  public let progress: Double

  /// A place in a playlist.
  public init(video: String, progress: Double) {
    self.video = video
    self.progress = progress
  }
}

/// How far through a playlist its player is, from 0 to 1, counting every
/// video as equally long (shared/fixtures/watch-progress.json): `position`
/// of `durationSeconds` into the video at `index`, from 0, of `count`.
public func playlistProgress(index: Int, count: Int, position: Double, durationSeconds: Double)
  -> Double
{
  if count <= 0 {
    return 0
  } else {
    let part = durationSeconds > 0 ? min(1, max(0, position / durationSeconds)) : 0
    return min(1, max(0, (Double(index) + part) / Double(count)))
  }
}

/// Where a playlist starts when opened.
public struct PlaylistStart: Sendable, Equatable {
  /// The place of the video to start at among the playlist's videos, from 0.
  public let index: Int
  /// How far into that video, in seconds.
  public let position: Double
}

/// Where a playlist starts when opened (shared/fixtures/watch-progress.json):
/// at the video that was playing, where it was left, when `videos`, the ids
/// its player loaded, still has it; otherwise, and when it is watched, at its
/// first video.
public func playlistStart(_ entry: WatchedEntry?, videos: [String]) -> PlaylistStart {
  if let entry, !entry.watched, let video = entry.video, let index = videos.firstIndex(of: video) {
    return PlaylistStart(index: index, position: entry.position ?? 0)
  } else {
    return PlaylistStart(index: 0, position: 0)
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

/// How full an item's progress bar is, from 0 to 1; nil for no bar. A
/// playlist, which has no length, shows its entry's progress.
public func progressFraction(_ entry: WatchedEntry?, durationSeconds: Double = 0) -> Double? {
  if isWatched(entry, durationSeconds: durationSeconds) {
    return 1
  } else if durationSeconds > 0 {
    return entry?.position.map { min(1, $0 / durationSeconds) }
  } else {
    return entry?.progress
  }
}

/// A watched entry after a mark at `now`: marking watched keeps its position
/// and its playlist's video and progress, unmarking drops them, or a position
/// near the end would read as watched again. Unknown fields are kept.
public func markedEntry(_ prior: WatchedEntry?, now: Int64, watched: Bool) -> WatchedEntry {
  var extra = prior?.extra ?? [:]
  if !watched {
    extra["position"] = nil
    extra["video"] = nil
    extra["progress"] = nil
  }
  return WatchedEntry(at: now, watched: watched, extra: extra)
}

/// A watched entry after its video played to `position` seconds; `ended`
/// when the player reported the end, which alone marks it watched here. A
/// playlist's entry also says where in it that was, `place`. Unknown fields
/// are kept.
public func playedEntry(
  _ prior: WatchedEntry?, now: Int64, position: Int, ended: Bool, place: PlaylistPlace? = nil
) -> WatchedEntry {
  var extra = prior?.extra ?? [:]
  extra["position"] = .integer(Int64(position))
  if let place {
    extra["video"] = .string(place.video)
    extra["progress"] = .double(place.progress)
  }
  return WatchedEntry(at: now, watched: ended, extra: extra)
}
